#!/bin/bash
# Claude Code hook: turns each event into a status file the notch app reads.
# Writes ~/.claude/notch/sessions/<session_id>.json. Never blocks Claude:
# it prints nothing and always exits 0.

DIR="$HOME/.claude/notch/sessions"
mkdir -p "$DIR"

EVENT=$(cat)
SID=$(jq -r '.session_id // "unknown"' <<<"$EVENT" 2>/dev/null) || exit 0
FILE="$DIR/$SID.json"
LOCK="$FILE.lock"

# Optional raw event log: touch ~/.claude/notch/.debug to turn on.
if [ -f "$HOME/.claude/notch/.debug" ]; then
  jq -c '{t: now, e: .hook_event_name, tool: .tool_name, input: .tool_input, n: .notification_type, msg: .message}' \
    <<<"$EVENT" >>"$HOME/.claude/notch/debug.log" 2>/dev/null
fi

if [ "$(jq -r '.hook_event_name' <<<"$EVENT")" = "SessionEnd" ]; then
  rm -f "$FILE"
  exit 0
fi

# Small lock so parallel tool calls don't overwrite each other.
for _ in $(seq 1 50); do mkdir "$LOCK" 2>/dev/null && break; sleep 0.01; done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

PREV=$(cat "$FILE" 2>/dev/null || echo '{}')

jq -n --argjson s "$PREV" --argjson e "$EVENT" '
  def base: ($s + {session: $e.session_id, cwd: ($e.cwd // $s.cwd),
                   project: (($e.cwd // $s.cwd // "") | split("/") | last),
                   updated: now});

  # Short human label for what a tool is doing.
  def describe:
    ($e.tool_name // "") as $t | ($e.tool_input // {}) as $i |
    (($i.file_path // $i.path // "") | split("/") | last) as $f |
    if   $t == "Bash"  then "Running " + (($i.description // $i.command // "command") | .[0:40])
    elif $t == "Edit" or $t == "MultiEdit" then "Editing " + $f
    elif $t == "Write" then "Writing " + $f
    elif $t == "Read"  then "Reading " + $f
    elif $t == "Grep" or $t == "Glob" then "Searching code"
    elif $t == "WebFetch" or $t == "WebSearch" then "Browsing the web"
    elif $t == "Agent" or $t == "Task" then "Delegating " + (($i.description // "") | .[0:30])
    elif $t == "TodoWrite" or ($t | endswith("update_plan")) then "Updating plan"
    elif ($t | startswith("mcp__")) then ($t | split("__") | last | gsub("_"; " "))
    else $t end;

  # Apply the desktop app plan tool (full list, or advance/done/start by number).
  def apply_plan($i):
    if $i.items then [$i.items[] | {content, status}]
    else (.todos // []) as $td
      | ($td | map(.status) | index("in_progress")) as $cur
      | $td
      | if $i.advance then
          (if $cur != null then .[$cur].status = "completed" else . end)
          | (map(.status) | index("pending")) as $nx
          | if $nx != null then .[$nx].status = "in_progress" else . end
        else . end
      | reduce (($i.done // [])[]) as $n (.; if .[$n-1] then .[$n-1].status = "completed" else . end)
      | if $i.start and .[$i.start-1] then .[$i.start-1].status = "in_progress" else . end
    end;

  def counts: . + {total: ((.todos // []) | length),
                   done:  ((.todos // []) | map(select(.status == "completed")) | length)};

  ($e.hook_event_name) as $ev |
  base |
  if $ev == "SessionStart" then
    .state = (.state // "idle")
  elif $ev == "UserPromptSubmit" then
    . + {state: "working", started: now, finished: null, todos: [],
         action: "Thinking", title: (($e.prompt // "") | gsub("\\s+"; " ") | .[0:80])}
  elif $ev == "PreToolUse" then
    . + {state: "working", action: describe}
  elif $ev == "PostToolUse" then
    .state = "working"
    | if $e.tool_name == "TodoWrite" then .todos = [($e.tool_input.todos // [])[] | {content, status}]
      elif ($e.tool_name | endswith("update_plan")) then .todos = apply_plan($e.tool_input)
      elif ($e.tool_name | endswith("wrap_up")) then .todos = [(.todos // [])[] | .status = "completed"]
      else . end
  elif $ev == "PermissionRequest" then
    . + {state: "needs_you", action: "Needs your approval"}
  elif $ev == "Notification" then
    # idle reminders after a finished turn should not flip "done" to amber
    if ($e.notification_type // "") == "idle_prompt"
       or (($e.message // "") | test("waiting for your input"; "i")) then .
    else . + {state: "needs_you", action: ($e.message // "Needs you")} end
  elif $ev == "Stop" then
    . + {state: "done", finished: now, action: "Done"}
  else . end
  | counts
' >"$FILE.tmp" 2>/dev/null && mv "$FILE.tmp" "$FILE"

exit 0
