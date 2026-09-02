#!/usr/bin/env bash
set -euo pipefail

# extract_session.sh — Emit canonical session events for Muse Code.
# Contract: see ../../schemas/canonical-event.schema.json
#
# Args: --session-id <id> --cwd <path> --depth <quick|standard>
# Env:  ATRIUM_TEST_MUSE_SESSION_ROOT (CI fixtures — overrides the production
#       ~/.local/share/muse/sessions root)
#
# Exit codes: 0=ok, 1=source-not-found, 2=parse-error, 3=IO error
#   (e.g. python3 missing), >=10=usage/fatal.

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
  echo "extract_session: python3 required (install python3 on this system)" >&2
  exit 3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/extract_session.py" \
  --session-id "$SESSION_ID" \
  --cwd "$CWD" \
  --depth "$DEPTH"
