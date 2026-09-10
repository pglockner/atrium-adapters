#!/usr/bin/env bash
set -euo pipefail

session_id="${1:?session id required}"
# See build_launch_command.sh: atrium passes these keys top-level, not under
# `extra`.
flags="${2:-}"
[ -z "$flags" ] && flags='{}'

effort=$(echo "$flags" | jq -r '.effort // "" | select(. != "")')
extra_args=$(echo "$flags" | jq -r '.extraArgs // "" | select(. != "")')

cmd=(goose session --resume --session-id "$session_id")

# Provider and model are deliberately NOT re-applied on resume. Goose restores
# the session's persisted provider_name and model_config (sessions.db), and only
# falls back to global config if those are absent. Re-appending the launch
# profile's original --provider/--model would overwrite an in-session /model
# change with stale launch-time values. Let Goose restore its own.

# Effort has no persisted per-session field in Goose, so carry it forward from
# the launch profile via GOOSE_THINKING_EFFORT (there is no --effort flag).
if [ -n "$effort" ]; then
  cmd=(env GOOSE_THINKING_EFFORT="$effort" "${cmd[@]}")
fi

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
