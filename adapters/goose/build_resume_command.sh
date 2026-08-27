#!/usr/bin/env bash
set -euo pipefail

session_id="${1:?session id required}"
flags="${2:-}"
[ -z "$flags" ] && flags='{}'

provider=$(echo "$flags" | jq -r '.extra.provider // empty')
model=$(echo "$flags" | jq -r '.extra.model // empty')
extra_args=$(echo "$flags" | jq -r '.extra.extraArgs // empty')

cmd=(goose session --resume --session-id "$session_id")

# Resume must carry the provider/model the launch profile applied. Goose
# otherwise falls back to the default configured in config.yaml, silently
# switching models out from under a resumed session.
[ -n "$provider" ] && cmd+=(--provider "$provider")
[ -n "$model" ] && cmd+=(--model "$model")

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
