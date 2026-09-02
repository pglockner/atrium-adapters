#!/usr/bin/env bash
# muse-session-enumeration.assert.sh
#
# Pins the two things muse's session enumerator gets wrong most easily, both
# specific to how muse stores sessions:
#
#  1. The date-partitioned root (<Y>/<M>/<D>/<uuid>/session.jsonl) has no
#     cwd-encoded path, so the workspace must be read out of each log's
#     `runtime.session.metadata` record — and matched by REALPATH, because muse
#     records the resolved root (`/private/tmp`) for a session the user started
#     in `/tmp`.
#  2. Subagent child logs live in the same root and must NOT be listed: the
#     method contract forbids emitting parented child sessions, and resuming
#     one would reattach to a child transcript. The discriminator is
#     `agent_tree_initialized.root_session_id != session_id`.
#
# Also pins the extractor's user-prose mapping, which reads
# `runtime.user_intent.accepted` (durable) and NOT the `turn.input.user` record
# that only exists on the ephemeral `exec --json` stream.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

for dependency in jq python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'muse-session-enumeration: missing dependency %s\n' "$dependency" >&2
    exit 1
  fi
done

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

SESSION_ROOT="${FIXTURE_ROOT}/sessions"
WORKSPACE="${FIXTURE_ROOT}/workspace"
mkdir -p "$WORKSPACE"

ROOT_SESSION="01a06000-0000-7000-8000-00000000root"
CHILD_SESSION="01a06000-0000-7000-8000-0000000child"
OTHER_SESSION="01a06000-0000-7000-8000-0000000other"

# The metadata record carries the RESOLVED workspace root, which on macOS
# differs from the path the caller passes ($TMPDIR is a /var symlink).
WORKSPACE_REAL="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$WORKSPACE")"

write_session() {
  local session_id="$1" root_session_id="$2" workspace="$3" prompt="$4"
  local dir="${SESSION_ROOT}/2026/09/02/${session_id}"
  mkdir -p "$dir"
  {
    # A transaction frame: the real records are JSON strings under children[].
    python3 - "$session_id" "$workspace" <<'PY'
import json, sys
session_id, workspace = sys.argv[1], sys.argv[2]
def rec(seq, payload_type, payload):
    return json.dumps({
        "schema_version": 1,
        "id": f"rec-{seq}",
        "stream": {"kind": "session", "id": session_id},
        "sequence": seq,
        "recorded_at": 1788380138000000 + seq,
        "record_type": "event",
        "durability": "durable",
        "payload_type": payload_type,
        "payload_schema_version": 1,
        "payload": payload,
    })
print(json.dumps({
    "retained_frame": "session_permission_transaction",
    "frame_schema_version": 1,
    "outer_log_ordinal": 1,
    "transaction_id": "txn-1",
    "children": [
        {"child_index": 0, "record_json": rec(1, "runtime.session.metadata", {
            "kind": "metadata",
            "record": {"workspace_root": workspace, "provider_id": "meta"},
        })},
    ],
}))
print(rec(2, "session.opened.observed", {
    "kind": "session_opened",
    "record": {"schema_version": 1, "session_id": session_id, "resume": False},
}))
PY
    python3 - "$session_id" "$root_session_id" "$prompt" <<'PY'
import json, sys
session_id, root_session_id, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
def rec(seq, payload_type, payload):
    return json.dumps({
        "schema_version": 1,
        "id": f"rec-{seq}",
        "stream": {"kind": "session", "id": session_id},
        "sequence": seq,
        "recorded_at": 1788380138000000 + seq,
        "record_type": "event",
        "durability": "durable",
        "payload_type": payload_type,
        "payload_schema_version": 1,
        "payload": payload,
    })
print(rec(3, "runtime.session", {
    "kind": "agent_tree_initialized",
    "record": {
        "schema_version": 1,
        "root_agent_id": root_session_id,
        "root_session_id": root_session_id,
    },
}))
print(rec(4, "runtime.user_intent.accepted", {
    "intent_id": "intent-1",
    "source_session_id": session_id,
    "surface": "main",
    "semantic_kind": {"kind": "chat"},
    "refill_blocks": [{"kind": "text", "text": prompt}],
    "model_messages": [{"content": [{"kind": "text", "text": prompt}]}],
}))
print(rec(5, "session.end", {
    "kind": "session_end",
    "record": {"schema_version": 1, "session_id": session_id, "exit_reason": "clean"},
}))
PY
  } >"${dir}/session.jsonl"
}

write_session "$ROOT_SESSION" "$ROOT_SESSION" "$WORKSPACE_REAL" "hello from the root session"
# Same workspace, but parented to the root session -> a subagent's own log.
write_session "$CHILD_SESSION" "$ROOT_SESSION" "$WORKSPACE_REAL" "child work"
# A root session in a different workspace -> must not leak into this listing.
write_session "$OTHER_SESSION" "$OTHER_SESSION" "/somewhere/else" "unrelated"

