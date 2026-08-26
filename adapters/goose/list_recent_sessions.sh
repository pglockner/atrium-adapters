#!/usr/bin/env bash
set -euo pipefail

cwd="${1:?working directory required}"

sessions_json=$(goose session list --format json --working_dir "$cwd" 2>/dev/null || echo '[]')

echo "$sessions_json" | jq -c '
  {
    sessions: [
      (. // [])[]
      | select(.parent_session_id == null)
      | {
          id: .id,
          name: (.name // null),
          cwd: .working_dir,
          lastActive: .updated_at
        }
    ]
  }
'
