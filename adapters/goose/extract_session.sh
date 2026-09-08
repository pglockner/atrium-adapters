#!/usr/bin/env bash
set -euo pipefail

# extract_session.sh — Emit canonical session events for Goose.
# Contract: see ../../schemas/canonical-event.schema.json
#
# Goose stores sessions and messages in one local SQLite database; its location
# depends on GOOSE_PATH_ROOT / XDG_DATA_HOME (see resolve_session_db.sh).
#
# Args: --session-id <id> --cwd <path> --depth <quick|standard|deep>
# Exit codes: 0=ok, 1=source-not-found, 2=parse-error, 3=IO error, >=10=usage/fatal.

SESSION_ID=""
CWD=""
DEPTH="standard"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --cwd)        CWD="$2";        shift 2 ;;
    --depth)      DEPTH="$2";      shift 2 ;;
    *) echo "extract_session: unknown arg $1" >&2; exit 10 ;;
  esac
done

if [[ -z "$SESSION_ID" ]]; then
  echo "extract_session: --session-id required" >&2
  exit 10
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "extract_session: python3 required" >&2
  exit 3
fi

DB_FILE="$("$(dirname "$0")/resolve_session_db.sh")"

if [[ ! -f "$DB_FILE" ]]; then
  echo "extract_session: goose database not found: $DB_FILE" >&2
  exit 1
fi

exec python3 "$(dirname "$0")/extract_session.py" \
  --db "$DB_FILE" \
  --session-id "$SESSION_ID" \
  --adapter goose \
  --cwd "$CWD" \
  --depth "$DEPTH"
