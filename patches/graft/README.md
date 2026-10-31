# Graft patches

`scripts/graft.sh` clones Graft (LGPL-3.0, `v1.1.1` = `4386b98`) into `.work/graft`, applies these patches in order and
builds the Minecraft 1.21.11 Fabric jar for iOS. The jar keeps Graft's `LICENSE` (as `LICENSE_graft`) and a
`COFRE-NOTICE.md` describing the modification. Source and jar stay out of git. Same rules as Air: at most 5 patches,
each with `Reason:` and `Drop when:`.

| Patch | Why |
|---|---|
| 0001 | Present through Air's published UIView/CAMetalLayer (main-queue layer writes), iOS MSL target, launcher's iOS shaderc/SPIRV-Cross, 1.21.11-only build |

Device run (DEBUG build): `scripts/graft.sh`, then `scripts/graft.sh serve` (prints a scenario with this Mac's LAN
address), then `scripts/scenario.sh /tmp/graft-build/fabric-1.21.11-graft.json` from another terminal.
