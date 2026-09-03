#!/usr/bin/env bash
set -euo pipefail

# build_eval_command.sh — one headless muse turn, used as atrium's hidden
# completion judge for emulated /goal and /loop.
# Output: {"command": [...], "acceptsPromptFile": true}
#
# `muse exec --prompt-file <path>` is the one-shot form. The prompt arrives as
# a FILE rather than on stdin because the judge prompt embeds a transcript tail
# that routinely contains backticks, quotes and newlines; a file avoids every
# shell-quoting hazard on the way in.
#
# Flags, and why each one is load-bearing:
#
#   --disable-approval  A judge that stops to ask permission hangs until the
#                       evaluation times out. It never needs to write anything.
#   --provider meta     Pinned so the judge cannot inherit an `echo` provider
#                       from an ambient config and silently return nonsense.
#
# Reasoning effort is deliberately NOT lowered. Measured on muse 1.0.2: wall
# time is dominated by process spawn, not reasoning (high 5.4s, low 6.5s,
# minimal 3.6s), and `minimal` returned a WRONG verdict on a case both higher
# tiers judged correctly. The adapter default is the right trade.

if ! command -v jq &>/dev/null; then
  echo '{"command": ["muse", "exec", "--disable-approval", "--provider", "meta", "--prompt-file"], "acceptsPromptFile": true}'
  exit 0
fi

jq -nc '{
  command: ["muse", "exec", "--disable-approval", "--provider", "meta", "--prompt-file"],
  acceptsPromptFile: true
}'
exit 0
