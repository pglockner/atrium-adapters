-- Sanitized Goose 1.49.0 session fixture. Synthetic data only.
-- Exercises: the .value tool envelope (1.48+), request/response id correlation,
-- the shell/developer result allowlist, and metadata_json turn-context filtering.
CREATE TABLE sessions (
  id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',
  user_set_name BOOLEAN DEFAULT FALSE, session_type TEXT NOT NULL DEFAULT 'user',
  working_dir TEXT NOT NULL, created_at TIMESTAMP, updated_at TIMESTAMP,
  provider_name TEXT, model_config_json TEXT, goose_mode TEXT NOT NULL DEFAULT 'auto',
  parent_session_id TEXT
);
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT, message_id TEXT, session_id TEXT NOT NULL,
  role TEXT NOT NULL, content_json TEXT NOT NULL, created_timestamp INTEGER NOT NULL,
  timestamp TIMESTAMP, tokens INTEGER, metadata_json TEXT
);

INSERT INTO sessions (id, name, working_dir, created_at, updated_at, provider_name, model_config_json)
VALUES ('20260908_fix', 'fixture session', '/work/proj',
        '2026-09-08 10:00:00', '2026-09-08 10:05:00',
        'openrouter', '{"model_name":"qwen/qwen3-coder"}');

-- real user turn (visible)
INSERT INTO messages (session_id, role, content_json, created_timestamp, timestamp, metadata_json)
VALUES ('20260908_fix', 'user',
  '[{"type":"text","text":"list the files then load a recipe"}]',
  1000, '2026-09-08 10:00:01', '{"userVisible":true,"agentVisible":true}');

-- turn-context injection (must be filtered out)
INSERT INTO messages (session_id, role, content_json, created_timestamp, timestamp, metadata_json)
VALUES ('20260908_fix', 'user',
  '[{"type":"text","text":"<turn-context>cwd=/work/proj</turn-context>"}]',
  1001, '2026-09-08 10:00:01', '{"userVisible":false,"agentVisible":true,"turnContext":true}');

-- assistant: two tool requests (1.49 .value envelope) — shell (allowlisted) + load (not)
INSERT INTO messages (session_id, role, content_json, created_timestamp, timestamp, metadata_json)
VALUES ('20260908_fix', 'assistant',
  '[{"type":"toolRequest","id":"call_shell_1","toolCall":{"status":"success","value":{"name":"shell","arguments":{"command":"ls -1"}}}},{"type":"toolRequest","id":"call_load_1","toolCall":{"status":"success","value":{"name":"load","arguments":{"source":"recipe-x"}}}}]',
  1002, '2026-09-08 10:00:02', '{"userVisible":true,"agentVisible":true}');

-- user: matching tool responses (1.49 .value envelope)
INSERT INTO messages (session_id, role, content_json, created_timestamp, timestamp, metadata_json)
VALUES ('20260908_fix', 'user',
  '[{"type":"toolResponse","id":"call_shell_1","toolResult":{"status":"success","value":{"resultType":"complete","content":[{"type":"text","text":"README.md\nsrc\n"}],"isError":false}}},{"type":"toolResponse","id":"call_load_1","toolResult":{"status":"success","value":{"content":[{"type":"text","text":"loaded recipe-x"}],"isError":false}}}]',
  1003, '2026-09-08 10:00:03', '{"userVisible":true,"agentVisible":true}');

-- assistant closing prose
INSERT INTO messages (session_id, role, content_json, created_timestamp, timestamp, metadata_json)
VALUES ('20260908_fix', 'assistant',
  '[{"type":"text","text":"Listed 2 entries and loaded the recipe."}]',
  1004, '2026-09-08 10:00:04', '{"userVisible":true,"agentVisible":true}');
