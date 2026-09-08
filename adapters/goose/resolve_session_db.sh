#!/usr/bin/env bash
set -euo pipefail

# resolve_session_db.sh — single source of truth for the path to Goose's
# SQLite session store. Goose keeps every session in one database; where that
# database lives depends on how Goose's paths are rooted:
#
#   GOOSE_PATH_ROOT set   ->  $GOOSE_PATH_ROOT/data/sessions/sessions.db
#   else XDG_DATA_HOME set ->  $XDG_DATA_HOME/goose/sessions/sessions.db
#   else                  ->  $HOME/.local/share/goose/sessions/sessions.db
#
# (GOOSE_PATH_ROOT relocates Goose's whole tree to $ROOT/{data,state,config,cache}
# and is NOT an XDG-style layout — verified against goose 1.49.0.)
#
# ATRIUM_TEST_TRANSCRIPT_ROOT/sessions.db, when present, wins — the fixtures hook.
#
# Prints the resolved path to stdout (whether or not the file exists); callers
# check for existence themselves.

if [ -n "${ATRIUM_TEST_TRANSCRIPT_ROOT:-}" ] && [ -f "${ATRIUM_TEST_TRANSCRIPT_ROOT}/sessions.db" ]; then
  printf '%s\n' "${ATRIUM_TEST_TRANSCRIPT_ROOT}/sessions.db"
elif [ -n "${GOOSE_PATH_ROOT:-}" ]; then
  printf '%s\n' "${GOOSE_PATH_ROOT}/data/sessions/sessions.db"
elif [ -n "${XDG_DATA_HOME:-}" ]; then
  printf '%s\n' "${XDG_DATA_HOME}/goose/sessions/sessions.db"
else
  printf '%s\n' "${HOME}/.local/share/goose/sessions/sessions.db"
fi
