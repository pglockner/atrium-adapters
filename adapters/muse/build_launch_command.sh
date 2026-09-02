#!/usr/bin/env bash
set -euo pipefail

# build_launch_command.sh — Build the command to launch Muse Code interactively.
# Takes $1 = JSON flags from launcher options
# Output: {"command": ["muse", ...flags]}
#
# jq filter is a single parenthesized expression: atrium's script PATH prefers
# /usr/bin/jq (Apple 1.7.1), which rejects multi-line `command: [$x] + …`
# without grouping.

FLAGS="${1:-"{}"}"

if ! command -v jq &>/dev/null; then
  echo '{"command": ["muse"]}'
  exit 0
fi

if ! printf '%s' "$FLAGS" | jq empty 2>/dev/null; then
  FLAGS='{}'
fi

# `--yolo` is muse's own name for "no approval prompts, no sandbox, trust this
# workspace"; it is the only flag that lifts BOTH gates, which is why the
# toggle maps to it rather than to a bare --disable-approval.
jq -nc \
  --argjson flags "$FLAGS" \
  '{command: (["muse"] + (if $flags.yolo == true then ["--yolo"] else [] end) + (if (($flags.approvalMode // "") | length) > 0 then ["--approval-mode", $flags.approvalMode] else [] end) + (if (($flags.model // "") | length) > 0 then ["--model", $flags.model] else [] end) + (if (($flags.effort // "") | length) > 0 then ["--reasoning-effort", $flags.effort] else [] end) + (if $flags.worktree == true then ["--worktree"] else [] end) + (if (($flags.extraArgs // "") | length) > 0 then ($flags.extraArgs | split(" ") | map(select(length > 0))) else [] end))}'
exit 0
