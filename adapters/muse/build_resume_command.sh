#!/usr/bin/env bash
set -euo pipefail

# build_resume_command.sh — Build the command to resume a Muse Code session.
# Takes $1 = session id (optional), $2 = JSON flags (optional)
# Output: {"command": ["muse", "resume", ...]}
#
# `muse resume <uuid>` targets one session; with no id, `--last` takes the most
# recent session in the workspace. A BARE `muse resume` is deliberately never
# emitted: it opens muse's interactive session PICKER, which would strand the
# pane on a chooser instead of resuming anything.

SESSION_ID="${1:-}"
FLAGS="${2:-"{}"}"

if ! command -v jq &>/dev/null; then
  if [ -n "$SESSION_ID" ]; then
    printf '{"command":["muse","resume",%s]}\n' \
      "$(printf '%s' "$SESSION_ID" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
  else
    echo '{"command": ["muse", "resume", "--last"]}'
  fi
  exit 0
fi

if ! printf '%s' "$FLAGS" | jq empty 2>/dev/null; then
  FLAGS='{}'
fi

# Root options may appear on either side of `resume`; they are placed after the
# subcommand so the session selector stays adjacent to it.
jq -nc \
  --arg sessionId "$SESSION_ID" \
  --argjson flags "$FLAGS" \
  '{command: (["muse", "resume"] + (if ($sessionId | length) > 0 then [$sessionId] else ["--last"] end) + (if $flags.yolo == true then ["--yolo"] else [] end) + (if (($flags.approvalMode // "") | length) > 0 then ["--approval-mode", $flags.approvalMode] else [] end) + (if (($flags.model // "") | length) > 0 then ["--model", $flags.model] else [] end) + (if (($flags.effort // "") | length) > 0 then ["--reasoning-effort", $flags.effort] else [] end))}'
exit 0
