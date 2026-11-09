#!/bin/bash
# Adds the notch hook to ~/.claude/settings.json (backs it up first).
# Safe to run twice: it skips events that already have the hook.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/notch-hook.sh"
SETTINGS="$HOME/.claude/settings.json"
chmod +x "$HOOK"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
[ -f "$SETTINGS.bak-notch" ] || cp "$SETTINGS" "$SETTINGS.bak-notch"   # keep the original
IN=$(mktemp); cp "$SETTINGS" "$IN"

jq --arg cmd "$HOOK" '
  def entry: {hooks: [{type: "command", command: $cmd, timeout: 5}]};
  def tool_entry: {matcher: "*"} + entry;
  def approve_entry: {matcher: "*", hooks: [{type: "command", command: $cmd, timeout: 90}]};
  def add($ev; $e):
    if any((.hooks[$ev] // [])[]; any(.hooks[]?; .command == $cmd)) then .
    else .hooks[$ev] = ((.hooks[$ev] // []) + [$e]) end;
  .hooks = (.hooks // {})
  | add("SessionStart"; entry) | add("UserPromptSubmit"; entry)
  | add("PreToolUse"; tool_entry) | add("PostToolUse"; tool_entry)
  | add("PostToolUseFailure"; tool_entry)
  | add("PermissionRequest"; approve_entry) | add("Notification"; entry)
  | add("Stop"; entry) | add("SessionEnd"; entry)
' "$IN" >"$SETTINGS"
rm -f "$IN"

echo "Hooks installed in $SETTINGS (backup: $SETTINGS.bak-notch)"
