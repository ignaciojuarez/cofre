# Edge cases and handling

| Case | Handling |
|---|---|
| Server offline/card URL down | Show cached last-known card with age; allow cancel/offline launch only if profile is already installed; retry with backoff. |
| MC/loader mismatch | Block join; offer a new per-server profile and show exact versions. |
| CurseForge third-party restriction | Do not proxy; request user CF key or browser download, then verify hash. |
| iOS-unsupported mod | Compatibility catalog blocks it; show replacement/exclusion and server compatibility risk. |
| Dependency conflict | SAT-like resolution over pack lock; show conflicting IDs/versions; no partial install. |
| Server swaps loader/MC mid-season | New signed card version creates staged profile generation; preserve old profile for rollback. |
| Low storage | Calculate download + extracted + rollback reserve; prompt cleanup or stop before download. |
| Interrupted download | Background URLSession resume; discard failed stage, retain old profile. |
| Whitelist rejects player | Join error includes address, account and whitelist guidance; do not retry-install. |
| Velocity/Bungee network | Card may list `network`; resolve backend card after transfer and select profile by backend address/card id. |
| Pack changes in game | Never mutate running profile; notify and apply next launch. |
| User modified profile | Three-way/hash-aware merge; preserve config/worlds/optional mods; require consent on conflicts. |
| Same pack used by two servers | Cache payload by SHA; profiles remain separate and each card owns update policy. |
| Optional mods conflict | Defaults are off unless `defaultEnabled`; show incompatibility before enabling. |
| Server and card push same resource pack | Deduplicate by hash; server-required wins and card duplicate is hidden; differing hashes are shown as a conflict. |
| Signature key rotates | Accept only signed `rotatesTo`; show fingerprint and require confirmation if pin changes. |
| Malicious manifest/zip | Enforce schema, HTTPS/allowlist, hashes, caps, path/symlink checks, no scripts; quarantine and report. |
