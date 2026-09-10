#!/usr/bin/env bash
# goose-hook.sh — relay a Goose lifecycle event to atrium as pane activity.
# Wired into <plugin-root>/atrium-goose/hooks/hooks.json by hooks.sh as:
#
#     goose-hook.sh <normalizer-event> <atrium-event>   (native payload on stdin)
#
#   normalizer-event  selects the transform in normalize-hook-payload.sh
#                     (the native Goose event name, lower-cased)
#   atrium-event      the activity event to emit. PostToolUseFailure folds into
#                     post-tool-use, carrying a synthesized non-empty `error`.
#
# Goose auto-loads this plugin for EVERY `goose` process on the machine, so the
# relay must stay inert outside an atrium pane and inside a chat pane whose
# activity already comes from atrium's ACP turn bridge. It emits through
# `atrium hook emit --pane-id`, so the event is stored against the originating
# pane (atrium's hook ingestion reads the pane id from the emit call, never
# infers it from session_id). Never fails the calling session: always exits 0.

set -uo pipefail

NORM_EVENT="${1:-}"
ATRIUM_EVENT="${2:-$NORM_EVENT}"
[ -n "$NORM_EVENT" ] || exit 0

# Chat panes receive activity from atrium's ACP turn bridge; relaying the plugin
# hook stream on top double-feeds the activity card and, with no settling stop
# behind it, wedges it in "working" (matches hermes/kimi/grok/cursor-agent).
[ -z "${ATRIUM_CHAT_SDK_HOOKS:-}" ] || exit 0

# Only relay a Goose that atrium launched into a pane. atrium injects
# ATRIUM_PANE_ID only into its own panes; its absence means there is no pane to
# attribute activity to (a plain-terminal `goose`, a cron job, an IDE plugin).
[ -n "${ATRIUM_PANE_ID:-}" ] || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Self-locate the atrium CLI from the install layout (<data-dir>/adapters/goose/)
# so one committed hooks.json entry resolves to whichever atrium instance owns
# this install (stable vs dev). $ATRIUM_CLI_PATH from the pane env still wins.
DATA_DIR="$(cd "$DIR/../.." 2>/dev/null && pwd || printf '%s' "$HOME/.atrium")"
case "$(basename "$DATA_DIR")" in
  .atrium-dev*) DEFAULT_CLI="$DATA_DIR/bin/atrium-dev" ;;
  *)            DEFAULT_CLI="$DATA_DIR/bin/atrium" ;;
esac
ATRIUM_CLI="${ATRIUM_CLI_PATH:-$DEFAULT_CLI}"
[ -x "$ATRIUM_CLI" ] || ATRIUM_CLI="atrium"

PAYLOAD="$(cat 2>/dev/null || true)"

printf '%s' "$PAYLOAD" \
  | "${DIR}/normalize-hook-payload.sh" "$NORM_EVENT" 2>/dev/null \
  | "$ATRIUM_CLI" hook emit "$ATRIUM_EVENT" \
      --adapter goose --pane-id "$ATRIUM_PANE_ID" --json >/dev/null 2>&1 || true

exit 0
