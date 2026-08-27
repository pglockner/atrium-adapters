#!/usr/bin/env python3
"""Goose session extractor — emits canonical JSONL events.

Reads:
  - ~/.local/share/goose/sessions/sessions.db (SQLite database)
    - sessions table (metadata: id, name, created_at, updated_at)
    - messages table (role, content_json, timestamp)
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone

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
            "SELECT role, content_json, timestamp FROM messages WHERE session_id = ? ORDER BY id ASC",
            (session_id,)
        )
        messages = cursor.fetchall()
    except Exception as exc:
        print(f"[goose] SQLite messages query failure: {exc}", file=sys.stderr)
        messages = []

    # If title still empty and messages exist, derive from first user msg
    if "title" not in session_start:
        for m in messages:
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

    call_counter = 0
    for m in messages:
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
                # Skip turn-context prose if present
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
                call_counter += 1
                tool_call = part.get("toolCall") or {}
                tool_name = tool_call.get("name") or "unknown"
                args = tool_call.get("arguments") or {}
                
                if not isinstance(args, dict):
                    args = {"value": args}
                
                call_id = part.get("id") or f"call_{call_counter}"
                
                if depth == "standard":
                    # Truncate large tool inputs
                    args = {k: (v[:500] + "..." if isinstance(v, str) and len(v) > 500 else v) for k, v in args.items()}
                
                emit({
                    "type": "tool_use",
                    "tool": tool_name,
                    "input": args,
                    "at": ts,
                    "id": call_id
                })
                emitted += 1

            elif p_type == "toolResponse" and depth == "deep":
                tool_result = part.get("toolResult") or {}
                is_error = tool_result.get("isError", False)
                
                # Fetch text content from tool response blocks
                res_content = tool_result.get("content", [])
                text_parts = []
                if isinstance(res_content, list):
                    for sub in res_content:
                        if isinstance(sub, dict) and sub.get("type") == "text":
                            text_parts.append(sub.get("text", ""))
                text = "".join(text_parts)
                
                # We limit results to deep commands like shell/developer
                emit({
                    "type": "tool_result",
                    "tool": "developer__shell",
                    "tool_use_id": part.get("id") or "",
                    "text": text,
                    "at": ts,
                    "is_error": bool(is_error),
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
