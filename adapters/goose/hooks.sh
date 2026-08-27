#!/usr/bin/env bash
set -euo pipefail

# hooks.sh — Manage Goose hook installation for atrium.
# Goose auto-discovers plugins at ~/.agents/plugins/<name>/hooks/hooks.json
# (Open Plugins hooks spec: https://open-plugins.com/agent-builders/components/hooks).
# Subcommands: install, uninstall, status
# Output: JSON to stdout, diagnostics to stderr

SUBCOMMAND="${1:?Usage: hooks.sh <install|uninstall|status>}"

PLUGIN_DIR="${HOME}/.agents/plugins/atrium-goose"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
RELAY_SCRIPT="${PLUGIN_DIR}/relay.sh"

do_install() {
  mkdir -p "${PLUGIN_DIR}/hooks"

  cat > "$RELAY_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# Relays a Goose lifecycle event to atrium's local hook server.
# Never fails the calling session: always exits 0.
EVENT="${1:-}"
PORT=$(cat "${HOME}/.atrium/hook-port" 2>/dev/null) || exit 0
[ -n "$PORT" ] || exit 0
curl -s -X POST "http://127.0.0.1:${PORT}/api/adapter/goose/${EVENT}" \
  -H 'Content-Type: application/json' -d "$(cat)" >/dev/null 2>&1 || true
exit 0
EOF
  chmod +x "$RELAY_SCRIPT"

  cat > "$HOOKS_JSON" <<EOF
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} session-start" }]
    }],
    "SessionEnd": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} session-end" }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} user-prompt-submit" }]
    }],
    "PreToolUse": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} pre-tool-use" }]
    }],
    "PostToolUse": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} post-tool-use" }]
    }],
    "PostToolUseFailure": [{
      "hooks": [{ "type": "command", "command": "${RELAY_SCRIPT} post-tool-use-failure" }]
    }]
  }
}
EOF

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
