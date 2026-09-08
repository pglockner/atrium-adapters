import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "extract_session.sh"


class ExtractorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db = self.root / "state.db"
        with sqlite3.connect(self.db) as connection:
            connection.executescript("""
                CREATE TABLE sessions (id TEXT, source TEXT, cwd TEXT, title TEXT,
                    started_at REAL, ended_at REAL, archived INTEGER DEFAULT 0);
                CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT,
                    content TEXT, tool_calls TEXT, tool_call_id TEXT, tool_name TEXT,
                    timestamp REAL, active INTEGER DEFAULT 1);
                INSERT INTO sessions (id,source,cwd,title,started_at)
                    VALUES ('session-one', 'acp', '/project', 'Fix', 100);
                INSERT INTO messages (session_id,role,content,timestamp) VALUES
                    ('session-one','user','Fix the regression',101),
                    ('session-one','system','Do not expose system instructions',102),
                    ('another-session','assistant','Unrelated conversation',103),
                    ('session-one','assistant','Regression test passed.',105);
                INSERT INTO messages (session_id,role,content,timestamp,active)
                    VALUES ('session-one','user','Retracted instruction',104,0);
            """)
            connection.execute("INSERT INTO messages (session_id,role,tool_calls,timestamp) VALUES (?,?,?,?)",
                ("session-one", "assistant", json.dumps([{"id":"call-one", "function":
                 {"name":"terminal", "arguments":"{\"command\":\"test\"}"}}]), 103.1))
            connection.execute("INSERT INTO messages (session_id,role,content,tool_call_id,tool_name,timestamp) VALUES (?,?,?,?,?,?)",
                ("session-one", "tool", "passed", "call-one", "terminal", 103.2))

    def run_extract(self, depth="standard", session_id="session-one"):
        return subprocess.run([str(SCRIPT), "--session-id", session_id, "--depth", depth],
            env={**os.environ, "ATRIUM_TEST_TRANSCRIPT_ROOT": str(self.root)},
            text=True, capture_output=True, check=False)

    def test_standard_extracts_acp_session_and_preserves_database(self):
        before = hashlib.sha256(self.db.read_bytes()).hexdigest()
        result = self.run_extract()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(events[0]["session_id"], "session-one")
        self.assertEqual(events[-1]["event_count"], len(events))
        self.assertEqual([event["text"] for event in events if event["type"] == "prose"],
                         ["Fix the regression", "Regression test passed."])
        self.assertEqual(len([event for event in events if event["type"] == "tool_use"]), 1)
        self.assertNotIn('"type": "tool_result"', result.stdout)
        self.assertEqual(hashlib.sha256(self.db.read_bytes()).hexdigest(), before)

    def test_depths(self):
        quick = self.run_extract("quick")
        self.assertEqual(quick.returncode, 0, quick.stderr)
        self.assertEqual(len(quick.stdout.splitlines()), 2)
        deep = self.run_extract("deep")
        self.assertEqual(deep.returncode, 0, deep.stderr)
        self.assertIn('"tool_use_id": "call-one"', deep.stdout)

    def test_clean_absence_is_distinct_from_database_failure(self):
        self.assertEqual(self.run_extract(session_id="missing").returncode, 1)
        self.db.write_bytes(b"damaged database")
        result = self.run_extract()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.db.unlink()
        self.assertEqual(self.run_extract().returncode, 1)
        self.assertFalse(self.db.exists())

    def test_malformed_tool_data_never_becomes_an_empty_success(self):
        for value in ["{broken", '{"not":"a list"}', '[{"id":"call","function":null}]']:
            with self.subTest(value=value):
                with sqlite3.connect(self.db) as connection:
                    connection.execute("UPDATE messages SET tool_calls=? WHERE tool_calls IS NOT NULL", (value,))
                result = self.run_extract()
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_invalid_session_identity(self):
        self.assertEqual(self.run_extract(session_id="../escape").returncode, 10)

    def test_recent_sessions_includes_chat_and_keeps_workspace_scope(self):
        with sqlite3.connect(self.db) as connection:
            connection.executescript("""
                INSERT INTO sessions (id,source,cwd,started_at) VALUES
                    ('cli-one','cli','/project',99), ('other','acp','/elsewhere',106);
                INSERT INTO sessions (id,source,cwd,started_at,archived)
                    VALUES ('archived','acp','/project',107,1);
            """)
        result = subprocess.run([str(SCRIPT.parent / "list_recent_sessions.sh"), "/project"],
            env={**os.environ, "HERMES_HOME": str(self.root)}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row["id"] for row in json.loads(result.stdout)["sessions"]],
                         ["session-one", "cli-one"])


if __name__ == "__main__":
    unittest.main()
