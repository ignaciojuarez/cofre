# UPDATING.md: pulling upstream changes (runbook for an AI agent)

Goal: move `upstream/*` to newer upstream code, keep our patches working, and leave a branch that a human can merge.
**Rules**
- Never edit `upstream/` in place.
- Never commit `.work/`.
- Never copy StikDebug (AGPL) code into `app/` or `extensions/`.

| Upstream | Path | Track | License | Why we have it |
|---|---|---|---|---|
| Air (herbrine8403/Amethyst-iOS-MyRemastered) | `upstream/air` | newest semver tag | GPL-3.0 | Game engine and launcher screens |
| StikJIT | `upstream/stikjit` | `main` (no releases) | MPL-2.0 | JIT helper inside the PacketTunnel appex |
| StikDebug | `upstream/stikdebug` | newest tag | AGPL-3.0 | Fallback companion app only |

## 1. Run

```sh
scripts/update-upstream.sh all --dry-run   # fetch, patch, build, static smoke. Changes nothing
scripts/update-upstream.sh all             # same, then bump UPSTREAM.lock, prepend CHANGELOG.md, commit on branch upstream/YYYYMMDD
scripts/update-upstream.sh air --to=5.2.0  # pin a specific tag or SHA
```

| Exit | Meaning | Do this |
|---|---|---|
| 0 | Updated, or nothing new | Go to step 3 (device smoke) if anything changed |
| 1 | Preflight failed (dirty tree, missing tool) | Fix it and run again |
| 2 | Patch conflict | Step 2 |
| 3 | Build failed | Read the end of `.work/build.log`. If the error is in our code (`app/`, `extensions/`, `app/Glue/AirBridge.*`), fix it there. If it's in upstream, check upstream issues and CI. Still broken: `--to=<previous tag>` and add a `HOLD:` comment line in UPSTREAM.lock |
| 4 | Static smoke failed | Read `.work/smoke.log` and fix the cause. Never weaken a check |
| 5 | LICENSE changed, or upstream rewrote history | **Stop and ask a human** |

`! watch-listed files changed` is not an error. You must still read `.work/WATCH-<name>.txt` (step 4).

## 2. Conflicts (exit 2)

1. Read `.work/CONFLICT.md`. It shows the failing patch and the upstream commits that touched the same files.
2. Read the patch's `Reason:` line. **Does upstream now do this itself?** If yes, delete the patch, add a line to `patches/RETIRED.md` (`name: why dropped`), and run again.
3. If not, fix it in the worktree with the smallest change that keeps the same behavior:
   ```sh
   cd .work/<name>; git status                      # conflicted files
   # edit, then:
   git add -A && git am --continue
   cd - && scripts/update-upstream.sh <name> --export-patches && scripts/update-upstream.sh <name>
   ```
4. **Stop and ask a human** if:
   - the fix needs more than about 30 new lines;
   - a patch would grow past budget (5 patches or 200 lines per upstream);
   - the conflict touches the JIT protocol (`JIT26*`, `brk`, `UniversalJIT26*.js`, StikJIT script API), entitlements, or sign-in.
5. Prefer moving logic out of a patch and into `app/Glue/AirBridge.*` when you can.

## 3. Device smoke (about 10 min: iPhone 17 Pro, plus an older non-TXM phone when possible)

Install with `scripts/run.sh` (relay). Install over the existing app so data is kept. Write results under "Device smoke" in CHANGELOG.md.

- [ ] App opens. Setup shows Dev Mode, Pairing and VPN as ✓
- [ ] Settings → JIT → **Test JIT** = READY (log shows region and detach)
- [ ] Vanilla latest: title screen in under 90 s, walk around for 30 s
- [ ] Fabric instance with Sodium + Iris: world loads
- [ ] Modrinth: search and install one mod. CurseForge: search (needs the user's key)
- [ ] Import one `.mrpack`
- [ ] Microsoft account is still signed in (token refresh works)
- [ ] Send to background for 10 s and come back: no crash
- [ ] Settings → Logs → Share works

## 4. Changelog and watch list

- `CHANGELOG.md` gets an entry written for you. Shorten it to **at most 5 bullets a friend would care about**, and keep the `⚠ watch-listed` line.
- What to check for each watch-listed file:

| File changed | Check |
|---|---|
| `Natives/JavaLauncher.m`, `UniversalJIT26*.js`, StikJIT `Sources/` or `Resources/*.js` | Host and script protocol still match → Test JIT on the TXM phone is **mandatory** |
| `entitlements.*.xml`, `Info.plist` | Our signing overrides still apply |
| `MicrosoftAuthenticator.m` | Client ID or flow changed? Our config still wins |
| `CurseForgeAPI.m` | No key got compiled in. Mirror behavior is unchanged |
| `INTEGRATION.md` (StikJIT) | New required steps for the helper? |
| `LICENSE` | The script already stopped. A human decides |

## 5. Finish

- Push branch `upstream/YYYYMMDD` and open a PR titled `[REFACTOR] Pull upstream fixes: …`. The body has the CHANGELOG entry and the smoke results.
- After merge: `scripts/add-friend.sh --all` re-signs and uploads. Friends install the new link over the old app.
- Source offer: the release tag of our repo includes `UPSTREAM.lock`, `patches/` and the build scripts. `NOTICE.txt` in the app links to it. GPL/MPL/AGPL all require this for every build we hand out.
