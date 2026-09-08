#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "extract_session: python3 required" >&2
  exit 3
fi
exec python3 "$(dirname "$0")/extract_session.py" "$@"
