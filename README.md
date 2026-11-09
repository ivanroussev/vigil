# Vigil

**Your MacBook notch keeps watch over Claude Code.**

You give Claude Code a long task and then… wait. Is it almost done? Stuck on a failing test? Waiting
on a permission prompt you can't see? Vigil turns the notch into a live status display, so you
know at a glance without switching windows.

<!-- demo: docs/demo.gif (10–15s: pill working → hover card → done) -->

## What it shows

| Notch | Meaning |
|---|---|
| White ring, spinning | Working. The ring and pill grow as plan steps complete (`3/8`) |
| Yellow `!`, blinking ring | Needs you: a permission prompt or a question |
| Lavender `?` | Looks stuck (see below) |
| Teal `✓` | Finished |

Small dashes next to the pill are your other running sessions. The menu bar shows the same thing
in text: `◔ 3/8 ~6m`.

## What makes it different

- **Knows when your agent is stuck.** No activity for 10 minutes (30 inside a long command),
  or the same step failing or repeating 3× in a row, turns the pill lavender with the reason.
- **Learns how long your tasks take.** The time-left estimate blends the current pace with your own
  history of seconds per step.
- **Approve from the notch.** Permission requests drop down with the full command and Allow / Deny.
- **Tells you what happened.** When a task finishes: files changed, `+312 −48` lines, tool calls, time taken.
- **Keeps a daily log.** "Today: 3h 20m across 9 tasks."

Hover the pill for the full card: the step checklist, current action, last activity,
elapsed time, ETA, context window usage, other sessions. Click it to jump back to Claude.

## Install

Needs macOS 14+ on any Mac (on Macs without a notch the pill sits under the menu bar), the Xcode
Command Line Tools (`xcode-select --install`) and `jq` (built into macOS 15+, else `brew install jq`).

```bash
git clone https://github.com/ivanroussev/vigil.git
cd vigil
./install.sh
```

That builds the app into `~/Applications`, adds the hooks to `~/.claude/settings.json` (your original
is saved once as `settings.json.bak-vigil`) and turns on launch at login (`--no-login` to skip).
Already-open Claude sessions are picked up from their next message.

```bash
./uninstall.sh           # removes the app, hooks and login item
./uninstall.sh --purge   # also deletes your task history
```

## How it works

No API keys and no network. Everything stays on your Mac.

```
Claude Code ──hooks──▶ vigil-hook.sh ──▶ ~/.claude/vigil/sessions/*.json ──▶ Vigil.app
 (each event)          (tiny bash + jq)    (one status file per session)      (reads 2×/s)
```

Claude Code [hooks](https://code.claude.com/docs/en/hooks) run a script on every event: prompt sent,
tool used, plan updated, permission requested, task stopped. The script writes a small JSON file per
session, plus one line per finished task to `history.jsonl`. The SwiftUI app reads those files and
draws the notch. Works with the Claude Code CLI in any terminal and the Claude desktop app.

## Approvals: the details

When Claude asks to use a tool, Vigil shows the exact command and waits up to 60 seconds
(`VIGIL_APPROVE_WAIT`) for Allow or Deny. With no answer, Claude's normal prompt takes over.
Vigil never approves anything on its own, your deny rules still apply, and questions and plan
approvals always stay in Claude.

## Settings

The eye icon in the menu bar has: previews of each state, sounds on/off, launch at login, quit.
The pill is hidden from screen sharing and recordings and stays out of fullscreen apps.

## Known limits

- The context window size isn't recorded in Claude's transcript, so Vigil assumes 200k unless usage goes past it.
- Clicking brings Claude or your terminal to the front, but can't open a specific desktop app session.
- Claude Code doesn't document whether its own permission prompt shows while a hook is waiting.
  If it doesn't for you, answering in Claude can take up to 60s; lower `VIGIL_APPROVE_WAIT`.
- Unsigned build from source: macOS may ask you to allow it the first time.

Debugging: `touch ~/.claude/vigil/.debug` logs raw hook events to `~/.claude/vigil/debug.log`.

---

MIT licensed. Not affiliated with Anthropic. Claude is a trademark of Anthropic.
Made by [Ivan Roussev](https://www.roussev.com).
