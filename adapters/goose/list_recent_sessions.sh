#!/usr/bin/env bash
set -euo pipefail

cwd="${1:?working directory required}"

# Goose stores every session in one SQLite database rather than per-session
# transcript files, so that database is the indexable source for all of them.
# Its location depends on GOOSE_PATH_ROOT / XDG_DATA_HOME (see
# resolve_session_db.sh). Emitted only when it exists; the field is optional
# and must name a real file.
db_path="$("$(dirname "$0")/resolve_session_db.sh")"
[ -f "$db_path" ] || db_path=""

sessions_json=$(goose session list --format json --working_dir "$cwd" 2>/dev/null || echo '[]')

echo "$sessions_json" | jq -c --arg source_path "$db_path" '
  {
    sessions: [
      (. // [])[]
      | select(.parent_session_id == null)
      | {
          id: .id,
          name: (.name // null),
          cwd: .working_dir,
          lastActive: (.last_message_at // .updated_at)
        }
        + (if $source_path == "" then {} else {sourcePath: $source_path} end)
    ]
  }
'
