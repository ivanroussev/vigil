#!/bin/bash
# Plays a scripted session through every Vigil state (~20s), for previews and demo recordings.
# While it runs, Vigil shows only this session. Optional: VIGIL_DEMO_HOVER=/path/to/cmd
# is called with "on" / "off" to open and close the hover card (e.g. a mouse-warp helper).
set -euo pipefail

DIR="$HOME/.claude/vigil/sessions"
REQ_DIR="$HOME/.claude/vigil/requests"
FILE="$DIR/vigil-demo.json"
mkdir -p "$DIR" "$REQ_DIR"
trap 'rm -f "$FILE" "$REQ_DIR/vigil-demo.json"; [ -n "${VIGIL_DEMO_HOVER:-}" ] && "$VIGIL_DEMO_HOVER" off; true' EXIT

START=$(($(date +%s) - 95))
STEPS='["Read the existing hook script","Track failing and repeated steps","Show stuck sessions in lavender","Learn ETA from task history","Add finish summary","Run the tests"]'

hover() { [ -n "${VIGIL_DEMO_HOVER:-}" ] && "$VIGIL_DEMO_HOVER" "$1" || true; }

# state(state, done, action, [extra jq])
state() {
  jq -n --arg st "$1" --argjson d "$2" --arg a "$3" --argjson steps "$STEPS" \
        --argjson start "$START" --argjson pid $$ "
    {session: \"vigil-demo\", state: \$st, done: \$d, total: (\$steps | length), action: \$a,
     title: \"Add stuck detection and a smarter ETA\", project: \"vigil\", cwd: \"/demo/vigil\",
     started: \$start, updated: now, pid: \$pid, entry: \"claude-desktop\",
     context: (52000 + \$d * 9000), model: \"claude-opus-5-5\",
     todos: [\$steps | to_entries[] | {content: .value,
             status: (if .key < \$d then \"completed\" elif .key == \$d then \"in_progress\" else \"pending\" end)}]}
    ${4:-}" >"$FILE.tmp" && mv "$FILE.tmp" "$FILE"
}

state working 0 "Thinking" '| .total = 0 | .todos = []';  sleep 2
state working 0 "Reading vigil-hook.sh";                   sleep 1.6
state working 1 "Editing vigil-hook.sh";                   sleep 1.6
state working 2 "Editing Models.swift";                    sleep 1.2
hover on;                                                  sleep 1.4
state working 3 "Editing StatusStore.swift";               sleep 2.2
hover off;                                                 sleep 0.6

# Permission prompt: the card opens on its own with Allow / Deny.
state needs_you 4 "Needs approval: Running swift test"
jq -n '{id: "vigil-demo", session: "vigil-demo", tool: "Bash", project: "vigil",
        detail: "swift test --package-path app", description: "Run the test suite",
        created: now, expires: (now + 60)}' >"$REQ_DIR/vigil-demo.json"
sleep 3.4
rm -f "$REQ_DIR/vigil-demo.json"
state working 4 "Running swift test";                      sleep 1.6
state working 5 "Running swift test";                      sleep 1.4

state done 6 "Done" '| .finished = now
  | .summary = {files: 4, added: 186, removed: 31, seconds: (now - .started | floor), tools: 42}'
sleep 1.8
hover on;                                                  sleep 3.2
hover off;                                                 sleep 0.8
