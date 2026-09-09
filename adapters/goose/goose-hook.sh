#!/usr/bin/env bash
# goose-hook.sh — relay a Goose lifecycle event to atrium's local hook server.
# Wired into <plugin-root>/atrium-goose/hooks/hooks.json by hooks.sh.
# Never fails the calling session: always exits 0.
#
# Usage: goose-hook.sh <normalizer-event> [atrium-event]   (payload on stdin)
#   normalizer-event  selects the transform in normalize-hook-payload.sh
#   atrium-event      the /api/adapter/goose/<event> endpoint to POST to
#                     (defaults to normalizer-event; PostToolUseFailure folds
#                     into post-tool-use with a synthesized error)

set -uo pipefail

NORM_EVENT="${1:-}"
ATRIUM_EVENT="${2:-$NORM_EVENT}"
[ -n "$NORM_EVENT" ] || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the atrium instance this session belongs to. Dev / linked-worktree
# panes export ATRIUM_DATA_DIR; without honoring it a session launched from a
# dev build would report to the stable daemon.
DATA_DIR="${ATRIUM_DATA_DIR:-$HOME/.atrium}"
PORT="$(cat "${DATA_DIR}/hook-port" 2>/dev/null)" || exit 0
[ -n "$PORT" ] || exit 0

PAYLOAD="$(cat 2>/dev/null || true)"

BODY="$(printf '%s' "$PAYLOAD" | "${DIR}/normalize-hook-payload.sh" "$NORM_EVENT" 2>/dev/null)" \
  || BODY="$PAYLOAD"

curl -s -X POST "http://127.0.0.1:${PORT}/api/adapter/goose/${ATRIUM_EVENT}" \
  -H 'Content-Type: application/json' \
  -d "$BODY" >/dev/null 2>&1 || true

exit 0
