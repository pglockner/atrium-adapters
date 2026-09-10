#!/usr/bin/env bash
# backup-paths.sh — Tilde-prefixed paths the goose install/uninstall
# touches. test-adapter.sh backs these up before testing and restores
# on exit. (goose-hook.sh and normalize-hook-payload.sh are committed
# adapter files, not install targets.)
echo "~/.agents/plugins/atrium-goose/hooks/hooks.json"