OUTPUT="$(
  ATRIUM_TEST_MUSE_SESSION_ROOT="$SESSION_ROOT" \
    bash "$ROOT/adapters/muse/list_recent_sessions.sh" "$WORKSPACE"
)" || {
  printf '[FAIL] muse enumerator exited unsuccessfully\n'
  exit 1
}

IDS="$(jq -cer '[.sessions[].id]' <<<"$OUTPUT")" || {
  printf '[FAIL] muse emitted invalid session JSON: %s\n' "$OUTPUT"
  exit 1
}

if [[ "$IDS" != "[\"${ROOT_SESSION}\"]" ]]; then
  printf '[FAIL] muse must list exactly the root session for this workspace\n'
  printf '  expected: ["%s"]\n' "$ROOT_SESSION"
  printf '  actual:   %s\n' "$IDS"
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse lists the root session and excludes subagent child logs\n'
fi

SOURCE_PATH="$(jq -r '.sessions[0].sourcePath // ""' <<<"$OUTPUT")"
if [[ -z "$SOURCE_PATH" || ! -f "$SOURCE_PATH" ]]; then
  printf '[FAIL] muse sourcePath missing or not a file: %s\n' "$SOURCE_PATH"
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse emits its indexable source path\n'
fi

LISTED_CWD="$(jq -r '.sessions[0].cwd // ""' <<<"$OUTPUT")"
if [[ "$LISTED_CWD" != "$WORKSPACE_REAL" ]]; then
  printf '[FAIL] muse must report the workspace root from the log (%s), got %s\n' \
    "$WORKSPACE_REAL" "$LISTED_CWD"
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse matches a workspace through its resolved realpath\n'
fi

# --- extractor -------------------------------------------------------------
EVENTS="$(
  ATRIUM_TEST_MUSE_SESSION_ROOT="$SESSION_ROOT" \
    bash "$ROOT/adapters/muse/extract_session.sh" \
    --session-id "$ROOT_SESSION" --cwd "$WORKSPACE_REAL" --depth standard
)" || {
  printf '[FAIL] muse extractor exited unsuccessfully\n'
  exit 1
}

TYPES="$(jq -sc '[.[].type]' <<<"$EVENTS")"
if [[ "$TYPES" != '["session_start","prose","session_end"]' ]]; then
  printf '[FAIL] muse extractor event sequence mismatch: %s\n' "$TYPES"
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse extractor brackets prose with session_start/session_end\n'
fi

PROSE="$(jq -sr '.[] | select(.type == "prose") | "\(.role):\(.text)"' <<<"$EVENTS")"
if [[ "$PROSE" != "user:hello from the root session" ]]; then
  printf '[FAIL] muse extractor prose mismatch: %s\n' "$PROSE"
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse extractor reads user prose from runtime.user_intent.accepted\n'
fi

# A session id with no log is "source not found" (exit 1), not a parse error.
if ATRIUM_TEST_MUSE_SESSION_ROOT="$SESSION_ROOT" \
  bash "$ROOT/adapters/muse/extract_session.sh" \
  --session-id "01a06000-0000-7000-8000-00000000none" >/dev/null 2>&1; then
  printf '[FAIL] muse extractor must exit non-zero for an unknown session\n'
  FAILURES=$((FAILURES + 1))
else
  STATUS=$?
  if [[ "$STATUS" -ne 1 ]]; then
    printf '[FAIL] muse extractor must exit 1 (source-not-found), got %s\n' "$STATUS"
    FAILURES=$((FAILURES + 1))
  else
    printf '[PASS] muse extractor exits 1 for an unknown session\n'
  fi
fi

# --- hooks -----------------------------------------------------------------
# Muse 1.0.2 has no installable hook surface. The adapter must SAY so with a
# reason rather than claim success, or the Tools card would show hooks as
# healthy and the user would wait forever for terminal-pane activity.
HOOKS_STATUS="$(bash "$ROOT/adapters/muse/hooks.sh" status)"
if [[ "$(jq -r '.installed' <<<"$HOOKS_STATUS")" != "false" ]]; then
  printf '[FAIL] muse hooks.sh must report installed=false\n'
  FAILURES=$((FAILURES + 1))
elif [[ -z "$(jq -r '.reason // ""' <<<"$HOOKS_STATUS")" ]]; then
  printf '[FAIL] muse hooks.sh must explain why hooks are unavailable\n'
  FAILURES=$((FAILURES + 1))
else
  printf '[PASS] muse hooks.sh reports its unavailability with a reason\n'
fi

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
printf 'muse-session-enumeration: all checks passed\n'
