# Claude Notch

A small pill around the MacBook notch that shows what Claude Code is doing:

- **Coral, pulsing**: working. It grows as plan steps complete and shows `3/8`, or elapsed time when there's no plan.
- **Amber ✋**: Claude needs your approval or input.
- **Green ✓**: finished.

## How it works

1. `hooks/notch-hook.sh` runs on Claude Code events (prompt, tool use, plan updates,
   permission requests, stop) and writes `~/.claude/notch/sessions/<session>.json`.
2. `ClaudeNotch.app` reads those files twice a second and draws the pill above the notch.
   With several sessions it shows the most urgent one (needs you > working > done).

## Setup

```bash
./scripts/install-hooks.sh   # adds the hooks to ~/.claude/settings.json (keeps a backup)
./scripts/build.sh           # builds build/ClaudeNotch.app
open build/ClaudeNotch.app
```

The menu bar capsule icon has preview states and Quit.

Debug: `touch ~/.claude/notch/.debug` logs raw hook events to `~/.claude/notch/debug.log`.

To remove the hooks, restore `~/.claude/settings.json.bak-notch` or delete the entries
that point at `notch-hook.sh`.
