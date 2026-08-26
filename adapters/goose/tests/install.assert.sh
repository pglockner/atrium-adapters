#!/usr/bin/env bash
set -euo pipefail

# install.assert.sh — Post-install assertions for the goose adapter.
# Verifies the Goose Open Plugins hook plugin (hooks/hooks.json spec:
# https://open-plugins.com/agent-builders/components/hooks) was written
# correctly: hooks.json wires SessionStart/SessionEnd to relay.sh, and
# relay.sh forwards stdin to atrium's hook server for the given event.

HOOKS_JSON="${HOME}/.agents/plugins/atrium-goose/hooks/hooks.json"
RELAY_SCRIPT="${HOME}/.agents/plugins/atrium-goose/relay.sh"

if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "install.assert: $HOOKS_JSON does not exist" >&2
  exit 1
fi

if ! jq -e '.hooks.SessionStart[0].hooks[0].command | test("relay\\.sh session-start$")' "$HOOKS_JSON" >/dev/null 2>&1; then
  echo "install.assert: $HOOKS_JSON missing SessionStart -> relay.sh session-start" >&2
  exit 1
fi

if ! jq -e '.hooks.SessionEnd[0].hooks[0].command | test("relay\\.sh session-end$")' "$HOOKS_JSON" >/dev/null 2>&1; then
  echo "install.assert: $HOOKS_JSON missing SessionEnd -> relay.sh session-end" >&2
  exit 1
fi

if [[ ! -x "$RELAY_SCRIPT" ]]; then
  echo "install.assert: $RELAY_SCRIPT missing or not executable" >&2
  exit 1
fi

if ! grep -q 'atrium/hook-port' "$RELAY_SCRIPT"; then
  echo "install.assert: $RELAY_SCRIPT does not read atrium's hook-port file" >&2
  exit 1
fi

if ! grep -q '/api/adapter/goose/' "$RELAY_SCRIPT"; then
  echo "install.assert: $RELAY_SCRIPT does not POST to the goose adapter endpoint" >&2
  exit 1
fi

exit 0
