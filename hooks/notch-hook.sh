#!/bin/bash
# Claude Code hook: turns each event into a status file the notch app reads.
#   ~/.claude/notch/sessions/<session_id>.json   live state per session
#   ~/.claude/notch/history.jsonl                one line per finished task
# Prints nothing and exits 0, except for PermissionRequest (see approve.sh).

ROOT="$HOME/.claude/notch"
DIR="$ROOT/sessions"
mkdir -p "$DIR"

EVENT=$(cat)
SID=$(jq -r '.session_id // "unknown"' <<<"$EVENT" 2>/dev/null) || exit 0
EV=$(jq -r '.hook_event_name // ""' <<<"$EVENT")
FILE="$DIR/$SID.json"
LOCK="$FILE.lock"

if [ -f "$ROOT/.debug" ]; then
  jq -c '{t: now, e: .hook_event_name, tool: .tool_name, input: .tool_input, n: .notification_type, msg: .message, err: .error}' \
    <<<"$EVENT" >>"$ROOT/debug.log" 2>/dev/null
fi

if [ "$EV" = "SessionEnd" ]; then
  rm -f "$FILE"
  exit 0
fi

CWD=$(jq -r '.cwd // empty' <<<"$EVENT")
[ -z "$CWD" ] && CWD=$(jq -r '.cwd // empty' "$FILE" 2>/dev/null)

