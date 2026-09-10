#!/usr/bin/env bash
set -euo pipefail

# Runs extract_session.py against a sanitized Goose 1.50.0 fixture DB and
# checks the behaviours review point 5 called out:
#   - the 1.48+ {"status","value":{...}} tool envelope is unwrapped
#     (tool name + input are real, not "unknown"/{})
#   - a tool result is correlated to its request by shared id
#   - results are emitted only for the shell/developer allowlist
#   - turn-context / non-user-visible messages are filtered via metadata_json

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="${HERE}/../../extract_session.py"
SID="20260908_fix"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
sqlite3 "${TMPD}/sessions.db" < "${HERE}/fixture.sql"

OUT="$(python3 "$EXTRACTOR" --db "${TMPD}/sessions.db" --session-id "$SID" --cwd /work/proj --depth deep)"

fail() { echo "extractor.assert: $1" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

echo "$OUT" | jq -e 'select(.type=="tool_use" and .tool=="shell") | .input.command == "ls -1"' >/dev/null \
  || fail "shell tool_use missing real input (1.48+ .value envelope not unwrapped)"

echo "$OUT" | jq -e 'select(.type=="tool_use") | select(.tool=="unknown")' >/dev/null \
  && fail "a tool_use was emitted with tool=unknown" || true

RES="$(echo "$OUT" | jq -c 'select(.type=="tool_result")')"
[ "$(echo "$RES" | jq -s 'length')" -eq 1 ] \
  || fail "expected exactly one tool_result (shell allowlisted, load dropped); got: $RES"
echo "$RES" | jq -e '.tool=="shell" and .tool_use_id=="call_shell_1" and (.text|contains("README.md")) and (.tool_use_id|length>0)' >/dev/null \
  || fail "shell tool_result not correlated / mislabeled / empty"
echo "$OUT" | jq -e 'select(.type=="tool_result" and .tool_use_id=="call_load_1")' >/dev/null \
  && fail "non-allowlisted 'load' tool_result was emitted" || true

echo "$OUT" | jq -e 'select(.type=="prose" and (.text|contains("turn-context")))' >/dev/null \
  && fail "turn-context message leaked into the transcript" || true

echo "extractor.assert: all checks passed"
