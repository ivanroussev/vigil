# Claude Notch

A pill around the MacBook notch, plus a menu bar progress bar, showing what Claude Code is doing.

| Pill | Meaning |
|---|---|
| Coral, pulsing | Working. Grows as plan steps complete; shows `3/8` or elapsed time |
| Amber ✋ | Needs your approval or input |
| Lavender ? | Looks stuck: no activity for 10 min (30 min inside a long command), or the same step failed / repeated 3× |
| Green ✓ | Finished (fades after 30 min) |

Small dots next to the pill are your other running sessions.

**Hover** the pill for the card: task, current action, heartbeat, step list, elapsed, ETA,
context window use, finish summary (files, +/− lines, tool calls), other sessions, and today's total.
**Click** the pill or a session to bring its app (Claude desktop or your terminal) to the front.

**Approve from the notch:** when Claude asks permission for a tool, the card opens with the full
command and Allow / Deny. It waits up to 60s (`NOTCH_APPROVE_WAIT`); with no answer, Claude's
normal dialog takes over. Questions and plan approvals always stay in Claude. It never approves on its own,
and Claude's deny rules still apply.

**ETA** blends this task's pace with your past seconds-per-step (after 3 finished planned tasks).

Menu bar: progress bar, today's total, previews of each state, Sounds, Launch at login, Quit.
The pill is hidden from screen sharing / recordings and doesn't cover fullscreen apps.

## How it works

1. `hooks/notch-hook.sh` runs on Claude Code events and writes
   `~/.claude/notch/sessions/<session>.json`; finished tasks are appended to `~/.claude/notch/history.jsonl`.
2. `hooks/approve.sh` handles permission requests through `~/.claude/notch/requests/` and `responses/`.
3. `ClaudeNotch.app` reads those files twice a second.

## Setup

```bash
./scripts/install-hooks.sh   # adds the hooks to ~/.claude/settings.json (original kept as .bak-notch)
./scripts/build.sh           # builds build/ClaudeNotch.app
open build/ClaudeNotch.app
```

Debug: `touch ~/.claude/notch/.debug` logs raw hook events to `~/.claude/notch/debug.log`.

## Known limits

- The context window size isn't in the transcript, so it's assumed 200k unless usage goes past it (then 1M).
- Clicking brings the right app forward but can't pick the exact Claude desktop session (no deep link for that).
- Whether Claude shows its own permission dialog while the notch is waiting isn't documented; if it doesn't,
  answering in Claude can take up to 60s to appear. Lower `NOTCH_APPROVE_WAIT` if that bothers you.