# Tokens in the context window right now, from the last reply in the transcript.
CTX=null
MODEL=null
if [[ "$EV" =~ ^(PostToolUse|Stop|UserPromptSubmit)$ ]]; then
  TP=$(jq -r '.transcript_path // empty' <<<"$EVENT")
  if [ -f "$TP" ]; then
    read -r CTX MODEL < <(tail -n 60 "$TP" | jq -rs '
      [.[] | select(.message.usage and (.isSidechain | not))] | last
      | if . then "\(.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)) \(.message.model // "null")"
        else "null null" end' 2>/dev/null)
    [ -z "$CTX" ] && CTX=null
    [ "$MODEL" = "null" ] || MODEL="\"$MODEL\""
    [ -z "$MODEL" ] && MODEL=null
  fi
fi

# Commit at the start of a task, so the finish summary can diff against it.
START_SHA=""
if [ "$EV" = "UserPromptSubmit" ] && [ -n "$CWD" ]; then
  START_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
fi

# A lock older than 5s was left by a killed hook: clear it.
[ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mtime +5s 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
for _ in $(seq 1 50); do mkdir "$LOCK" 2>/dev/null && break; sleep 0.01; done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

PREV=$(cat "$FILE" 2>/dev/null || echo '{}')

NEW=$(jq -n --argjson s "$PREV" --argjson e "$EVENT" \
  --argjson ctx "$CTX" --argjson model "$MODEL" --arg sha "$START_SHA" \
  --arg entry "${CLAUDE_CODE_ENTRYPOINT:-}" --arg host "${CLAUDE_CODE_HOST_SESSION_ID:-}" \
  --arg term "${TERM_PROGRAM:-}" --arg pid "${CLAUDE_PID:-$PPID}" '
  def base: ($s + {session: $e.session_id, cwd: ($e.cwd // $s.cwd),
                   project: (($e.cwd // $s.cwd // "") | split("/") | last),
                   entry: $entry, host_session: $host, term: $term,
                   pid: ($pid | tonumber? // null), updated: now})
            | if $ctx != null then .context = $ctx else . end
            | if $model != null then .model = $model else . end;

  def describe:
    ($e.tool_name // "") as $t | ($e.tool_input // {}) as $i |
    (($i.file_path // $i.notebook_path // $i.path // "") | split("/") | last) as $f |
    if   $t == "Bash"  then "Running " + (($i.description // $i.command // "command") | .[0:40])
    elif $t == "Edit" or $t == "MultiEdit" or $t == "NotebookEdit" then "Editing " + $f
    elif $t == "Write" then "Writing " + $f
    elif $t == "Read"  then "Reading " + $f
    elif $t == "Grep" or $t == "Glob" then "Searching code"
    elif $t == "WebFetch" or $t == "WebSearch" then "Browsing the web"
    elif $t == "Agent" or $t == "Task" then "Delegating " + (($i.description // "") | .[0:30])
    elif $t == "AskUserQuestion" then "Asking you a question"
    elif $t == "TodoWrite" or ($t | endswith("update_plan")) then "Updating plan"
    elif ($t | startswith("mcp__")) then ($t | split("__") | last | gsub("_"; " "))
    else $t end;

  # Same tool + same input three times in a row looks like a loop.
  def call_key: ($e.tool_name // "") + ":" + (($e.tool_input // {}) | (.command // .file_path // .url // tostring) | .[0:200]);

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
    . + {state: "working", started: now, finished: null, todos: [], files: [],
         tools: 0, fails: 0, repeats: 0, lastKey: null, lastError: null, inTool: false,
         summary: null, start_sha: $sha, action: "Thinking",
         title: (($e.prompt // "") | gsub("\\s+"; " ") | .[0:80])}
  elif $ev == "PreToolUse" then
    (call_key) as $k
    | . + {state: "working", action: describe, inTool: true, toolStarted: now,
           tools: ((.tools // 0) + 1),
           repeats: (if .lastKey == $k then (.repeats // 0) + 1 else 1 end), lastKey: $k}
  elif $ev == "PostToolUse" then
    . + {state: "working", inTool: false, fails: 0}
    | ($e.tool_input.file_path // $e.tool_input.notebook_path) as $p
    | if ($e.tool_name | test("^(Edit|MultiEdit|Write|NotebookEdit)$")) and $p
      then .files = (((.files // []) + [$p]) | unique) else . end
    | if $e.tool_name == "TodoWrite" then .todos = [($e.tool_input.todos // [])[] | {content, status}]
      elif ($e.tool_name | endswith("update_plan")) then .todos = apply_plan($e.tool_input)
      elif ($e.tool_name | endswith("wrap_up")) then .todos = [(.todos // [])[] | .status = "completed"]
      else . end
  elif $ev == "PostToolUseFailure" then
    . + {state: "working", inTool: false, fails: ((.fails // 0) + 1),
         lastError: (($e.error // "failed") | tostring | .[0:120])}
  elif $ev == "PermissionRequest" then
    . + {state: "needs_you", action: (if $e.tool_name == "AskUserQuestion" then "Asking you a question"
                                      else "Needs approval: " + describe end)}
  elif $ev == "Notification" then
    if ($e.notification_type // "") == "idle_prompt"
       or (($e.message // "") | test("waiting for your input"; "i")) then .
    else . + {state: "needs_you", action: ($e.message // "Needs you")} end
  elif $ev == "Stop" then
    . + {state: "done", finished: now, action: "Done", inTool: false}
    | .todos = [(.todos // [])[] | if .status == "in_progress" then .status = "completed" else . end]
  else . end
  | counts
' 2>/dev/null) || exit 0

# Finish summary: lines changed in the files Claude touched, since the task started.
if [ "$EV" = "Stop" ]; then
  SHA=$(jq -r '.start_sha // empty' <<<"$NEW")
  ADDED=0; REMOVED=0
  if [ -n "$SHA" ] && [ -n "$CWD" ]; then
    FILES=()
    while IFS= read -r f; do FILES+=("$f"); done < <(jq -r '.files[]?' <<<"$NEW")
    if [ ${#FILES[@]} -gt 0 ]; then
      read -r ADDED REMOVED < <(git -C "$CWD" diff --numstat "$SHA" -- "${FILES[@]}" 2>/dev/null \
        | awk '{a+=$1; r+=$2} END {print a+0, r+0}')
      # New untracked files count as all-added.
      for f in "${FILES[@]}"; do
        if [ -f "$f" ] && ! git -C "$CWD" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
          ADDED=$((ADDED + $(wc -l <"$f")))
        fi
      done
    fi
  fi
  NEW=$(jq --argjson a "${ADDED:-0}" --argjson r "${REMOVED:-0}" \
    '.summary = {files: ((.files // []) | length), added: $a, removed: $r,
                 seconds: ((.finished - (.started // .finished)) | floor), tools: (.tools // 0)}' <<<"$NEW")
  # One history line per finished task (skip empty turns).
  jq -c 'select(.started) | {session, project, title, started, finished,
          seconds: .summary.seconds, steps: .total, files: .summary.files,
          added: .summary.added, removed: .summary.removed, tools: .summary.tools}' \
    <<<"$NEW" >>"$ROOT/history.jsonl" 2>/dev/null
fi

printf '%s' "$NEW" >"$FILE.tmp" && mv "$FILE.tmp" "$FILE"

# Permission requests: optionally wait for Allow/Deny from the notch.
if [ "$EV" = "PermissionRequest" ]; then
  rmdir "$LOCK" 2>/dev/null; trap - EXIT
  exec "$(dirname "$0")/approve.sh" <<<"$EVENT"
fi
exit 0
