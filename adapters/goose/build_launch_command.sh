#!/usr/bin/env bash
set -euo pipefail

# atrium passes launcher_options keys at the TOP level of the flags bag
# ({"model":"…","provider":"…"}), which is what every shipped adapter reads.
# The SDK README also documents a nested `extra` object, so accept both and
# prefer whichever is actually populated. Reading only `.extra` silently
# dropped every launch-profile model/provider/effort selection.
flags="${1:-}"
[ -z "$flags" ] && flags='{}'

provider=$(echo "$flags" | jq -r '[.provider, .extra.provider] | map(select(. != null and . != "")) | first // empty')
model=$(echo "$flags" | jq -r '[.model, .extra.model] | map(select(. != null and . != "")) | first // empty')
effort=$(echo "$flags" | jq -r '[.effort, .extra.effort] | map(select(. != null and . != "")) | first // empty')
extra_args=$(echo "$flags" | jq -r '[.extraArgs, .extra.extraArgs] | map(select(. != null and . != "")) | first // empty')

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
