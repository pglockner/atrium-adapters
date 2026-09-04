#!/usr/bin/env bash
set -euo pipefail

URL=""
for arg in "$@"; do
  case "$arg" in
    http://*|https://*)
      URL="$arg"
      break
      ;;
  esac
done

[ -n "$URL" ] || exit 1
[ -n "${ATRIUM_CLI_PATH:-}" ] || exit 1

ARGS=(hook emit auth-browser-open --adapter claude-code)
if [ -n "${ATRIUM_PANE_ID:-}" ]; then
  ARGS+=(--pane-id "$ATRIUM_PANE_ID")
fi

jq -cn --arg url "$URL" '{atrium_browser_auth_url: $url}' \
  | "$ATRIUM_CLI_PATH" "${ARGS[@]}" >/dev/null
