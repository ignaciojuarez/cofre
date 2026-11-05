# Metallum patches (Cofre Metallum)

`scripts/metallum.sh` builds Cofre's iOS Metallum (MIT, https://github.com/kokodio/metallum) for Minecraft 26.2 and
26.3. Upstream has no 26.2 branch, so each version is its own pinned commit in its own clone:

| MC | Commit | Upstream state |
|---|---|---|
| 26.3 | `467d312` | `v0.0.25` (`4da72f5`) + `5bee03e` (lock in `getOrCompileFunction`) |
| 26.2 | `a12ffb3` | "MRT": last 26.2 commit, already on metal-jvm (never tagged; `v0.0.24` predates metal-jvm) |

Patches named `*-mcX.Y-*` apply only to that version; the others apply to both. Each jar keeps Metallum's
`LICENSE_metallum` and adds `COFRE-NOTICE.md`; metal-jvm (MIT, unmodified) is nested as upstream does. Metallum is pure
FFM, so there is no native dylib: Air's `Frameworks/libmetallum.dylib` (MetalUniversal's) is not used. Source and jars
stay out of git. Same rules as Air: at most 5 patches, each with `Reason:` and `Drop when:`.

| Patch | Why |
|---|---|
| 0001 | Shared `IosHost` (iOS detection, Air's published UIView/CAMetalLayer, per-frame autorelease pool, launcher's SPIRV-Cross) + `COFRE-NOTICE.md` |
| 0002 | 26.3: host layer instead of an SDL Metal view, no Objective-C blocks (poll command-buffer status), iOS MSL, no `displaySyncEnabled` on iOS, deferred pipeline release (reload crash), jar name + notice |
| 0003 | 26.2: the same on the GLFW/NSView path, plus upstream's `getOrCompileFunction` lock |

Output: `/tmp/metallum-build/metallum-cofre-mc{26.2,26.3}-0.0.25-cofre.1.jar` (`METALLUM_OUT` overrides). The Fabric
mod id stays `metallum`, so `MetalMod` detection keeps working. Findings and what still needs a device:
`plan/reviews/cofre-metallum.md`.
