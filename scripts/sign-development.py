#!/usr/bin/env python3
import os
import plistlib
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / "artifacts/Payload/Cofre.app"
appex = app / "PlugIns/PacketTunnel.appex"
products = root / ".build-tools/signing/build/Build/Products/Debug-iphoneos"
app_profile = products / "Cofre.app/embedded.mobileprovision"
tunnel_profile = products / "PacketTunnel.appex/embedded.mobileprovision"

if not app_profile.exists() or not tunnel_profile.exists():
    raise SystemExit("build .build-tools/signing first to generate both profiles")
identity = os.environ.get("SIGNING_IDENTITY") or sys.exit("SIGNING_IDENTITY is required")
team = os.environ.get("TEAM_ID") or sys.exit("TEAM_ID is required")
bundle = os.environ.get("BUNDLE_ID", "com.ignaciojuarez.cofre")
tunnel_bundle = os.environ.get("TUNNEL_BUNDLE_ID", "com.ignaciojuarez.cofre.tunnel")
if not bundle.startswith("com.") or not tunnel_bundle.startswith(bundle + "."):
    raise SystemExit("invalid bundle IDs")


def profile_ent(path):
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", str(path)])
    return plistlib.loads(decoded)["Entitlements"]


def sign_macho(tree, skip=None):
    for path in sorted(tree.rglob("*"), key=lambda p: len(p.parts)):
        if skip and (path == skip or skip in path.parents):
            continue
        if path.is_file() and not path.is_symlink():
            kind = subprocess.check_output(["file", "-b", str(path)], text=True)
            if "Mach-O" in kind:
                subprocess.run(["codesign", "--force", "--sign", identity, "--timestamp=none", str(path)], check=True)


ae = dict(profile_ent(app_profile))
te = dict(profile_ent(tunnel_profile))
for entitlements in (ae, te):
    assert entitlements.get("get-task-allow") is True
assert ae.get("com.apple.developer.kernel.increased-memory-limit") is True
assert ae.get("com.apple.developer.kernel.extended-virtual-addressing") is True
assert "packet-tunnel-provider" in te.get("com.apple.developer.networking.networkextension", [])
assert ae.get("application-identifier") == team + "." + bundle
assert te.get("application-identifier") == team + "." + tunnel_bundle

device = os.environ.get("RELAY_DEVICE_ID", "")
if device:
    profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(app_profile)]))
    if device not in profile["ProvisionedDevices"]:
        raise SystemExit("device is not provisioned")

if not appex.exists():
    raise SystemExit("missing appex")
info = plistlib.loads((app / "Info.plist").read_bytes())
info["CFBundleIdentifier"] = bundle
info["CFBundleDisplayName"] = "Cofre"
(app / "Info.plist").write_bytes(plistlib.dumps(info))
(app / "embedded.mobileprovision").write_bytes(app_profile.read_bytes())
(appex / "embedded.mobileprovision").write_bytes(tunnel_profile.read_bytes())

sign_macho(appex)
tunnel_entitlements = root / "Tunnel.entitlements"
if not tunnel_entitlements.exists():
    tunnel_entitlements = root / ".build-tools/signing/Tunnel.entitlements"
subprocess.run([
    "codesign", "--force", "--sign", identity, "--timestamp=none", "--entitlements",
    str(tunnel_entitlements), str(appex)
], check=True)
sign_macho(app, skip=appex)
ent = root / "artifacts/Development.entitlements"
with ent.open("wb") as handle:
    plistlib.dump(ae, handle)
subprocess.run([
    "codesign", "--force", "--sign", identity, "--timestamp=none", "--generate-entitlement-der",
    "--entitlements", str(ent), str(app)
], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(appex)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
for path in (appex, app):
    print("---", path)
    subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], check=False)
