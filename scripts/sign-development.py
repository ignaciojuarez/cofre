from pathlib import Path
import plistlib, subprocess, shutil
root=Path(__file__).resolve().parents[1]; app=root/'artifacts/Payload/Cofre.app'; appex=app/'PlugIns/PacketTunnel.appex'
products=root/'.build-tools/signing/build/Build/Products/Debug-iphoneos'
app_profile=products/'Cofre.app/embedded.mobileprovision'; tunnel_profile=products/'PacketTunnel.appex/embedded.mobileprovision'
if not app_profile.exists() or not tunnel_profile.exists(): raise SystemExit('build .build-tools/signing first to generate both profiles')
identity='Apple Development: Ignacio Juarez (SIGNING_IDENTITY)'; bundle='com.ignaciojuarez.cofre'
def profile_ent(path): return plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(path)]))['Entitlements']
ae=dict(profile_ent(app_profile)); te=dict(profile_ent(tunnel_profile))
for e in (ae,te): assert e.get('get-task-allow') is True
assert ae.get('com.apple.developer.kernel.increased-memory-limit') is True
assert ae.get('com.apple.developer.kernel.extended-virtual-addressing') is True
assert 'packet-tunnel-provider' in te.get('com.apple.developer.networking.networkextension', [])
assert ae.get('application-identifier') == 'APPLE_TEAM_ID.'+bundle
assert te.get('application-identifier') == 'APPLE_TEAM_ID.'+bundle+'.tunnel'
assert 'OLD_DEVICE_UDID' in plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app_profile)]))['ProvisionedDevices']
info=plistlib.loads((app/'Info.plist').read_bytes()); info['CFBundleIdentifier']=bundle; info['CFBundleDisplayName']='Cofre'; (app/'Info.plist').write_bytes(plistlib.dumps(info)); (app/'embedded.mobileprovision').write_bytes(app_profile.read_bytes())
# Appex first, as required by iOS nested-code verification.
if not appex.exists(): raise SystemExit('missing PacketTunnel.appex in Cofre.app/PlugIns')
(appex/'embedded.mobileprovision').write_bytes(tunnel_profile.read_bytes())
for f in sorted(appex.rglob('*'), key=lambda p: len(p.parts)):
    if f.is_file() and not f.is_symlink() and 'Mach-O' in subprocess.check_output(['file','-b',str(f)],text=True): subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(f)],check=True)
subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--entitlements',str(root/'Tunnel.entitlements') if (root/'Tunnel.entitlements').exists() else str(root/'.build-tools/signing/Tunnel.entitlements'),str(appex)],check=True)
for f in sorted(app.rglob('*'), key=lambda p: len(p.parts)):
    if appex in f.parents or f == appex: continue
    if f.is_file() and not f.is_symlink() and 'Mach-O' in subprocess.check_output(['file','-b',str(f)],text=True): subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(f)],check=True)
ent=root/'artifacts/Development.entitlements'; plistlib.dump(ae,ent.open('wb'))
subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--generate-entitlement-der','--entitlements',str(ent),str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(appex)],check=True); subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
for p in (appex,app):
    print('---',p); subprocess.run(['codesign','-d','--entitlements',':-',str(p)],check=False)
