from pathlib import Path
import plistlib, subprocess
root=Path(__file__).resolve().parents[1]; app=root/'artifacts/Payload/Cofre.app'
profile=next(root.glob('upstream/air/.build-tools/signing/build/Debug-iphoneos/*/embedded.mobileprovision'),None)
if not profile: raise SystemExit('missing development profile; build Air first')
identity='Apple Development: Ignacio Juarez (SIGNING_IDENTITY)'; bundle='com.ignaciojuarez.cofre'; tunnel='com.ignaciojuarez.cofre.tunnel'
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile)])); e=dict(p['Entitlements'])
for key in ('get-task-allow','com.apple.developer.kernel.increased-memory-limit','com.apple.developer.kernel.extended-virtual-addressing'):
    assert e.get(key) is True, key
assert 'OLD_DEVICE_UDID' in p['ProvisionedDevices']
e['application-identifier']='APPLE_TEAM_ID.'+bundle; e['keychain-access-groups']=['APPLE_TEAM_ID.'+bundle]
ent=root/'artifacts/Development.entitlements'; plistlib.dump(e,ent.open('wb'))
info=plistlib.loads((app/'Info.plist').read_bytes()); info['CFBundleIdentifier']=bundle; info['CFBundleDisplayName']='Cofre'; (app/'Info.plist').write_bytes(plistlib.dumps(info)); (app/'embedded.mobileprovision').write_bytes(profile.read_bytes())
appex=app/'PlugIns/PacketTunnel.appex'
if appex.exists():
    ae=dict(e); ae['com.apple.developer.networking.networkextension']=['packet-tunnel-provider']; aet=root/'artifacts/Tunnel.entitlements'; plistlib.dump(ae,aet.open('wb'))
    for f in appex.rglob('*'):
        if f.is_file() and not f.is_symlink() and 'Mach-O' in subprocess.check_output(['file','-b',str(f)],text=True): subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(f)],check=True)
    subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--entitlements',str(aet),str(appex)],check=True)
for f in app.rglob('*'):
    if f.is_file() and not f.is_symlink() and 'Mach-O' in subprocess.check_output(['file','-b',str(f)],text=True): subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(f)],check=True)
subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--generate-entitlement-der','--entitlements',str(ent),str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('signed Cofre; tunnel must be embedded and signed before host')
