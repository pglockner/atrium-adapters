#!/usr/bin/env bash
set -euo pipefail

# install.assert.sh — Post-install assertions for the goose adapter.
# Verifies the Goose Open Plugins hook plugin (hooks/hooks.json spec:
# https://open-plugins.com/agent-builders/components/hooks) was written
# correctly: hooks.json wires the four events Goose 1.49.0 dispatches to
# plugins (SessionStart/SessionEnd/UserPromptSubmit/Stop) at the committed
# goose-hook.sh, which resolves the atrium instance from ATRIUM_DATA_DIR and
# relays the normalized payload to atrium's hook server.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_JSON="${HOME}/.agents/plugins/atrium-goose/hooks/hooks.json"
HOOK_SCRIPT="${ADAPTER_DIR}/goose-hook.sh"
NORMALIZER="${ADAPTER_DIR}/normalize-hook-payload.sh"

if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "install.assert: $HOOKS_JSON does not exist" >&2
  exit 1
fi

for pair in "SessionStart:session-start" "SessionEnd:session-end" \
            "UserPromptSubmit:user-prompt-submit" "Stop:stop"; do
  native="${pair%%:*}"
  arg="${pair##*:}"
  if ! jq -e --arg n "$native" --arg a " ${arg}$" \
       '.hooks[$n][0].hooks[0].command | test("goose-hook\\.sh" + $a)' \
       "$HOOKS_JSON" >/dev/null 2>&1; then
    echo "install.assert: $HOOKS_JSON missing $native -> goose-hook.sh $arg" >&2
    exit 1
  fi
done

# No tool-level events — Goose 1.49.0 does not dispatch them to plugins.
if jq -e '.hooks | has("PreToolUse") or has("PostToolUse") or has("PostToolUseFailure")' \
     "$HOOKS_JSON" >/dev/null 2>&1; then
  echo "install.assert: $HOOKS_JSON wires a tool hook Goose does not fire" >&2
  exit 1
fi

for f in "$HOOK_SCRIPT" "$NORMALIZER"; do
  if [[ ! -x "$f" ]]; then
    echo "install.assert: $f missing or not executable" >&2
    exit 1
  fi
done

# The relay must resolve the port from the pane's own atrium instance.
if ! grep -q 'ATRIUM_DATA_DIR:-$HOME/.atrium' "$HOOK_SCRIPT"; then
  echo "install.assert: $HOOK_SCRIPT does not resolve hook-port via ATRIUM_DATA_DIR" >&2
  exit 1
fi

if ! grep -q '/api/adapter/goose/' "$HOOK_SCRIPT"; then
  echo "install.assert: $HOOK_SCRIPT does not POST to the goose adapter endpoint" >&2
  exit 1
fi

exit 0
