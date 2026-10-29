"""Builds ../gallery.html from icons.json (written by make_icons.py). Inline SVG only."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, 'icons.json')))
TOP = list(D['extras'])
REASON = {
    '01': 'Instantly reads as "the chest" at any size.',
    '02': 'Most ownable: dark, glowing, stands out on any page.',
    '03': 'Tells the story: open it and your mods come out.',
}

sym = []
for i in D['icons']:
    n = i['num']
    if i.get('flat'):
        sym.append(f'<symbol id="i{n}" viewBox="0 0 1024 1024">{D["flat"].format(id="fbg")}</symbol>')
        continue
    sym.append(f'<symbol id="b{n}" viewBox="0 0 32 32"><g fill="none">{i["bg"]}</g></symbol>')
    sym.append(f'<symbol id="f{n}" viewBox="0 0 32 32"><g fill="none">{i["fg"]}</g></symbol>')
for n, e in D['extras'].items():
    sym.append(f'<symbol id="t{n}" viewBox="0 0 32 32"><g fill="none">{e["tint"]}</g></symbol>')
sym.append(f'<symbol id="bd" viewBox="0 0 32 32"><g fill="none">{D["darkbg"]}</g></symbol>')


def icon(n, size, layers=None, cls='ic'):
    if n == '09':
        body, sr = '<use href="#i09" width="1024" height="1024"/>', ''
        vb = '0 0 1024 1024'
    else:
        layers = layers or [f'b{n}', f'f{n}']
        body = ''.join(f'<use href="#{l}" width="32" height="32"/>' if l != 'black'
                       else '<rect width="32" height="32" fill="#000"/>' for l in layers)
        vb, sr = '0 0 32 32', ' shape-rendering="crispEdges"'
    return f'<span class="{cls}" style="width:{size}px"><svg viewBox="{vb}" width="{size}" height="{size}"{sr}>{body}</svg></span>'


cards = ''.join(
    f'<div class="card">{icon(i["num"], 150)}<div class="nm">{i["num"]} · {i["name"]}'
    f'{" <span class=top>★ Top 3</span>" if i["num"] in TOP else ""}</div><div class="nt">{i["note"]}</div></div>'
    for i in D['icons'])
row = ''.join(icon(i['num'], 60) for i in D['icons'])
names = {i['num']: i['name'] for i in D['icons']}
tops = ''
for n in TOP:
    looks = [('Default', None), ('Dark', ['bd', f'f{n}']), ('Tinted', ['black', f't{n}']),
             ('Background', [f'b{n}']), ('Foreground', [f'f{n}'])]
    cells = ''.join(f'<figure>{icon(n, 72, l, "ic" if k != "Foreground" else "ic fgl")}<figcaption>{k}</figcaption></figure>'
                    for k, l in looks)
    tops += f'<div class="tp"><div class="nm">{n} · {names[n]}</div><div class="nt">{REASON[n]}</div><div class="looks">{cells}</div></div>'

html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cofre · app icon options</title>
<style>
html,body{{margin:0}}
body{{font-family:var(--font-sans);color:var(--foreground)}}
.wrap{{max-width:728px;margin:0 auto;padding:24px 0 32px}}
h1{{font-size:22px;line-height:1.2;margin:0 0 4px}}
h2{{font-size:15px;margin:32px 0 4px}}
.sub,.nt,figcaption,.cap{{color:var(--muted-foreground)}}
.sub{{font-size:14px;margin:0 0 20px}}
.cap{{font-size:12px;margin:0 0 10px}}
.grid{{display:grid;grid-template-columns:repeat(4,150px);justify-content:space-between;row-gap:22px}}
.ic{{display:block;overflow:hidden;border-radius:22.4%;line-height:0;flex:none}}
.ic svg{{display:block}}
.ic.fgl{{border-radius:0}}
.nm{{font-size:14px;font-weight:600;margin-top:8px}}
.nt{{font-size:12px;line-height:1.35;margin-top:2px}}
.top{{font-weight:500;font-size:12px}}
.wall{{padding:16px;border-radius:var(--radius);display:grid;grid-template-columns:repeat(5,60px);justify-content:space-around;row-gap:20px;margin-bottom:12px}}
.wall.dark{{background:linear-gradient(160deg,#2a1d5e 0%,#121024 55%,#4a2070 100%)}}
.wall.light{{background:linear-gradient(160deg,#f6f2ff 0%,#ddd2ff 55%,#ffdcc8 100%)}}
.tp{{margin-top:14px}}
.looks{{display:flex;gap:22px;margin-top:8px}}
figure{{margin:0}}
figcaption{{font-size:11px;margin-top:5px;text-align:center}}
</style></head><body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>{''.join(sym)}</defs></svg>
<div class="wrap">
<h1>Cofre · app icon options</h1>
<p class="sub">Purple chest, original 32×32 pixel art (no Mojang textures). 1024 PNGs sit next to this file.</p>
<div class="grid">{cards}</div>
<h2>Home screen at 60 px</h2>
<p class="cap">01 → 10, left to right, top to bottom.</p>
<div class="wall dark">{row}</div>
<div class="wall light">{row}</div>
<h2>Top 3 · appearances and layers</h2>
<p class="cap">Dark and tinted for iOS 18+; background and foreground layers for Icon Composer.</p>
{tops}
</div>
</body></html>
'''
out = os.path.join(os.path.dirname(HERE), 'gallery.html')
open(out, 'w').write(html)
print(out, len(html.encode()), 'bytes')
