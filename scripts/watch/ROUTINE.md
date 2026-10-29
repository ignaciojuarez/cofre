# Weekly upstream check (runbook)

The scheduled "Cofre upstream spy" task follows this file. Change the process here, not in the task prompt.

## Run
1. Run `scripts/upstream-report.sh` from the repo root. It fetches refs only (no checkouts, no pin changes, no commits) and writes `artifacts/upstream-report.md`.
2. Read the per-upstream verdict:
   - `no action`: nothing to do.
   - `worth pulling`: say which upstream, how many commits, and which watched paths changed. Suggest running `scripts/update-upstream.sh <name>` (see `UPDATING.md`).
   - `needs a human`: say why (license change, patch conflict, or a JIT, entitlement or sign-in path changed). Don't try to fix it.
3. Also flag the report line "Air quiet ≥ 90 days → consider re-basing on Amethyst" when it appears (rule in `plan/UPSTREAM_STRATEGY.md`).

## State
`.work/watch/last-run.json` (gitignored) holds the last run time, the verdict per upstream, and a one-line summary. Read it first. Update it after the report is written. Only report a `worth pulling` that's still unchanged since last week as "still pending" (one line), not as new.

## Never
- Update pins, apply patches for real, commit, push, build, or install. Those happen in a normal session with the owner.

## Retire
Delete the scheduled task and this file if Cofre stops tracking upstreams.
