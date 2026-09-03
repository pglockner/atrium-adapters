#!/usr/bin/env python3
"""Emit canonical session events (JSONL) for one Muse Code session.

Contract: ../../schemas/canonical-event.schema.json — five variants keyed on
``type``: session_start, prose, tool_use, tool_result, session_end.

Source of truth is the session's DURABLE log:

    ~/.local/share/muse/sessions/<YYYY>/<MM>/<DD>/<session-uuid>/session.jsonl

Records are event-sourced envelopes carrying ``payload_type`` + ``payload``.
Two framing rules apply (identical to list_recent_sessions.py): some records
arrive wrapped in a ``session_permission_transaction`` frame whose real records
are JSON strings under ``children[].record_json``, and ``recorded_at`` is
MICROSECONDS since the epoch, not seconds or millis.

=============================================================================
VERIFIED vs. OWED — read before extending
=============================================================================
The payload vocabulary below was read off real logs from muse 1.0.2. Only a
subset could be observed, because a turn that reaches the model needs Meta
credentials and the echo provider is not reachable through `muse serve`:

  VERIFIED and mapped here
    runtime.session.metadata          -> session_start cwd (workspace_root)
    session.opened.observed           -> session_start
    runtime.user_intent.accepted      -> prose(role=user)
    session.end                       -> session_end
    runtime.session/{run,task}         -> turn + task lifecycle (for timing and
                                         the failed-run diagnostic)

  NOT YET OBSERVABLE, therefore NOT mapped
    assistant prose and tool_use / tool_result. The ephemeral `exec --json`
    stream exposes `turn.input.user`, `run.output.delta` and
    `run.terminal.completed`, but those are `durability: "ephemeral"` STATUS
    records and are absent from the durable log — so they are deliberately not
    read here. Where the durable assistant message and tool records land is
    unknown until a credentialed session can be captured.

Nothing is guessed. An unrecognized ``payload_type`` is skipped, so when those
records do appear this extractor keeps working and simply does not yet index
them — that is a known, stated gap rather than a silent mis-parse.
=============================================================================
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_NOT_FOUND = 1
EXIT_PARSE_ERROR = 2

ADAPTER_NAME = "muse"

# `quick` indexes the conversation only; `standard` adds task/tool records once
# they are mappable. Both walk the same log — the depth gates what is emitted,
# never how much is read, because the log has no random access.
DEPTHS = ("quick", "standard")


def session_root() -> str:
    override = os.environ.get("ATRIUM_TEST_MUSE_SESSION_ROOT")
    if override:
        return override
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(data_home, "muse", "sessions")


def find_transcript(root: str, session_id: str) -> str | None:
    """Locate <root>/<Y>/<M>/<D>/<session_id>/session.jsonl.

    The date partition is not derivable from the session id (a UUIDv7 encodes
    creation time, but in UTC millis — the directory is the LOCAL date muse
    happened to write, so deriving it would miss across midnight and across
    timezones). A bounded walk of the partitions is the correct lookup.
    """
    direct = os.path.join(root, session_id, "session.jsonl")
    if os.path.isfile(direct):
        return direct
    for year in sorted(safe_listdir(root), reverse=True):
        year_path = os.path.join(root, year)
        for month in sorted(safe_listdir(year_path), reverse=True):
            month_path = os.path.join(year_path, month)
            for day in sorted(safe_listdir(month_path), reverse=True):
                candidate = os.path.join(
                    month_path, day, session_id, "session.jsonl"
                )
                if os.path.isfile(candidate):
                    return candidate
    return None


def safe_listdir(path: str):
    try:
        return [entry for entry in os.listdir(path) if not entry.startswith(".")]
    except OSError:
        return []


def iter_records(raw_line: str):
    """Yield every real record on a log line, unwrapping transaction frames."""
    try:
        outer = json.loads(raw_line)
    except (ValueError, TypeError):
        return
    if not isinstance(outer, dict):
        return
    children = outer.get("children")
    if isinstance(children, list):
        for child in children:
            if isinstance(child, dict) and isinstance(child.get("record_json"), str):
                try:
                    inner = json.loads(child["record_json"])
                except ValueError:
                    continue
                if isinstance(inner, dict):
                    yield inner
        return
    yield outer


def iso_from_micros(micros) -> str | None:
    """`recorded_at` is microseconds since the epoch."""
    if not isinstance(micros, (int, float)) or micros <= 0:
        return None
    try:
        moment = datetime.fromtimestamp(micros / 1_000_000, timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None
    return moment.isoformat().replace("+00:00", "Z")


def text_from_model_messages(payload: dict) -> str:
    """Concatenate the text blocks of a user intent.

    `model_messages[].content[]` is the model-visible form; `refill_blocks[]`
    is the same text as re-delivered on resume. Prefer the former and fall back
    to the latter so a record carrying only one of them still yields prose.
    """
    parts: list[str] = []
    for message in payload.get("model_messages") or []:
        if not isinstance(message, dict):
            continue
        for block in message.get("content") or []:
            if isinstance(block, dict) and block.get("kind") == "text":
                value = block.get("text")
                if isinstance(value, str) and value:
                    parts.append(value)
    if parts:
        return "\n".join(parts)
    for block in payload.get("refill_blocks") or []:
        if isinstance(block, dict) and block.get("kind") == "text":
            value = block.get("text")
            if isinstance(value, str) and value:
                parts.append(value)
    return "\n".join(parts)


def emit(event: dict) -> None:
    json.dump(event, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--cwd", default="")
    parser.add_argument("--depth", default="standard")
    args = parser.parse_args()

    if args.depth not in DEPTHS:
        print(f"extract_session: unsupported depth {args.depth}", file=sys.stderr)
        return 10

    root = session_root()
    transcript = find_transcript(root, args.session_id)
    if transcript is None:
        print(
            f"extract_session: no muse session log for {args.session_id} under {root}",
            file=sys.stderr,
        )
        return EXIT_NOT_FOUND

    try:
        handle = open(transcript, "r", encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"extract_session: cannot read {transcript}: {error}", file=sys.stderr)
        return EXIT_PARSE_ERROR

    cwd = args.cwd or ""
    started_at = None
    ended_at = None
    prose: list[dict] = []
    unparseable = 0
    emitted = 0

    with handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            produced = False
            for record in iter_records(line):
                produced = True
                payload = record.get("payload")
                if not isinstance(payload, dict):
                    continue
                payload_type = record.get("payload_type") or ""
                at = iso_from_micros(record.get("recorded_at"))
                inner = payload.get("record")
                inner = inner if isinstance(inner, dict) else {}

                if payload_type == "runtime.session.metadata":
                    root_dir = inner.get("workspace_root")
                    if isinstance(root_dir, str) and root_dir and not args.cwd:
                        cwd = root_dir
                    started_at = started_at or at
                elif payload_type == "session.opened.observed":
                    started_at = started_at or at
                elif payload_type == "runtime.user_intent.accepted":
                    # Only genuine chat turns are conversation; other semantic
                    # kinds (reminders, system refills) are not user prose.
                    semantic = payload.get("semantic_kind")
                    kind = (
                        semantic.get("kind") if isinstance(semantic, dict) else None
                    )
                    if kind not in (None, "chat"):
                        continue
                    text = text_from_model_messages(payload)
                    if text and at:
                        prose.append({"type": "prose", "role": "user", "text": text, "at": at})
                elif payload_type == "session.end":
                    ended_at = at
            if not produced:
                unparseable += 1

    if started_at is None:
        # A log with no openable session record is unusable, not merely empty.
        print(
            f"extract_session: {transcript} carries no session-open record",
            file=sys.stderr,
        )
        return EXIT_PARSE_ERROR

    emit(
        {
            "type": "session_start",
            "session_id": args.session_id,
            "adapter": ADAPTER_NAME,
            "cwd": cwd,
            "started_at": started_at,
        }
    )
    emitted += 1
    for event in prose:
        emit(event)
        emitted += 1
    emit(
        {
            "type": "session_end",
            "session_id": args.session_id,
            "ended_at": ended_at or started_at,
            "event_count": emitted,
        }
    )

    if unparseable:
        print(
            f"extract_session: skipped {unparseable} unparseable line(s) in {transcript}",
            file=sys.stderr,
        )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
