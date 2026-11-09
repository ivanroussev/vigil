#!/bin/bash
# Removes Vigil: the app, its hooks in ~/.claude/settings.json and the login item.
#   ./uninstall.sh           keep your task history in ~/.claude/vigil
#   ./uninstall.sh --purge   also delete ~/.claude/vigil
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

pkill -x Vigil 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.roussev.vigil.plist"
rm -rf "$HOME/Applications/Vigil.app"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  TMP=$(mktemp)
  jq '.hooks |= ((. // {})
        | with_entries(.value |= map(select(any(.hooks[]?; .command | test("/\\.claude/vigil/hooks/")) | not)))
        | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end' "$SETTINGS" >"$TMP" && mv "$TMP" "$SETTINGS"
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.claude/vigil"
  echo "✓ Vigil removed, including its history."
else
  rm -rf "$HOME/.claude/vigil/hooks"
  echo "✓ Vigil removed. Task history kept in ~/.claude/vigil (use --purge to delete it)."
fi
