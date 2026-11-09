#!/bin/bash
# Vigil installer: builds the app, installs the Claude Code hooks, starts it.
#   ./install.sh              install (and launch at login)
#   ./install.sh --no-login   don't add the login item
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DATA="$HOME/.claude/vigil"
HOOKS="$DATA/hooks"
APP="$HOME/Applications/Vigil.app"
SETTINGS="$HOME/.claude/settings.json"
AGENT="$HOME/Library/LaunchAgents/com.roussev.vigil.plist"
LOGIN=1
[ "${1:-}" = "--no-login" ] && LOGIN=0

say() { printf '\033[1m→ %s\033[0m\n' "$1"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Vigil is macOS only."
command -v swift >/dev/null || die "Swift not found. Install the Xcode Command Line Tools: xcode-select --install"
command -v jq >/dev/null || die "jq not found. Install it with: brew install jq"

say "Building Vigil"
"$ROOT/scripts/build.sh" >/dev/null

say "Installing the app to $APP"
pkill -x Vigil 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$ROOT/build/Vigil.app" "$APP"

say "Installing hooks to $HOOKS"
mkdir -p "$HOOKS"
cp "$ROOT/hooks/vigil-hook.sh" "$ROOT/hooks/approve.sh" "$HOOKS/"
chmod +x "$HOOKS"/*.sh

say "Registering hooks in $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
[ -f "$SETTINGS.bak-vigil" ] || cp "$SETTINGS" "$SETTINGS.bak-vigil"   # original, kept once
TMP=$(mktemp)
jq --arg cmd "$HOOKS/vigil-hook.sh" '
  def entry($t): {hooks: [{type: "command", command: $cmd, timeout: $t}]};
  def add($ev; $e):
    if any((.hooks[$ev] // [])[]; any(.hooks[]?; .command == $cmd)) then .
    else .hooks[$ev] = ((.hooks[$ev] // []) + [$e]) end;
  .hooks = (.hooks // {})
  | add("SessionStart"; entry(5)) | add("UserPromptSubmit"; entry(5))
  | add("PreToolUse"; {matcher: "*"} + entry(5)) | add("PostToolUse"; {matcher: "*"} + entry(5))
  | add("PostToolUseFailure"; {matcher: "*"} + entry(5))
  | add("PermissionRequest"; {matcher: "*"} + entry(90))
  | add("Notification"; entry(5)) | add("Stop"; entry(5)) | add("SessionEnd"; entry(5))
' "$SETTINGS" >"$TMP" && mv "$TMP" "$SETTINGS"

if [ $LOGIN = 1 ]; then
  say "Adding launch at login"
  mkdir -p "$(dirname "$AGENT")"
  cat >"$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.roussev.vigil</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
fi

open "$APP"
printf '\n\033[32m✓ Vigil is running.\033[0m Look at your notch, or the eye icon in the menu bar.\n'
echo "  New Claude Code sessions are tracked right away; already-open ones from their next message."
echo "  Uninstall any time: ./uninstall.sh"
