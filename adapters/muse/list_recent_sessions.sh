#!/usr/bin/env bash
set -euo pipefail

# list_recent_sessions.sh — List recent, directly-resumable Muse Code sessions.
# Takes $1 = CWD
# Output: {"sessions": [{id, name, cwd, lastActive, sourcePath}, ...]}
#
# Muse stores one directory per session under a date-partitioned root:
#   ~/.local/share/muse/sessions/<YYYY>/<MM>/<DD>/<session-uuid>/session.jsonl
# There is no cwd-encoded path (unlike Claude's project dirs), so the workspace
# has to be read out of each log's metadata record.
#
# Delegated to python3 in ONE process rather than a shell loop: the records are
# JSON, some arrive wrapped in `session_permission_transaction` frames whose
# real payloads live in `children[].record_json` (a JSON string inside JSON),
# and a per-file jq/sed invocation would blow the <50ms adapter budget.
#
# Env: ATRIUM_TEST_MUSE_SESSION_ROOT — overrides the session root (CI fixtures).

CWD="${1:?Usage: list_recent_sessions.sh <cwd>}"

if ! command -v python3 &>/dev/null; then
  echo '{"sessions": []}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/list_recent_sessions.py" "$CWD"
