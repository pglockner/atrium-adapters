#!/usr/bin/env python3
import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


def timestamp(value):
    return datetime.fromtimestamp(float(value), timezone.utc).isoformat()


def extract(connection, session_id, cwd, depth):
    connection.row_factory = sqlite3.Row
    connection.execute("BEGIN")
    session = connection.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
    if session is None:
        return None
    start = timestamp(session["started_at"])
    events = [{"type": "session_start", "session_id": session_id, "adapter": "hermes",
               "cwd": session["cwd"] or cwd, "started_at": start, "title": session["title"]}]
    last_at = start
    if depth != "quick":
        columns = {row[1] for row in connection.execute("PRAGMA table_info(messages)")}
        active = " AND COALESCE(active, 1) = 1" if "active" in columns else ""
        rows = connection.execute(
            "SELECT role, content, tool_calls, tool_call_id, tool_name, timestamp FROM messages "
            "WHERE session_id = ?" + active + " ORDER BY timestamp, id LIMIT 100001", (session_id,))
        output_bytes = 0
        tools = {}
        for index, row in enumerate(rows):
            if index >= 100000:
                raise ValueError("transcript exceeds message limit")
            at = timestamp(row["timestamp"])
            last_at = at
            text = row["content"] or ""
            if not isinstance(text, str):
                raise ValueError("unsupported message content")
            output_bytes += len(text.encode("utf-8")) + len(row["tool_calls"] or "")
            if output_bytes > 16 * 1024 * 1024:
                raise ValueError("transcript exceeds byte limit")
            if row["role"] in ("user", "assistant") and text.strip():
                events.append({"type": "prose", "role": row["role"], "text": text, "at": at})
            if row["role"] == "assistant" and row["tool_calls"]:
                calls = json.loads(row["tool_calls"])
                if not isinstance(calls, list):
                    raise ValueError("unsupported tool calls")
                for call in calls:
                    function = call["function"]
                    arguments = function.get("arguments", {})
                    if isinstance(arguments, str):
                        arguments = json.loads(arguments or "{}")
                    if not isinstance(arguments, dict) or not call["id"] or not function["name"]:
                        raise ValueError("unsupported tool call")
                    tools[call["id"]] = function["name"]
                    events.append({"type": "tool_use", "tool": function["name"], "input": arguments,
                                   "id": call["id"], "at": at})
            if depth == "deep" and row["role"] == "tool":
                tool_id = row["tool_call_id"]
                name = row["tool_name"] or tools.get(tool_id)
                if not tool_id or not name:
                    raise ValueError("tool result has no identity")
                events.append({"type": "tool_result", "tool": name, "tool_use_id": tool_id,
                               "text": text, "at": at})
    events.append({"type": "session_end", "session_id": session_id,
                   "ended_at": timestamp(session["ended_at"]) if session["ended_at"] else last_at,
                   "event_count": len(events) + 1})
    return events


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--cwd", default="")
    parser.add_argument("--depth", choices=("quick", "standard", "deep"), default="standard")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", args.session_id):
        return 10
    root = Path(os.environ.get("ATRIUM_TEST_TRANSCRIPT_ROOT") or
                os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
    source = root / "state.db"
    try:
        source.stat()
        with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True, timeout=1) as connection:
            events = extract(connection, args.session_id, args.cwd, args.depth)
    except FileNotFoundError:
        print("extract_session: source not found", file=sys.stderr)
        return 1
    except (OSError, sqlite3.Error) as error:
        print(f"extract_session: source read failed: {error}", file=sys.stderr)
        return 3
    except (ValueError, TypeError, KeyError, IndexError, AttributeError, OverflowError) as error:
        print(f"extract_session: unsupported transcript: {error}", file=sys.stderr)
        return 2
    if events is None:
        print("extract_session: session not found", file=sys.stderr)
        return 1
    for event in events:
        print(json.dumps(event, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
