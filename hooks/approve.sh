#!/bin/bash
# PermissionRequest: let the notch app answer Allow / Deny.
# Waits up to NOTCH_APPROVE_WAIT seconds (default 60) for a reply file.
# No reply, or the app isn't running -> prints nothing, so Claude shows
# its normal permission dialog. Never approves on its own.

ROOT="$HOME/.claude/notch"
WAIT="${NOTCH_APPROVE_WAIT:-60}"
EVENT=$(cat)

# Questions and plan approvals need the real Claude UI.
TOOL=$(jq -r '.tool_name // ""' <<<"$EVENT")
case "$TOOL" in AskUserQuestion|ExitPlanMode|EnterPlanMode) exit 0 ;; esac

pgrep -x ClaudeNotch >/dev/null || exit 0

mkdir -p "$ROOT/requests" "$ROOT/responses"
SID=$(jq -r '.session_id' <<<"$EVENT")
ID="$(date +%s)-$$-$RANDOM"
REQ="$ROOT/requests/$ID.json"
RES="$ROOT/responses/$ID.json"
trap 'rm -f "$REQ" "$RES"' EXIT

# What the user sees: the full command / file / URL, not a summary.
jq -c --arg id "$ID" --argjson wait "$WAIT" '{
    id: $id, session: .session_id, tool: .tool_name,
    project: ((.cwd // "") | split("/") | last),
    detail: ((.tool_input // {}) | (.command // .file_path // .notebook_path // .url // .pattern // tostring)),
    description: (.tool_input.description // null),
    created: now, expires: (now + $wait)}' <<<"$EVENT" >"$REQ.tmp" && mv "$REQ.tmp" "$REQ"

END=$((SECONDS + WAIT))
while [ $SECONDS -lt $END ]; do
  if [ -f "$RES" ]; then
    case "$(jq -r '.behavior // ""' "$RES" 2>/dev/null)" in
      allow) echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ;;
      deny)  echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the notch"}}}' ;;
    esac
    exit 0
  fi
  # Session moved on (answered in Claude, or stopped): stop waiting.
  STATE=$(jq -r '.state // ""' "$ROOT/sessions/$SID.json" 2>/dev/null)
  [ "$STATE" != "needs_you" ] && exit 0
  sleep 0.25
done
exit 0
