#!/usr/bin/env bash
set -euo pipefail

# Regression check: goose launch must consume the flags bag atrium actually
# sends. atrium passes launcher_options keys at the TOP level
# ({"model":…,"provider":…,"effort":…,"extraArgs":…}). goose originally read a
# nested `.extra` object (AdapterFlags, since removed), so every launch
# profile's model/provider/effort was silently dropped and every session
# started on goose's own configured default instead.
# Verified live: pane launched with a model-bearing profile produced a bare
# `goose session` argv before the fix, and
# `goose session --provider … --model …` after.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/adapters/goose/build_launch_command.sh"
FAILURES=0

assert_launch() {
  local desc="$1" flags="$2" expected="$3"
  local actual
  actual="$(bash "$SCRIPT" "$flags" | jq -c '.command')"
  if [[ "$actual" == "$(echo "$expected" | jq -c '.')" ]]; then
    printf '[PASS] goose launch: %s\n' "$desc"
  else
    printf '[FAIL] goose launch: %s\n' "$desc"
    printf '  expected: %s\n' "$(echo "$expected" | jq -c '.')"
    printf '  actual:   %s\n' "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# The exact bag atrium sent in the live repro.
assert_launch "top-level flags (the shape atrium sends)" \
  '{"extraArgs":"","model":"qwen/qwen3-coder","provider":"openrouter"}' \
  '["goose","session","--provider","openrouter","--model","qwen/qwen3-coder"]'

# A nested `.extra` object is NOT read — that shape is dead (AdapterFlags removed).
assert_launch "nested .extra is ignored, not unwrapped" \
  '{"extra":{"model":"m1","provider":"p1","effort":"high"}}' \
  '["goose","session"]'

# effort has no CLI flag; it must ride in as an env prefix, never as --effort.
assert_launch "effort becomes a GOOSE_THINKING_EFFORT env prefix" \
  '{"effort":"max"}' \
  '["env","GOOSE_THINKING_EFFORT=max","goose","session"]'

assert_launch "all flags together" \
  '{"model":"anthropic/claude","provider":"anthropic","effort":"medium","extraArgs":"--max-turns 3"}' \
  '["env","GOOSE_THINKING_EFFORT=medium","goose","session","--provider","anthropic","--model","anthropic/claude","--max-turns","3"]'

# An unset select sends "" — that must not become an empty flag value.
assert_launch "blank values are omitted, not passed as empty flags" \
  '{"model":"","provider":"","effort":"","extraArgs":""}' \
  '["goose","session"]'

assert_launch "no flags at all" '{}' '["goose","session"]'
assert_launch "empty flags string" '' '["goose","session"]'

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
printf 'goose-launch-profile-flags: all checks passed\n'
