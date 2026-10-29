"""Strict, dependency-free server-card validator for examples and CI."""
import base64, glob, ipaddress, json, re, sys, os
os.chdir(os.path.dirname(__file__))
from urllib.parse import urlparse

HEX128 = re.compile(r"^[0-9a-fA-F]{128}$")
B64_32 = re.compile(r"^[A-Za-z0-9_-]{43}$")
B64_64 = re.compile(r"^[A-Za-z0-9_-]{86}$")
HOST = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$")

def check(d):
 e=[]
 req=['schema_version','id','server','game','loader','pack','update_policy','security','signing']
 if not isinstance(d,dict): return ['root not object']
 e += [f'missing {k}' for k in req if k not in d]
 if d.get('schema_version')!='1.0.0': e.append('schema_version must be 1.0.0')
 if not isinstance(d.get('id'),str) or not re.fullmatch(r'[a-z0-9][a-z0-9.-]{0,62}',d.get('id','')): e.append('invalid id')
 s=d.get('server',{}); add=s.get('addresses',[]) if isinstance(s,dict) else []
 if not add: e.append('addresses required')
 for a in add:
  if not isinstance(a,dict) or not isinstance(a.get('host'),str) or not HOST.fullmatch(a.get('host','')) or not isinstance(a.get('port'),int) or not 1<=a['port']<=65535: e.append('invalid address')
 g=d.get('game',{}); 
 if not isinstance(g.get('version'),str) or g.get('java_version') not in (8,17,21,25): e.append('invalid game')
 l=d.get('loader',{}); 
 if l.get('type') not in ('vanilla','fabric','quilt','forge','neoforge') or not isinstance(l.get('version'),str): e.append('invalid loader')
 p=d.get('pack',{}); u=p.get('url',''); ph=urlparse(u)
 if p.get('type') not in ('mrpack','packwiz') or ph.scheme!='https' or not ph.hostname or not HEX128.fullmatch(p.get('sha512','')): e.append('invalid pack')
 sec=d.get('security',{}); origin=sec.get('origin',''); oh=urlparse(origin).hostname
 if urlparse(origin).scheme!='https' or not oh or any('*' in h for h in sec.get('allowed_hosts',[])): e.append('origin/allowlist must be HTTPS and exact')
 hosts=sec.get('allowed_hosts',[])
 if not hosts or any(not isinstance(h,str) or not HOST.fullmatch(h) for h in hosts) or ph.hostname not in hosts: e.append('pack host outside allowlist')
 if sec.get('trust') not in ('tofu','pinned') or not isinstance(sec.get('max_bytes'),int) or sec['max_bytes']<1: e.append('invalid security')
 sig=d.get('signing',{})
 if sig.get('algorithm')!='ed25519' or not B64_32.fullmatch(sig.get('public_key','')) or not B64_64.fullmatch(sig.get('signature','')): e.append('invalid mandatory signature')
 if oh and oh not in hosts: e.append('origin host outside allowlist')
 return e

unexpected=0
for f in sorted(glob.glob('examples/*.json')):
 try: d=json.load(open(f)); errors=check(d)
 except Exception as ex: errors=[str(ex)]
 expected=any(x in f for x in ('malicious','invalid'))
 label='FAIL as expected' if expected and errors else 'PASS' if not expected and not errors else 'UNEXPECTED'
 print(f'{f}: {label}' + (f' ({"; ".join(errors)})' if errors and label!='PASS' else ''))
 unexpected += label=='UNEXPECTED'
if unexpected: sys.exit(1)
