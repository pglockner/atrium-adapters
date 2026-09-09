#!/usr/bin/env bash
set -euo pipefail

# state.assert.sh — runs in test-adapter.sh Phase 5. Receives the JSON activity
# state atrium captured after the fixtures were POSTed through /resolve, and
# checks the tool-call lifecycle resolved the way review round 2 asked for:
#   - pre-tool-use carries the tool name + parsed input
#   - the successful post-tool-use has no error
#   - the failed call (PostToolUseFailure, relayed to post-tool-use) carries a
#     non-empty error so the FSM marks it failed, not succeeded
#   - user-prompt-submit / stop still normalize

state="$(cat)"

jq -e '
  ([.events[] | select(.eventName == "pre-tool-use")] | last
    | .payload.tool_name == "shell"
      and (.payload.tool_input_json.command == "echo GOOD-CALL"))
  and
  ([.events[] | select(.eventName == "post-tool-use")]
    | (map(select((.payload.error // "") == "")) | length) >= 1
      and (map(select((.payload.error // "") != "")) | length) >= 1)
  and
  ([.events[] | select(.eventName == "user-prompt-submit")] | last
    | .payload.user_prompt == "Summarize the README.")
  and
  ([.events[] | select(.eventName == "stop")] | last
    | .payload.last_assistant_message == "Output: `hello-from-goose`")
' <<<"$state" >/dev/null
