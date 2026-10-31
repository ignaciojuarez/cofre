#!/usr/bin/env python3
"""Exercise the launch bridge's real renderer profile handoff on macOS."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "app/Glue/AirBridge/AirBridgeAdapter.m").read_text()
method = source[source.index("- (BOOL)pickRendererForProfile:"):]
handoff = method[method.index("  BOOL explicit ="):]
handoff = handoff[:handoff.index("    NSMutableDictionary *profiles")] + "  }\n"
harness = r'''
#import <Foundation/Foundation.h>
static NSMutableDictionary *apply(NSDictionary *before, NSString *pick) {
  NSMutableDictionary *profile = [before mutableCopy];
HANDOFF
  return profile;
}
int main(void) { @autoreleasepool {
  for (NSArray *pair in @[
      @[@"metallum", @"libmetallum.dylib"],
      @[@"mobileglues", @"libmobileglues.dylib"],
      @[@"zink", @"libOSMesa.8.dylib"]]) {
    NSDictionary *before = @{@"renderer": pair[0], @"javaVersion": @"25"};
    NSDictionary *after = apply(before, pair[1]);
    NSCAssert([after[@"renderer"] isEqual:pair[1]], @"Alias reached Air: %@", after);
    NSCAssert(!after[@"cofreRendererPicked"], @"Explicit choice became Auto");
    NSCAssert([after[@"javaVersion"] isEqual:@"25"], @"Java choice changed");
    NSCAssert([apply(after, pair[1]) isEqual:after], @"Not idempotent");
  }
  NSDictionary *automatic = apply(@{}, @"libmetallum.dylib");
  NSCAssert([automatic[@"cofreRendererPicked"] boolValue], @"Auto provenance lost");
  NSDictionary *fallback = apply(@{@"renderer": @"metallum"}, @"libmobileglues.dylib");
  NSCAssert([fallback[@"renderer"] isEqual:@"libmobileglues.dylib"], @"Resolved fallback ignored");
} }
'''.replace("HANDOFF", handoff)
with tempfile.TemporaryDirectory(prefix="cofre-renderer-") as directory:
    tree = Path(directory)
    (tree / "check.m").write_text(harness)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation",
                    str(tree / "check.m"), "-o", str(tree / "check")], check=True)
    subprocess.run([str(tree / "check")], check=True)
print("PASS: explicit renderer aliases and fallbacks reach Air as dylib names")
