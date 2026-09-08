#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${HOME}/.claude/settings.json"

jq -e '
  [.hooks.PreToolUse[]?.hooks[]?.command]
  | any(contains("hook guard-computer-use"))
' "$SETTINGS_FILE" >/dev/null
