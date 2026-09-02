#!/usr/bin/env python3
"""List recent, directly-resumable Muse Code sessions for one workspace.

Emits ``{"sessions": [{id, name, cwd, lastActive, sourcePath}, ...]}`` on
stdout, newest first. Never raises: an unreadable or half-written log yields
one skipped session, not a failed method.

Session identity and the fields we need all appear in the FIRST few records of
``session.jsonl``, so each file is read head-first and abandoned as soon as it
has answered — a session log grows to megabytes and nothing here needs the tail.

Two framing details this has to respect:

* Some records are wrapped in a ``session_permission_transaction`` envelope
  whose real records live in ``children[].record_json`` as JSON *strings*.
  Reading only the outer object misses the metadata record entirely.
* ``runtime.session`` / ``agent_tree_initialized`` carries ``root_session_id``.
  When that differs from the session's own id the log belongs to a SUBAGENT
  child, which the method contract forbids emitting — resuming one would
  reattach to a child transcript rather than a conversation the user had.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

# Enough to cover metadata + session_opened + the name record with room to
# spare, while refusing to walk a multi-megabyte transcript.
MAX_RECORDS_SCANNED = 400
MAX_SESSIONS = 20


def session_root() -> str:
    override = os.environ.get("ATRIUM_TEST_MUSE_SESSION_ROOT")
    if override:
        return override
    # Mirrors muse's own resolution: XDG data home, else ~/.local/share.
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(data_home, "muse", "sessions")


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
            if not isinstance(child, dict):
                continue
            payload = child.get("record_json")
            if not isinstance(payload, str):
                continue
            try:
                inner = json.loads(payload)
            except ValueError:
                continue
            if isinstance(inner, dict):
                yield inner
        return
    yield outer


def read_session(directory: str, session_id: str):
    """Return a session dict, or None when the log is unusable or a child."""
    path = os.path.join(directory, "session.jsonl")
    try:
        handle = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        return None

    cwd = None
    name = None
    with handle:
        for index, line in enumerate(handle):
            if index >= MAX_RECORDS_SCANNED:
                break
            line = line.strip()
            if not line:
                continue
            for record in iter_records(line):
                payload = record.get("payload")
                if not isinstance(payload, dict):
                    continue
                payload_type = record.get("payload_type") or ""
                inner = payload.get("record")
                inner = inner if isinstance(inner, dict) else {}

                if payload_type == "runtime.session.metadata":
                    root = inner.get("workspace_root")
                    if isinstance(root, str) and root:
                        cwd = root
                elif payload_type == "session.name.changed":
                    candidate = payload.get("new_name")
                    if isinstance(candidate, str) and candidate:
                        name = candidate
                elif payload.get("kind") == "agent_tree_initialized":
                    root_session = inner.get("root_session_id")
                    if isinstance(root_session, str) and root_session != session_id:
                        # A subagent's own log — not directly resumable.
                        return None
            if cwd is not None and name is not None:
                break

    if not cwd:
        return None

    try:
        modified = os.path.getmtime(path)
    except OSError:
        return None

    return {
        "id": session_id,
        "name": name,
        "cwd": cwd,
        "lastActive": datetime.fromtimestamp(modified, timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "sourcePath": path,
        "_mtime": modified,
    }


def candidate_dirs(root: str):
    """Yield (dir, session_id) newest-partition-first.

    The tree is <year>/<month>/<day>/<uuid>, so a reverse lexicographic walk of
    the zero-padded partitions is already newest-first and lets us stop early
    instead of stat-ing every session the user has ever run.
    """
    for year in sorted(safe_listdir(root), reverse=True):
        year_path = os.path.join(root, year)
        for month in sorted(safe_listdir(year_path), reverse=True):
            month_path = os.path.join(year_path, month)
            for day in sorted(safe_listdir(month_path), reverse=True):
                day_path = os.path.join(month_path, day)
                for session_id in safe_listdir(day_path):
                    yield os.path.join(day_path, session_id), session_id


def safe_listdir(path: str):
    try:
        return [entry for entry in os.listdir(path) if not entry.startswith(".")]
    except OSError:
        return []


def main() -> int:
    target_cwd = sys.argv[1] if len(sys.argv) > 1 else ""
    root = session_root()
    if not os.path.isdir(root):
        json.dump({"sessions": []}, sys.stdout)
        sys.stdout.write("\n")
        return 0

    # macOS hands muse a /private-prefixed realpath for /tmp and friends, so a
    # raw string compare would drop every session started in one. Compare
    # resolved paths, keeping the caller's spelling in the output.
    try:
        target_real = os.path.realpath(target_cwd) if target_cwd else ""
    except OSError:
        target_real = target_cwd

    found = []
    scanned = 0
    for directory, session_id in candidate_dirs(root):
        # Bounded: partitions are newest-first, so this is a recency window,
        # not an arbitrary cutoff mid-workspace.
        if scanned >= MAX_SESSIONS * 10:
            break
        scanned += 1
        session = read_session(directory, session_id)
        if session is None:
            continue
        if target_real:
            try:
                if os.path.realpath(session["cwd"]) != target_real:
                    continue
            except OSError:
                if session["cwd"] != target_cwd:
                    continue
        found.append(session)
        if len(found) >= MAX_SESSIONS * 2:
            break

    found.sort(key=lambda entry: entry["_mtime"], reverse=True)
    for session in found:
        session.pop("_mtime", None)

    json.dump({"sessions": found[:MAX_SESSIONS]}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 - a listing failure must not break the pane
        json.dump({"sessions": []}, sys.stdout)
        sys.stdout.write("\n")
        sys.exit(0)
