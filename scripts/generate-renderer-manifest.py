#!/usr/bin/env python3
"""Emit capability facts from the exact Metallum jar shipped in the app."""
import hashlib, json, os, sys, zipfile
jar = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'upstream/air/JavaApp/libs/others/metallum_agent.jar')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'artifacts/Payload/AngelAuraAmethyst.app/RendererManifest.json')
versions, integrations, classes = set(), {}, {}
with zipfile.ZipFile(jar) as z:
    for n in z.namelist():
        if not n.startswith('classes') or n.endswith('/'):
            continue
        prefix = n.split('/', 1)[0]
        classes[prefix] = classes.get(prefix, 0) + 1
        key = prefix.removeprefix('classes')
        mapping = {'12111_1_21_11':'1.21.11', '261':'26.1', '262':'26.2', '262iris':'26.2', '263':'26.3', '264':'26.4'}
        version = next((v for p,v in mapping.items() if key.startswith(p)), None)
        if version:
            versions.add(version)
            low = n.lower() + prefix.lower()
            for name in ('iris','sodium','mixin'):
                if name in low:
                    integrations.setdefault(name, set()).add(version)
hashv = hashlib.sha256(open(jar,'rb').read()).hexdigest()
manifest = {'renderer':'Metal','engineRevision':'ship-derived','artifactSHA256':hashv,
            'gameVersions':sorted(versions), 'integrations':{k:sorted(v) for k,v in integrations.items()},
            'features':sorted(k for k in ('compute','ssbo','imageLoadStore') if k in integrations), 'limits':{}, 'classes':classes}
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out,'w') as f: json.dump(manifest,f,sort_keys=True,indent=2); f.write('\n')
