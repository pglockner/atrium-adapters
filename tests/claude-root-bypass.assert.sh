#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REAL_PATH="$PATH"

write_fake_id() {
  printf '#!/usr/bin/env bash\necho "%s"\n' "$1" >"$TMP/id"
  chmod +x "$TMP/id"
}

assert_root_command() {
  local output="$1"
  jq -e '
    .command[0:5] == [
      "env",
      "DISABLE_AUTOUPDATER=1",
      "ATRIUM_CLAUDE_ROOT_BYPASS_PERMISSIONS=1",
      "claude",
      "--permission-mode"
    ]
    and .command[5] == "acceptEdits"
    and (.command | index("--dangerously-skip-permissions") == null)
  ' <<<"$output" >/dev/null
}

write_fake_id 0
root_launch="$(PATH="$TMP:$REAL_PATH" "$ADAPTER/build_launch_command.sh" \
  '{"dangerouslySkipPermissions":true,"model":"sonnet","effort":"medium"}')"
assert_root_command "$root_launch"

root_resume="$(PATH="$TMP:$REAL_PATH" "$ADAPTER/build_resume_command.sh" \
  session-123 '{"dangerouslySkipPermissions":true,"model":"sonnet"}')"
assert_root_command "$root_resume"
jq -e '.command[-2:] == ["--resume", "session-123"]' \
  <<<"$root_resume" >/dev/null

write_fake_id 501
non_root_launch="$(PATH="$TMP:$REAL_PATH" "$ADAPTER/build_launch_command.sh" \
  '{"dangerouslySkipPermissions":true}')"
jq -e '
  (.command | index("--dangerously-skip-permissions") != null)
  and (.command | index("ATRIUM_CLAUDE_ROOT_BYPASS_PERMISSIONS=1") == null)
  and (.command | index("acceptEdits") == null)
' <<<"$non_root_launch" >/dev/null

cat >"$TMP/atrium" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 0
EOF
chmod +x "$TMP/atrium"

permission_payload='{"session_id":"abc","transcript_path":"/tmp/abc.jsonl","cwd":"/tmp","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"true"}}'
allow_output="$(printf '%s' "$permission_payload" \
  | env -u ATRIUM_CHAT_SDK_HOOKS \
    ATRIUM_CLI_PATH="$TMP/atrium" \
    ATRIUM_CLAUDE_ROOT_BYPASS_PERMISSIONS=1 \
    "$ADAPTER/claude-hook-entry.sh" permission-request)"
jq -e '
  .hookSpecificOutput.hookEventName == "PermissionRequest"
  and .hookSpecificOutput.decision.behavior == "allow"
' <<<"$allow_output" >/dev/null

ordinary_output="$(printf '%s' "$permission_payload" \
  | env -u ATRIUM_CHAT_SDK_HOOKS \
    ATRIUM_CLI_PATH="$TMP/atrium" \
    "$ADAPTER/claude-hook-entry.sh" permission-request)"
test -z "$ordinary_output"

echo "claude root bypass: ok"
