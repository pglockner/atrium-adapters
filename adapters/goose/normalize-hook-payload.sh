#!/usr/bin/env bash
set -uo pipefail

# normalize-hook-payload.sh — map a Goose Open Plugins hook payload onto the
# field names atrium's activity FSM consumes, then pass it through. On any
# error the original payload is emitted unchanged (a hook must never fail the
# session).
#
# Goose 1.49.0 fires exactly four Open Plugins events to a plugin's hooks.json:
# SessionStart, UserPromptSubmit, Stop, SessionEnd. The tool-level events
# (PreToolUse/PostToolUse/PostToolUseFailure) are enum variants that are not
# dispatched to plugins in 1.49.0, so there is nothing to normalize for them.

EVENT="${1:-}"
INPUT="$(cat 2>/dev/null || true)"

emit_raw() { printf '%s' "$INPUT"; }

case "$EVENT" in
  user-prompt-submit)
    # Goose sends the prompt as `message`; atrium wants `prompt`/`user_prompt`.
    printf '%s' "$INPUT" | jq -c '
      (.message // .matcher_context // "") as $p
      | . + {prompt: $p, user_prompt: $p}
    ' 2>/dev/null || emit_raw
    ;;

  stop)
    # Goose already provides `last_assistant_message`; also expose it as
    # `assistant_message` for FSMs that key on that name.
    printf '%s' "$INPUT" | jq -c '
      (.last_assistant_message // "") as $m
      | . + (if $m == "" then {} else {assistant_message: $m} end)
    ' 2>/dev/null || emit_raw
    ;;

  *)
    emit_raw
    ;;
esac
