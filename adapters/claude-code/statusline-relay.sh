#!/usr/bin/env bash
# atrium-statusline-relay — installed as Claude Code's statusLine command.
#
# Runs on every statusline tick with the session JSON on stdin. It:
#   1. relays `context_window`, `cost`, and `rate_limits` to atrium's composer
#      usage meter, but only when the session was spawned by atrium
#      (ATRIUM_PANE_ID set) and only when the payload changed since the last
#      tick — the statusline fires several times a second during streaming;
#   2. reproduces the user's original statusline display (the command
#      preserved by statusline.sh at install) so taking over the slot is
#      invisible to them.
#
# Diagnostics are silenced and it always exits 0 — a statusline failure
# must never disrupt the session or blank the display.
set -uo pipefail

input="$(cat)"
CHAIN_FILE="${HOME}/.claude/.atrium-statusline-chain"

if [ -n "${ATRIUM_PANE_ID:-}" ] && command -v jq >/dev/null 2>&1; then
  bound=false
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && bound=true
  usage="$(printf '%s' "$input" | jq -c --argjson bound "$bound" '
    if ((.rate_limits // .context_window // .cost) == null) then empty
    else {
      rate_limits: .rate_limits,
      context_window: .context_window,
      cost: .cost,
      tokenBound: $bound
    } | with_entries(select(.value != null))
    end
  ' 2>/dev/null || true)"
  if [ -n "$usage" ]; then
    cache="${TMPDIR:-/tmp}/atrium-statusline-${ATRIUM_PANE_ID}.usage"
    prev=""
    [ -f "$cache" ] && prev="$(cat "$cache" 2>/dev/null || true)"
    if [ "$usage" != "$prev" ]; then
      printf '%s' "$usage" > "$cache" 2>/dev/null || true
      # tokenBound: whether THIS session actually runs as a pane-bound
      # account (CLAUDE_CODE_OAUTH_TOKEN in the claude process env, which
      # this relay inherits). Atrium attributes unbound sessions to the
      # ambient login regardless of the pane's binding — without this bit a
      # failed/absent token injection painted the ambient account's usage
      # onto the bound account's row.
      # Fire-and-forget: an orphaned bg job in a non-interactive script is
      # not SIGHUP'd on exit, and the socket write is a few ms.
      printf '%s' "$usage" \
        | "${ATRIUM_CLI_PATH:-atrium}" hook emit usage-update \
            --adapter claude-code --pane-id "${ATRIUM_PANE_ID}" >/dev/null 2>&1 &
    fi
  fi
fi

# Chain to the user's original statusline (fed the same stdin), else print
# nothing (empty statusline).
if [ -s "$CHAIN_FILE" ]; then
  chain="$(cat "$CHAIN_FILE")"
  printf '%s' "$input" | eval "$chain" || true
fi
exit 0
