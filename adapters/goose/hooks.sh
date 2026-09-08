#!/usr/bin/env bash
set -euo pipefail

# hooks.sh — Manage Goose hook installation for atrium.
# Goose auto-discovers plugins at ~/.agents/plugins/<name>/hooks/hooks.json
# (Open Plugins hooks spec: https://open-plugins.com/agent-builders/components/hooks).
#
# The plugin's hooks.json points every event at the adapter's committed
# goose-hook.sh, which normalizes the payload and relays it to atrium. Only the
# events Goose 1.49.0 actually dispatches to plugins are wired: SessionStart,
# SessionEnd, UserPromptSubmit, Stop. (PreToolUse/PostToolUse/PostToolUseFailure
# are enum variants that are not delivered to plugins in current Goose.)
#
# Subcommands: install, uninstall, status
# Output: JSON to stdout, diagnostics to stderr

SUBCOMMAND="${1:?Usage: hooks.sh <install|uninstall|status>}"

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${ADAPTER_DIR}/goose-hook.sh"
PLUGIN_DIR="${HOME}/.agents/plugins/atrium-goose"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"

do_install() {
  mkdir -p "${PLUGIN_DIR}/hooks"
  chmod +x "$HOOK_SCRIPT" "${ADAPTER_DIR}/normalize-hook-payload.sh"

  jq -n --arg cmd "$HOOK_SCRIPT" '
    def ev($name; $arg): { ($name): [ { hooks: [ { type: "command", command: ($cmd + " " + $arg) } ] } ] };
    { hooks:
        ( ev("SessionStart";     "session-start")
        + ev("SessionEnd";       "session-end")
        + ev("UserPromptSubmit"; "user-prompt-submit")
        + ev("Stop";             "stop") )
    }
  ' > "$HOOKS_JSON"

  echo '{"subcommand": "install", "installed": true}'
}

do_uninstall() {
  rm -rf "$PLUGIN_DIR"
  echo '{"subcommand": "uninstall", "uninstalled": true}'
}

do_status() {
  if [ -f "$HOOKS_JSON" ]; then
    echo '{"subcommand": "status", "installed": true}'
  else
    echo '{"subcommand": "status", "installed": false}'
  fi
}

case "$SUBCOMMAND" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  *)
    echo "{\"error\": \"Unknown subcommand: ${SUBCOMMAND}\"}" >&2
    exit 2
    ;;
esac
