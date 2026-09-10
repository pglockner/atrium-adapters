#!/usr/bin/env bash
set -uo pipefail

# normalize-hook-payload.sh — map a Goose Open Plugins hook payload onto the
# field names atrium's activity FSM consumes, then pass it through. On any
# error the original payload is emitted unchanged (a hook must never fail the
# session).
#
# Goose 1.50.0 dispatches these events to a plugin's hooks.json: SessionStart,
# SessionEnd, UserPromptSubmit, Stop, and (restored on the normal execution
# path in 1.50) PreToolUse / PostToolUse / PostToolUseFailure. Tool events carry
# session_id / tool_call_id / tool_name / tool_input / working_dir — never the
# tool result, so none is synthesized.

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

  pre-tool-use|post-tool-use)
    # tool_input is an object; the FSM wants it stringified plus the raw object.
    printf '%s' "$INPUT" | jq -c '
      (.tool_input // {}) as $ti
      | . + {
          tool_input: (if ($ti | type) == "string" then $ti else ($ti | tojson) end),
          tool_input_json: $ti
        }
    ' 2>/dev/null || emit_raw
    ;;

  post-tool-use-failure)
    # Relayed to the post-tool-use endpoint. Goose's PostToolUseFailure carries
    # no error text, so synthesize a non-empty `error` — that is the signal the
    # FSM needs to mark the call failed rather than succeeded (not tool output).
    printf '%s' "$INPUT" | jq -c '
      (.tool_input // {}) as $ti
      | . + {
          tool_input: (if ($ti | type) == "string" then $ti else ($ti | tojson) end),
          tool_input_json: $ti,
          error: (.error // "Goose reported the tool call failed")
        }
    ' 2>/dev/null || emit_raw
    ;;

  *)
    emit_raw
    ;;
esac
