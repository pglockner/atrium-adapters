#!/usr/bin/env bash
set -euo pipefail

# Goose keeps every session in one SQLite database, and its location moves with
# GOOSE_PATH_ROOT / XDG_DATA_HOME. list_recent_sessions.sh and
# extract_session.sh must resolve the same path, or a session discovered under
# one root gets handed to an extractor opening a different database.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVE="${ROOT}/adapters/goose/resolve_session_db.sh"
FAILURES=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '[PASS] %s\n' "$desc"
  else
    printf '[FAIL] %s\n  expected: %s\n  actual:   %s\n' "$desc" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

check 'GOOSE_PATH_ROOT wins (flat $ROOT/data layout, not XDG)' \
  "/root/data/sessions/sessions.db" \
  "$(env -u XDG_DATA_HOME GOOSE_PATH_ROOT=/root "$RESOLVE")"

check "GOOSE_PATH_ROOT beats XDG_DATA_HOME" \
  "/root/data/sessions/sessions.db" \
  "$(GOOSE_PATH_ROOT=/root XDG_DATA_HOME=/xdg "$RESOLVE")"

check "XDG_DATA_HOME when no GOOSE_PATH_ROOT" \
  "/xdg/goose/sessions/sessions.db" \
  "$(env -u GOOSE_PATH_ROOT XDG_DATA_HOME=/xdg "$RESOLVE")"

check "default \$HOME/.local/share" \
  "${HOME}/.local/share/goose/sessions/sessions.db" \
  "$(env -u GOOSE_PATH_ROOT -u XDG_DATA_HOME "$RESOLVE")"

# Goose ignores a relative GOOSE_PATH_ROOT (crates/goose/src/config/paths.rs);
# the resolver must too, or it opens a DB Goose isn't using.
check "relative GOOSE_PATH_ROOT is ignored (falls through to XDG)" \
  "/xdg/goose/sessions/sessions.db" \
  "$(GOOSE_PATH_ROOT=relative/root XDG_DATA_HOME=/xdg "$RESOLVE")"

check "relative GOOSE_PATH_ROOT is ignored (falls through to \$HOME)" \
  "${HOME}/.local/share/goose/sessions/sessions.db" \
  "$(env -u XDG_DATA_HOME GOOSE_PATH_ROOT=relative/root "$RESOLVE")"

# hooks.sh must install to Goose's rooted plugin dir for an absolute
# GOOSE_PATH_ROOT, and to $HOME for a relative one.
HOOKS_SH="${ROOT}/adapters/goose/hooks.sh"
hooks_rooted="$(mktemp -d)"
GOOSE_PATH_ROOT="$hooks_rooted" bash "$HOOKS_SH" install >/dev/null
check "hooks.sh honors absolute GOOSE_PATH_ROOT for the plugin dir" \
  "present" \
  "$([ -f "${hooks_rooted}/.agents/plugins/atrium-goose/hooks/hooks.json" ] && echo present || echo missing)"
GOOSE_PATH_ROOT="$hooks_rooted" bash "$HOOKS_SH" uninstall >/dev/null
check "hooks.sh ignores a relative GOOSE_PATH_ROOT for the plugin dir" \
  "missing" \
  "$([ -e "${hooks_rooted}/relative" ] && echo present || echo missing)"
rm -rf "$hooks_rooted"

# Both consumers must call the resolver, not hardcode a path.
for consumer in list_recent_sessions.sh extract_session.sh; do
  if grep -q 'resolve_session_db.sh' "${ROOT}/adapters/goose/${consumer}"; then
    printf '[PASS] %s calls resolve_session_db.sh\n' "$consumer"
  else
    printf '[FAIL] %s does not call resolve_session_db.sh\n' "$consumer"
    FAILURES=$((FAILURES + 1))
  fi
done

# The fixture hook still overrides.
tmpd="$(mktemp -d)"; : > "${tmpd}/sessions.db"
check "ATRIUM_TEST_TRANSCRIPT_ROOT overrides everything" \
  "${tmpd}/sessions.db" \
  "$(ATRIUM_TEST_TRANSCRIPT_ROOT="$tmpd" GOOSE_PATH_ROOT=/root "$RESOLVE")"
rm -rf "$tmpd"

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
printf 'goose-session-db-resolution: all checks passed\n'
