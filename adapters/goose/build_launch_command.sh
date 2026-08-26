#!/usr/bin/env bash
set -euo pipefail

flags="${1:-}"
[ -z "$flags" ] && flags='{}'

provider=$(echo "$flags" | jq -r '.extra.provider // empty')
model=$(echo "$flags" | jq -r '.extra.model // empty')
extra_args=$(echo "$flags" | jq -r '.extra.extraArgs // empty')

cmd=(goose session)

[ -n "$provider" ] && cmd+=(--provider "$provider")
[ -n "$model" ] && cmd+=(--model "$model")

if [ -n "$extra_args" ]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  cmd+=("${extra_arr[@]}")
fi

printf '%s\n' "${cmd[@]}" | jq -R . | jq -s '{command: .}'
