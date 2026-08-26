#!/usr/bin/env bash
set -euo pipefail

session_id="${1:?session id required}"
flags="${2:-}"
[ -z "$flags" ] && flags='{}'

extra_args=$(echo "$flags" | jq -r '.extra.extraArgs // empty')

cmd=(goose session --resume --session-id "$session_id")

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
