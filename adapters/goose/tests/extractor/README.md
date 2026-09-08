# goose extractor fixture

`fixture.sql` builds a sanitized Goose 1.49.0 `sessions.db` (synthetic data —
no real transcripts). `assert.sh` builds it in a temp dir, runs
`extract_session.py --depth deep` against it, and checks the review-point-5
behaviours:

- the `{"status","value":{…}}` tool envelope introduced in Goose 1.48 is
  unwrapped (real tool name + input, not `unknown` / `{}`)
- a `toolResponse` is correlated to its `toolRequest` by the shared `id`
- `tool_result` events are emitted only for the shell/developer allowlist
  (`load` in the fixture is dropped)
- `messages.metadata_json` (`userVisible` / `turnContext`) filters
  turn-context injections instead of a brittle string match

Run: `bash adapters/goose/tests/extractor/assert.sh`
