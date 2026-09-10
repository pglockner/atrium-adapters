#!/usr/bin/env bash
set -euo pipefail

# state.assert.sh — runs in test-adapter.sh Phase 5. Receives the JSON activity
# state atrium captured after the fixtures were POSTed through /resolve.
#
# Phase 4 POSTs each fixture under its directory basename, so it does NOT run
# goose-hook.sh and cannot exercise the PostToolUseFailure -> post-tool-use
# fold — that is covered end-to-end in tests/relay.assert.sh. Here we assert
# only what the harness actually delivers for goose:
#   - pre-tool-use carries the tool name + parsed input
#   - the clean post-tool-use has no error
#   - the failure payload normalized to a non-empty error (stored as its own
#     event because Phase 4 never folds it)
#   - user-prompt-submit / stop still normalize

state="$(cat)"

jq -e '
  ([.events[] | select(.eventName == "pre-tool-use")] | last
    | .payload.tool_name == "shell"
      and (.payload.tool_input_json.command == "echo GOOD-CALL"))
  and
  ([.events[] | select(.eventName == "post-tool-use")] | last
    | (.payload.error // "") == ""
      and (.payload.tool_input_json.command == "echo GOOD-CALL"))
  and
  ([.events[] | select(.eventName == "post-tool-use-failure")] | last
    | (.payload.error // "") != "")
  and
  ([.events[] | select(.eventName == "user-prompt-submit")] | last
    | .payload.user_prompt == "Summarize the README.")
  and
  ([.events[] | select(.eventName == "stop")] | last
    | .payload.last_assistant_message == "Output: `hello-from-goose`")
' <<<"$state" >/dev/null
