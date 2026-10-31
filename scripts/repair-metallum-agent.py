#!/usr/bin/env python3
"""Repair the classes Air's metallum_agent.jar references but does not ship, then verify the jar.

  scripts/repair-metallum-agent.py <jar>            repair in place (idempotent), then verify
  scripts/repair-metallum-agent.py --check <jar>    verify only; exit 1 on a dangling reference

Air's agent picks one class set per Minecraft version (classes12111_1_21_11/, classes262iris/,
classes263/, ...) and defines its com/metallum/client/, com/metallum/shims/, com/metallum/Metallum
and Fabric API stubs into the game's class loader. Everything else, including com/metallum/agent/,
comes from the jar root through the app class loader, which has no Minecraft libraries.
Three gaps crash vanilla Metal (plan/reviews/metal-mods.md):
  * 1.21.11 and 26.2: their Metallum implements the Fabric API interfaces, but only classes261/263/264
    bundle those stubs. Metallum then falls back to the root copy, whose static init needs slf4j:
    NoClassDefFoundError org/slf4j/LoggerFactory. Stubs are copied from classes263/.
  * 1.21.11: MetalDevice calls com/metallum/agent/ShaderVersionBump, which no Air jar has ever had.
    Cofre compiles its own (app/Glue/MetallumAgent) into the jar root.
  * 1.21.11: Metallum calls `new NopLogger()`, but the root NopLogger has a private constructor.
    Root members a class set uses that are private are made public.
"""
import os, struct, subprocess, sys, tempfile, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUMP_SOURCE = os.path.join(ROOT, 'app/Glue/MetallumAgent/com/metallum/agent/ShaderVersionBump.java')
BUMP_CLASS = 'com/metallum/agent/ShaderVersionBump.class'
STUB_SOURCE = 'classes263/'
STUB_PREFIX = 'net/fabricmc/'
OWN = 'com/metallum/'
ROOT_ONLY = 'com/metallum/agent/'  # never defined from a class set
ENTRY_TIME = (2026, 10, 31, 0, 0, 0)  # fixed, so repeated builds give identical bytes
ACC_PUBLIC, ACC_PRIVATE, ACC_PROTECTED = 0x1, 0x2, 0x4
SIZES = {3: 4, 4: 4, 5: 8, 6: 8, 8: 2, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}


def parse(data):
    """The parts of a class file this script needs, plus where each member's access flags live."""
    u2 = lambda at: struct.unpack('>H', data[at:at + 2])[0]
    count, at, index = u2(8), 10, 1
    utf8, cls, refs, nat = {}, {}, [], {}
    while index < count:
        tag = data[at]
        if tag == 1:
            utf8[index] = data[at + 3:at + 3 + u2(at + 1)].decode('utf-8', 'replace')
            at += 3 + u2(at + 1)
        elif tag == 7:
            cls[index] = u2(at + 1)
            at += 3
        elif tag in (9, 10, 11):
            refs.append((u2(at + 1), u2(at + 3)))
            at += 5
        elif tag == 12:
            nat[index] = (u2(at + 1), u2(at + 3))
            at += 5
        else:
            at += 1 + SIZES[tag]
        index += 2 if tag in (5, 6) else 1
    names = {i: utf8[n] for i, n in cls.items()}
    superclass, interface_count = u2(at + 4), u2(at + 6)
    interfaces = [names[u2(at + 8 + 2 * k)] for k in range(interface_count)]
    at += 8 + 2 * interface_count
    members = {}
    for _ in range(2):  # fields, then methods
        member_count, at = u2(at), at + 2
        for _ in range(member_count):
            members[(utf8[u2(at + 2)], utf8[u2(at + 4)])] = (u2(at), at)
            attribute_count, at = u2(at + 6), at + 8
            for _ in range(attribute_count):
                at += 6 + struct.unpack('>I', data[at + 2:at + 6])[0]
    return {'super': names.get(superclass), 'interfaces': interfaces, 'classes': set(names.values()),
            'refs': [(names[c], utf8[nat[n][0]], utf8[nat[n][1]]) for c, n in refs], 'members': members}


def widen(data, wanted):
    """The class with the given members made public."""
    out = bytearray(data)
    for flags, at in (parse(data)['members'][key] for key in wanted):
        struct.pack_into('>H', out, at, (flags & ~(ACC_PRIVATE | ACC_PROTECTED)) | ACC_PUBLIC)
    return bytes(out)


