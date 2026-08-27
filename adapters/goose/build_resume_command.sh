#!/usr/bin/env bash
set -euo pipefail

session_id="${1:?session id required}"
flags="${2:-}"
[ -z "$flags" ] && flags='{}'

provider=$(echo "$flags" | jq -r '.extra.provider // empty')
model=$(echo "$flags" | jq -r '.extra.model // empty')
effort=$(echo "$flags" | jq -r '.extra.effort // empty')
extra_args=$(echo "$flags" | jq -r '.extra.extraArgs // empty')

cmd=(goose session --resume --session-id "$session_id")

# Resume must carry the provider/model the launch profile applied. Goose
# otherwise falls back to the default configured in config.yaml, silently
# switching models out from under a resumed session.
[ -n "$provider" ] && cmd+=(--provider "$provider")
[ -n "$model" ] && cmd+=(--model "$model")

# Carry the effort so the resumed session keeps the same thinking_effort.
# Goose has no --effort flag; set GOOSE_THINKING_EFFORT instead.
if [ -n "$effort" ]; then
  cmd=(env GOOSE_THINKING_EFFORT="$effort" "${cmd[@]}")
fi

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
