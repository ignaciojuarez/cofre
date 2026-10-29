# Updating upstream dependencies

`scripts/update-upstream.sh` updates the three pinned submodules without editing them in place. It fetches tags, selects the newest semver tag for Air and StikDebug (or `main` for StikJIT), applies our patches in a temporary `.work/<name>` worktree, checks the diff, and records a status file in `.work/`.

```sh
scripts/update-upstream.sh all --dry-run   # fetch and validate; no lockfile/changelog commit
scripts/update-upstream.sh air --to=5.2.0 # select a tag or commit
scripts/update-upstream.sh all             # update UPSTREAM.lock and prepend CHANGELOG.md
```

Exit codes are 0 for success or no changes, 1 for an invalid option or missing lockfile, and 2 when a patch cannot be applied. A conflict status is left in `.work/update-<name>.conflict`; normal patch status is `.work/update-<name>.status`. The script uses UTC ISO-8601 timestamps and does not commit `.work/`.

Before merging an update, run `scripts/smoke.sh`, `scripts/lint.sh`, and `scripts/test.sh`. Review changes to licenses, entitlements, sign-in, and JIT protocol files with a human. Never copy StikDebug code into the app or extensions, and never commit build products.
