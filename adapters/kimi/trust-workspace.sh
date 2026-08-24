#!/usr/bin/env bash
# Pre-accept kimi's "Trust this folder?" gate for the launch directory, then
# exec the real command.
#
# kimi ships no --trust flag (cursor-agent does; --yolo/--auto do NOT bypass
# the gate) and the prompt's preselected option is "Don't trust — Exit Kimi
# Code", so Enter quits. This wrapper is emitted ONLY when the launcher's
# `trust` toggle is on; trusting a folder lets kimi auto-start the project-level
# MCP servers declared in that repo, so it stays opt-in.
#
# Trust is a presence check on a record in kimi's atomic document store
# (WorkspaceTrustService: `trusted = docs.get(scope, key) !== undefined`):
#
#   <KIMI_CODE_HOME>/workspace-trust/wd_<slug>_<sha256(dir)[:12]>
#   {"root":"<dir>","trustedAt":<epoch ms>}
#
# where <slug> mirrors kimi's slugifyWorkDirName: the basename lowercased, runs
# of [^a-z0-9._-] collapsed to "-", leading/trailing "-" stripped, truncated to
# 40 chars, re-stripped, and replaced with "workspace" if it empties out.
set -euo pipefail

KIMI_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
TRUST_DIR="${KIMI_HOME}/workspace-trust"
MAX_SLUG_LENGTH=40

sha256_hex() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    return 1
  fi
}

workdir_slug() {
  local slug
  slug="$(printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9._-][^a-z0-9._-]*/-/g' -e 's/^-*//' -e 's/-*$//' |
    cut -c "1-${MAX_SLUG_LENGTH}" |
    sed -e 's/^-*//' -e 's/-*$//')"
  case "$slug" in
    "" | "." | "..") printf 'workspace' ;;
    *) printf '%s' "$slug" ;;
  esac
}

# Never let a trust-write problem block the launch — the worst case is the user
# answers the prompt by hand, which is exactly today's behaviour.
trust_workspace() {
  local root base slug hash key path tmp escaped
  root="$(pwd -P)" || return 0
  base="${root##*/}"
  slug="$(workdir_slug "$base")" || return 0
  hash="$(sha256_hex "$root")" || return 0
  key="wd_${slug}_${hash:0:12}"
  path="${TRUST_DIR}/${key}"

  [ -e "$path" ] && return 0

  mkdir -p "$TRUST_DIR" || return 0
  chmod 700 "$TRUST_DIR" 2>/dev/null || true

  # JSON string escaping: backslash first, then double quote.
  escaped="${root//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"

  tmp="${path}.atrium.$$"
  printf '{"root":"%s","trustedAt":%s}' \
    "$escaped" "$(( $(date +%s) * 1000 ))" > "$tmp" || return 0
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$path" || rm -f "$tmp"
  return 0
}

trust_workspace || true

if [ "$#" -eq 0 ]; then
  echo "trust-workspace.sh: no command to exec" >&2
  exit 64
fi

exec "$@"
