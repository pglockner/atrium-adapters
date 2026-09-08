#!/usr/bin/env python3
"""Goose session extractor — emits canonical JSONL events.

Reads Goose's SQLite session store (see resolve_session_db.sh for the path):
  - sessions table  (metadata: id, name, working_dir, created_at, updated_at)
  - messages table  (role, content_json, timestamp, metadata_json)

Goose 1.48+ nests tool call/result payloads under a `.value` envelope
({"status": ..., "value": {...}}); 1.47 and earlier put the fields at the top
level. Both shapes are handled.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone

# Tool results are large and mostly shell/developer output. At deep depth we
# emit a result only for those tools, and only when it can be attributed to a
# request, with the text capped.
RESULT_TOOL_ALLOW_PREFIXES = ("developer", "shell", "str_replace", "text_editor")
RESULT_TEXT_CAP = 2000

def emit(event: dict) -> None:
    sys.stdout.write(json.dumps(event, ensure_ascii=False))
    sys.stdout.write("\n")

def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def _truncate_title(text: str, max_len: int = 120) -> str:
    text = text.strip()
    return text if len(text) <= max_len else text[: max_len - 3] + "..."

def _degraded(session_id: str, cwd: str, ts: str) -> None:
    print("[goose] transcript format not recognized; emitting metadata only", file=sys.stderr)
    emit({
        "type": "session_start",
        "session_id": session_id,
        "adapter": "goose",
        "cwd": cwd,
        "started_at": ts,
    })
    emit({
        "type": "session_end",
        "session_id": session_id,
        "ended_at": ts,
        "event_count": 2,
    })

def _normalize_ts(ts_str: str | None) -> str:
    if not ts_str:
        return iso_now()
    # SQLite times look like "2026-08-26 05:43:54"
    try:
        dt = datetime.strptime(ts_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
        return dt.replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return ts_str

def _unwrap(node):
    """Return the payload of a Goose tool envelope, tolerating both the
    1.48+ {"status","value":{...}} shape and the older flat shape."""
    if isinstance(node, dict) and "value" in node and isinstance(node["value"], dict):
        return node["value"]
    return node if isinstance(node, dict) else {}

def _is_user_visible(metadata_json: str | None) -> bool:
    """Goose tags each message with {userVisible, agentVisible, turnContext}.
    Turn-context injections and non-user-visible rows are noise for a
    transcript. Rows with no/blank metadata default to visible."""
    if not metadata_json:
        return True
    try:
        meta = json.loads(metadata_json)
    except Exception:
        return True
    if not isinstance(meta, dict):
        return True
    if meta.get("turnContext") is True:
        return False
    if meta.get("userVisible") is False:
        return False
    return True

def extract(db_path: str, session_id: str, cwd: str, depth: str) -> None:
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
    except Exception as exc:
        print(f"[goose] SQLite connection failure: {exc}", file=sys.stderr)
        _degraded(session_id, cwd, iso_now())
        return

    # 1. Fetch Session Info
    try:
        cursor.execute(
            "SELECT name, working_dir, created_at, updated_at FROM sessions WHERE id = ?",
            (session_id,)
        )
        session_row = cursor.fetchone()
    except Exception as exc:
        print(f"[goose] SQLite query failure: {exc}", file=sys.stderr)
        _degraded(session_id, cwd, iso_now())
        conn.close()
        return

    if not session_row:
        _degraded(session_id, cwd, iso_now())
        conn.close()
        return

    started_at = _normalize_ts(session_row["created_at"])
    ended_at = _normalize_ts(session_row["updated_at"])
    title = session_row["name"]
    resolved_cwd = session_row["working_dir"] or cwd

    session_start = {
        "type": "session_start",
        "session_id": session_id,
        "adapter": "goose",
        "cwd": resolved_cwd,
        "started_at": started_at,
    }
    if title:
        session_start["title"] = _truncate_title(str(title))

    # 2. Fetch Messages
    try:
        cursor.execute(
            "SELECT role, content_json, timestamp, metadata_json "
            "FROM messages WHERE session_id = ? ORDER BY created_timestamp ASC, id ASC",
            (session_id,)
        )
        messages = cursor.fetchall()
    except Exception as exc:
        print(f"[goose] SQLite messages query failure: {exc}", file=sys.stderr)
        messages = []

    visible = [m for m in messages if _is_user_visible(m["metadata_json"])]

    # If title still empty and messages exist, derive from first user msg
    if "title" not in session_start:
        for m in visible:
            if m["role"] == "user":
                try:
                    content = json.loads(m["content_json"])
                    text = "".join([part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"])
                    if text.strip():
                        session_start["title"] = _truncate_title(text.strip())
                        break
                except Exception:
                    continue

    emit(session_start)
    emitted = 1

    if depth == "quick":
        emit({
            "type": "session_end",
            "session_id": session_id,
            "ended_at": ended_at,
            "event_count": emitted + 1,
        })
        conn.close()
        return

    # Correlate tool responses back to the request that produced them. Goose
    # uses the same id on the toolRequest and its toolResponse.
    tool_by_id: dict[str, str] = {}

    for m in visible:
        ts = _normalize_ts(m["timestamp"])
        role = m["role"]

        try:
            content = json.loads(m["content_json"])
        except Exception:
            continue

        if not isinstance(content, list):
            continue

        for part in content:
            if not isinstance(part, dict):
                continue

            p_type = part.get("type")

            if p_type == "text":
                text = part.get("text", "")
                if "<turn-context>" in text:
                    continue
                if text.strip():
                    emit({
                        "type": "prose",
                        "role": "user" if role == "user" else "assistant",
                        "text": text.strip(),
                        "at": ts
                    })
                    emitted += 1

            elif p_type == "toolRequest":
                call = _unwrap(part.get("toolCall") or {})
                tool_name = call.get("name") or "unknown"
                args = call.get("arguments")
                if not isinstance(args, dict):
                    args = {} if args is None else {"value": args}

                call_id = part.get("id") or ""
                if call_id:
                    tool_by_id[call_id] = tool_name

                if depth == "standard":
                    args = {k: (v[:500] + "..." if isinstance(v, str) and len(v) > 500 else v) for k, v in args.items()}

                event = {
                    "type": "tool_use",
                    "tool": tool_name,
                    "input": args,
                    "at": ts,
                }
                if call_id:
                    event["id"] = call_id
                emit(event)
                emitted += 1

            elif p_type == "toolResponse" and depth == "deep":
                call_id = part.get("id") or ""
                tool_name = tool_by_id.get(call_id)
                # Only emit a result we can attribute to a request, for the
                # shell/developer-class tools whose output is worth keeping.
                if not call_id or not tool_name:
                    continue
                if not tool_name.startswith(RESULT_TOOL_ALLOW_PREFIXES):
                    continue

                result = _unwrap(part.get("toolResult") or {})
                is_error = bool(result.get("isError", False))
                res_content = result.get("content", [])
                text_parts = []
                if isinstance(res_content, list):
                    for sub in res_content:
                        if isinstance(sub, dict) and sub.get("type") == "text":
                            text_parts.append(sub.get("text", ""))
                text = "".join(text_parts)
                if len(text) > RESULT_TEXT_CAP:
                    text = text[:RESULT_TEXT_CAP] + "..."

                emit({
                    "type": "tool_result",
                    "tool": tool_name,
                    "tool_use_id": call_id,
                    "text": text,
                    "at": ts,
                    "is_error": is_error,
                })
                emitted += 1

    emit({
        "type": "session_end",
        "session_id": session_id,
        "ended_at": ended_at,
        "event_count": emitted + 1,
    })
    conn.close()

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--db", required=True)
    p.add_argument("--session-id", required=True)
    p.add_argument("--adapter", default="goose")
    p.add_argument("--cwd", default="")
    p.add_argument("--depth", default="standard", choices=["quick", "standard", "deep"])
    args = p.parse_args()

    try:
        extract(args.db, args.session_id, args.cwd, args.depth)
    except Exception as exc:
        print(f"extract_session: fatal error: {exc}", file=sys.stderr)
        _degraded(args.session_id, args.cwd, iso_now())
        return 0
    return 0

if __name__ == "__main__":
    sys.exit(main())
