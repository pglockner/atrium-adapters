#!/usr/bin/env bash
set -euo pipefail

skill="skills/atrium-bug-report/SKILL.md"

require() {
  local pattern="$1"
  local message="$2"
  if ! grep -Eq "$pattern" "$skill"; then
    echo "atrium-bug-report contract: $message" >&2
    exit 1
  fi
}

reject() {
  local pattern="$1"
  local message="$2"
  if grep -Eq "$pattern" "$skill"; then
    echo "atrium-bug-report contract: $message" >&2
    exit 1
  fi
}

require 'atrium-contract-reviewed-through: [0-9a-f]{40}' 'missing full atrium review marker'
require 'runtime\.<YYYY-MM-DD>\.log.*background daemon \(`atriumd`\)' 'runtime log ownership drifted'
require 'chat-runtime\.<YYYY-MM-DD>\.log' 'chat-runtime log is absent from the artifact map'
for artifact in video.mov transcript.jsonl events.jsonl chapters.json annotations.json; do
  require "$artifact" "capture bundle inventory is missing $artifact"
done
require 'issues/new\?title=<urlencoded-title>&body=<urlencoded-approved-body>' 'fallback must preserve the approved issue body'
require 'Never shell out to `ffmpeg`, `ffprobe`, `sips`, or ImageMagick' 'capture investigation must require atrium native commands'

reject 'labels=bug,source:in-app' 'fallback still assumes unprovisioned labels'
reject 'for L in bug source:in-app' 'posting still silently mutates an unprovisioned taxonomy'
reject '^## `area:` labels|— `area:' 'unprovisioned area labels have returned'
reject 'typical busy day logs|~15,000 INFO' 'static log-volume calibration has returned'

echo "atrium-bug-report contract: ok"
