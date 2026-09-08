#!/usr/bin/env bash
set -euo pipefail

# atrium passes each launcher_options key at the TOP level of the flags bag
# ({"model":"…","provider":"…","effort":"…","extraArgs":"…"}) — the same shape
# every other adapter reads. (An older SDK README described a nested `extra`
# object; that was AdapterFlags, which has been removed. Do not read `.extra`.)
flags="${1:-}"
[ -z "$flags" ] && flags='{}'

provider=$(echo "$flags" | jq -r '.provider // "" | select(. != "")')
model=$(echo "$flags" | jq -r '.model // "" | select(. != "")')
effort=$(echo "$flags" | jq -r '.effort // "" | select(. != "")')
extra_args=$(echo "$flags" | jq -r '.extraArgs // "" | select(. != "")')

cmd=(goose session)

[ -n "$provider" ] && cmd+=(--provider "$provider")
[ -n "$model" ] && cmd+=(--model "$model")

# Goose has no --effort CLI flag; thinking_effort is set via the
# GOOSE_THINKING_EFFORT environment variable (or the ACP preference
# gooseThinkingEffort). Set it at launch so the session starts with the
# chosen effort.
if [ -n "$effort" ]; then
  cmd=(env GOOSE_THINKING_EFFORT="$effort" "${cmd[@]}")
fi

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
