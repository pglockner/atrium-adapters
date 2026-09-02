#!/usr/bin/env bash
set -euo pipefail

# hooks.sh — Report Muse Code hook installation state for atrium.
#
# Muse DOES define a hook system, and its event vocabulary is a superset of
# Claude Code's — the `HookEventKind` enum in the 1.0.2 binary carries
# SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse,
# PreLLMCall, PostLLMCall, PreCompact, PostCompact, SubagentStart,
# SubagentStop, Stop, SessionEnd, Notification, PostToolUseFailure,
# StopFailure and PostToolBatch. Hooks are declared by a native plugin
# (`.muse-plugin/plugin.json`, capability family `hooks`, structured argv with
# a timeout).
#
# But hooks are NOT INSTALLABLE in this build. There is no user-scope plugin
# root and no install command — `muse plugins` answers, verbatim:
#
#     plugins are not available in this build
#
# So the only documented path to a hook (a workspace plugin manifest) cannot be
# loaded, and there is deliberately nothing to write here. We do NOT:
#   - drop a `.muse-plugin/` into the user's repo (it would pollute their tree
#     AND still never load), or
#   - guess at the shape of ~/.local/share/muse/plugins/installed.json, which
#     would be an unverified format whose failure mode is silent — the exact
#     "pushed asset never ships" class this repo already guards against.
#
# Consequence, stated rather than hidden: a Muse TERMINAL pane produces no
# atrium activity cards. Muse CHAT panes are unaffected — the muse-msp
# transport reads MSP's own view stream (turn/*, item/*, approval/*), which
# needs no hooks at all.
#
# When a build ships plugin support, this becomes a real installer: write a
# plugin manifest declaring one hook per event with
# `["sh", "hooks/atrium-hook.sh"]` argv shelling out to `atrium hook emit`,
# then register it. The event names above are already the right set.
#
# Subcommands: install, uninstall, status
# Output: JSON to stdout, diagnostics to stderr

SUBCOMMAND="${1:?Usage: hooks.sh <install|uninstall|status>}"

# `muse --version` already prints "Muse Code <semver> (<build>)", so it is used
# bare here rather than prefixed.
UNAVAILABLE_REASON="$(
  muse --version 2>/dev/null | head -1 || echo "Muse Code (version unknown)"
) has no installable hook surface: \`muse plugins\` reports \"plugins are not available in this build\", and plugin manifests are the only way muse loads a hook. Muse chat panes still report full activity over MSP; terminal panes cannot until muse ships plugin support."

case "$SUBCOMMAND" in
  status)
    printf '{"subcommand":"status","installed":false,"reason":%s}\n' \
      "$(printf '%s' "$UNAVAILABLE_REASON" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
    ;;
  install)
    # Report the honest outcome instead of exiting non-zero: a missing vendor
    # capability is not a broken adapter, and a hard failure here would drag
    # the whole Tools card to "attention" for something the user cannot fix.
    printf '{"subcommand":"install","installed":false,"reason":%s}\n' \
      "$(printf '%s' "$UNAVAILABLE_REASON" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
    ;;
  uninstall)
    # Nothing was ever written, so uninstall is vacuously complete.
    printf '{"subcommand":"uninstall","installed":false}\n'
    ;;
  *)
    echo "{\"error\": \"unknown subcommand: ${SUBCOMMAND}\"}" >&2
    exit 1
    ;;
esac