class Jar:
    def __init__(self, z):
        self.z, self.entries, self.cache = z, set(z.namelist()), {}
        self.sets = sorted({n.split('/', 1)[0] + '/' for n in self.entries if n.startswith('classes') and '/' in n})

    def own(self, prefix):
        """The set's classes the agent defines into the game loader."""
        return sorted(n[len(prefix):-6] for n in self.entries if n.startswith(prefix + OWN)
                      and not n.startswith(prefix + ROOT_ONLY) and n.endswith('.class'))

    def entry(self, prefix, name):
        """The jar entry the game loader ends up with for a class, or None."""
        paths = [name + '.class'] if name.startswith(ROOT_ONLY) else [prefix + name + '.class', name + '.class']
        return next((p for p in paths if p in self.entries), None)

    def cls(self, path):
        if path not in self.cache:
            self.cache[path] = parse(self.z.read(path))
        return self.cache[path]

    def private_root_uses(self, prefix):
        """{root entry: {(name, descriptor)}} for private root members a class set references."""
        found = {}
        for name in self.own(prefix):
            for owner, member, desc in self.cls(prefix + name + '.class')['refs']:
                path = self.entry(prefix, owner) if owner.startswith(OWN) and owner != name else None
                while path and not path.startswith(prefix):
                    info = self.cls(path)
                    if (member, desc) in info['members']:
                        if info['members'][(member, desc)][0] & ACC_PRIVATE:
                            found.setdefault(path, set()).add((member, desc))
                        break
                    path = self.entry(prefix, info['super']) if info['super'] else None
        return found

    def problems(self):
        found = []
        for prefix in self.sets:
            for name in self.own(prefix):
                info = self.cls(prefix + name + '.class')
                wanted = {c for c in info['classes'] if c.startswith(OWN)}
                if name == 'com/metallum/Metallum':
                    wanted |= set(info['interfaces'])  # needed to define it in the game loader at all
                found += [f'{prefix}{name} -> class {c}' for c in sorted(wanted) if not self.entry(prefix, c)]
            # Member existence is not checked: interface default methods and constant-pool entries
            # that Air's own rewrite left unused make it noisy. Private access across loaders is exact.
            for path, members in sorted(self.private_root_uses(prefix).items()):
                found += [f'{prefix} -> private {path[:-6]}.{m}{d}' for m, d in sorted(members)]
        return found


def compile_bump(out_dir):
    """Compile with the first JDK 21+ found (Air's BOOTJDK is JDK 8, so it cannot be the default)."""
    homes = [os.environ.get('JAVA_HOME', '')]
    try:
        homes.append(subprocess.run(['/usr/libexec/java_home', '-v', '21+'], capture_output=True, text=True).stdout.strip())
    except OSError:
        pass
    for javac in [os.path.join(h, 'bin', 'javac') for h in homes if h] + ['javac']:
        try:
            if subprocess.run([javac, '--release', '21', '-nowarn', '-d', out_dir, BUMP_SOURCE]).returncode == 0:
                with open(os.path.join(out_dir, BUMP_CLASS), 'rb') as f:
                    return f.read()
        except OSError:
            continue
    sys.exit('repair-metallum-agent: needs a JDK 21+ javac (set JAVA_HOME)')


def repair(path):
    added, replaced, widened = {}, {}, {}
    with zipfile.ZipFile(path) as z:
        jar = Jar(z)
        stubs = {n[len(STUB_SOURCE):]: z.read(n) for n in jar.entries
                 if n.startswith(STUB_SOURCE + STUB_PREFIX) and n.endswith('.class')}
        for prefix in jar.sets:
            metallum = prefix + 'com/metallum/Metallum.class'
            if metallum in jar.entries and any(i.startswith(STUB_PREFIX) and not jar.entry(prefix, i)
                                               for i in jar.cls(metallum)['interfaces']):
                if not stubs:
                    sys.exit(f'{path}: no Fabric API stubs under {STUB_SOURCE} to copy')
                added.update({prefix + n: data for n, data in stubs.items() if prefix + n not in jar.entries})
            for entry, members in jar.private_root_uses(prefix).items():
                widened.setdefault(entry, set()).update(members)
        for entry, members in widened.items():
            replaced[entry] = widen(z.read(entry), members)
        if BUMP_CLASS not in jar.entries:
            with tempfile.TemporaryDirectory(prefix='cofre-metallum-') as tmp:
                added[BUMP_CLASS] = compile_bump(tmp)
        if not added and not replaced:
            return
        temporary = path + '.repair'
        with zipfile.ZipFile(temporary, 'w') as out:
            for info in z.infolist():  # same order, so META-INF/MANIFEST.MF stays first
                copy = zipfile.ZipInfo(info.filename, info.date_time)
                copy.compress_type, copy.external_attr = info.compress_type, info.external_attr
                out.writestr(copy, replaced.get(info.filename) or z.read(info))
            for name in sorted(added):
                out.writestr(zipfile.ZipInfo(name, ENTRY_TIME), added[name], zipfile.ZIP_DEFLATED)
    os.replace(temporary, path)
    for name in sorted(widened):
        print(f'metallum_agent.jar: made public {name[:-6]}.' + ', '.join(m + d for m, d in sorted(widened[name])))
    for name in sorted(added):
        print(f'metallum_agent.jar: added {name}')


def main(argv):
    check_only = argv[:1] == ['--check']
    args = argv[1:] if check_only else argv
    if len(args) != 1:
        sys.exit('usage: repair-metallum-agent.py [--check] <metallum_agent.jar>')
    if not check_only:
        repair(args[0])
    with zipfile.ZipFile(args[0]) as z:
        missing = Jar(z).problems()
    for line in missing:
        print(f'metallum_agent.jar: {line}', file=sys.stderr)
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
