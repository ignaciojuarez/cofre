# Auto-triage: from a user's problem to a reviewed PR

Goal: when a player hits a problem, one tap sends a full, private-by-default report. An agent on the Mac mini diagnoses it and opens a draft PR with a status and a confidence score, and Ignacio reviews it. No paid services.

## Flow

```
iPhone: crash screen or Settings › Report a problem
  └─ builds report.zip (report.json + trimmed logs), shows a preview, the user taps Send
       ├─ A: email (default; no account needed) → reports@ mailbox
       └─ B: prefilled GitHub issue (people with GitHub accounts)
A home Mac: a T3 scheduled task every 15 min
  ├─ reads new mail (hostinger-mail) and opens/updates a GitHub issue with `gh` (Ignacio's own auth)
  ├─ deduplicates by crash signature: a repeat becomes a comment, "+1 (3 devices)"
  └─ starts one agent per new signature, in its own worktree
Agent (GPT, high/xhigh)
  ├─ reads the report and the code, finds the cause, writes the fix and tests
  └─ opens a draft PR "Fixes #N" with the status block below, labels it needs-review
Ignacio: reviews on the phone, then merges or asks the agent to revise
```

## Why this transport

| Option | Cost | Needs | Verdict |
|---|---|---|---|
| Email with attachment → mailbox the Mac mini reads | Free (existing mailbox) | Mail app on the phone | ✅ Default. Private, full logs, no account |
| Prefilled GitHub issue URL | Free | A GitHub account; URL ≈ 8 KB, so summary only and the zip attached by hand | ✅ Fallback |
| App posts to the GitHub API | Free | A token inside the app | ❌ Never embed secrets |
| Own server or a serverless worker | Free tier or paid | Hosting, plus a public endpoint on the Mac mini | ❌ Not now |

## report.json: the context the agent needs

| Group | Fields |
|---|---|
| App | Cofre version and build commit, Air commit, patches hash, install date |
| Device | Model (iPhone18,x), iOS version and build, RAM, free disk, thermal state, Low Power Mode, JIT mode (TXM/attached), VPN up |
| Instance | MC version, loader and version, mods (name, version, Modrinth/CF id, on/off), resource and shader packs, renderer (chosen → resolved), Java runtime, RAM setting → heap, JVM args, FPS cap, resolution scale, language |
| Session | Launch stages with timestamps, first-frame time, input mode, keyboard events, exit code, classified reason and clue, crash signature |
| Breadcrumbs | Cofre actions (`[Cofre] action …`), plus the **options.txt diff between launch and exit** (e.g. `graphicsMode: fast → fancy`) |
| Logs | latestlog.txt with Metallum per-frame spam dropped (it was 7 MB in 3 min); MC latest.log tail; crash-reports/*; hs_err_pid*.log |

**Signature:** a hash of the reason, the top native frame or Java exception with its top frame, the MC version and the renderer. One signature means one issue.

## Privacy, on by default

- Redact before zipping: access tokens, UUIDs, xuid, player name (becomes `player`), IPs and server addresses, emails, and container UUIDs in paths.
- The preview screen shows exactly what's sent. The user can remove logs and still send the summary.
- Nothing is sent automatically. The user always taps Send.

## PR status block (the agent writes it)

```
Status: fix ready | needs device test | needs info | not ours (upstream)
Confidence: 0–100% with a one-line reason
Root cause: one paragraph with the evidence lines from the report
Fix: files changed and why
Risk: what could break
Verify: exact steps and the log lines to check on a device
```

## Build order

1. **Breadcrumbs.** Add `[Cofre] action` lines, an options.txt diff at exit, and log the Cofre version/build at start. This is small and helps today.
2. **report.zip + preview + email/issue send** from the crash screen and Settings, with redaction tests.
3. **Mac mini routine** (T3 scheduled task): mail → issue → dedupe → agent → draft PR. The runbook lives in `ROUTINE.md`.
4. A Metallum log level (performance plan #4), so logs stay small and readable.

## Open questions

- Which mailbox receives reports (e.g. a new reports@ address)?
- Can users email without a GitHub account? This is assumed yes.
- Should the issues be public (the repo is public once published)? Reports are redacted, but private issues on a second repo is an option.
