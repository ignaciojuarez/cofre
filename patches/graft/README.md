# Graft patches

`scripts/graft.sh` clones Graft (LGPL-3.0, `v1.1.1` = `4386b98`) into `.work/graft`, applies these patches in order and
builds the Minecraft 1.21.11 Fabric jar for iOS. The jar keeps Graft's `LICENSE` (as `LICENSE_graft`) and a
`COFRE-NOTICE.md` describing the modification. Source and jar stay out of git. Same rules as Air: at most 5 patches,
each with `Reason:` and `Drop when:`.

| Patch | Why |
|---|---|
| 0001 | Present through Air's published UIView/CAMetalLayer (main-queue layer writes), iOS MSL target, launcher's iOS shaderc/SPIRV-Cross, 1.21.11-only build |

Device run (DEBUG build): `scripts/graft.sh`, then
`COFRE_PUSH=/tmp/graft-build/graft-ios-1.21.11-1.1.1-cofre.1.jar scripts/scenario.sh scripts/scenarios/fabric-1.21.11-graft.json`
(the jar is copied into the app's Documents; no network needed).
