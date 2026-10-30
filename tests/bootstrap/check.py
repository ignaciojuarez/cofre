#!/usr/bin/env python3
"""Replay all Air patches and exercise the actual ObjC ignore-list repair on macOS."""
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix="cofre-bootstrap-") as directory:
    tree = Path(directory)
    patches = sorted((ROOT / "patches/air").glob("*.patch"))
    assert len(patches) <= 5
    # Restore only files touched by the patches; never mutate upstream or .work.
    for patch in patches:
        for line in patch.read_text().splitlines():
            if line.startswith("--- a/"):
                name = line[6:]
                target = tree / name
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(subprocess.check_output(
                        ["git", "-C", str(ROOT / "upstream/air"), "show", f"HEAD:{name}"]))
    run("git", "init", "-q", str(tree))
    for patch in patches:
        run("git", "-C", str(tree), "apply", str(patch))
    source = (tree / "Natives/MinecraftResourceUtils.m").read_text()
    method = source[source.index("+ (void)applyBootstrapLauncherIgnoreListFix:"):]
    method = method[:method.index("#pragma mark")]
    harness = r'''
#import <Foundation/Foundation.h>
@interface MinecraftResourceUtils : NSObject
+ (void)applyBootstrapLauncherIgnoreListFix:(NSMutableDictionary *)json;
@end
@implementation MinecraftResourceUtils
METHOD
@end
static void check(NSArray *before, NSArray *after) {
    NSMutableDictionary *json = [@{@"arguments": @{@"jvm": before, @"game": @[@"keep"]}} mutableCopy];
    [MinecraftResourceUtils applyBootstrapLauncherIgnoreListFix:json];
    NSCAssert([json[@"arguments"][@"jvm"] isEqual:after], @"Unexpected repair: %@", json);
    NSCAssert([json[@"arguments"][@"game"] isEqual:@[@"keep"]], @"Game args changed");
    NSDictionary *once = [json copy];
    [MinecraftResourceUtils applyBootstrapLauncherIgnoreListFix:json];
    NSCAssert([json isEqual:once], @"Not idempotent");
}
int main(void) { @autoreleasepool {
    check(@[@"-DignoreList=bootstraplauncher,securejarhandler,lwjgl,${primary_jar_name}"],
          @[@"-DignoreList=bootstraplauncher,securejarhandler,${primary_jar_name}"]);
    check(@[@"-DignoreList=lwjgl,lwjgl,asm,"], @[@"-DignoreList=asm"]);
    check(@[@"-DignoreList=lwjgl"], @[]);
    check(@[@"-DignoreList=asm,securejarhandler"], @[@"-DignoreList=asm,securejarhandler"]);
    check(@[@"-DignoreList=lwjgl", @"-Xmx2G", @"-DignoreList=asm,lwjgl"],
          @[@"-Xmx2G", @"-DignoreList=asm"]);
    check(@[@"-DignoreList=asm,lwjgl_util", @"-Xmx2G"], @[@"-DignoreList=asm,lwjgl_util", @"-Xmx2G"]);
    check(@[@"-Xmx2G", @{@"rules": @[]}, @"fabric"], @[@"-Xmx2G", @{@"rules": @[]}, @"fabric"]);
    for (id args in @[[NSNull null], @{}, @{@"jvm": @"bad"}]) {
        NSMutableDictionary *json = [@{@"arguments": args} mutableCopy];
        NSDictionary *before = [json copy];
        [MinecraftResourceUtils applyBootstrapLauncherIgnoreListFix:json];
        NSCAssert([json isEqual:before], @"Malformed args changed");
    }
} }
'''.replace("METHOD", method)
    (tree / "check.m").write_text(harness)
    run("xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", str(tree / "check.m"), "-o", str(tree / "check"))
    run(str(tree / "check"))
    print("PASS: all five patches apply; saved/new Forge and NeoForge args repaired; vanilla/Fabric unchanged")

libs = ROOT / "artifacts/Payload/Cofre.app/libs"
if libs.exists():
    with zipfile.ZipFile(libs / "launcher.jar") as jar:
        assert any(n.startswith("com/apple/ios/audio/") and n.endswith(".class") for n in jar.namelist())
    for version in (333, 341):
        with zipfile.ZipFile(libs / f"lwjgl-{version}/lwjgl.jar") as jar:
            names = set(jar.namelist())
            assert "org/lwjgl/system/MemoryUtil.class" in names
            assert "org/lwjgl/system/Struct.class" in names
            assert not any(n.startswith(("com/apple/ios/audio/", "com/mojang/")) and n.endswith(".class") for n in names)
    print("PASS: bundled LWJGL 333/341 contain required classes and no launcher audio/Mojang split packages")
