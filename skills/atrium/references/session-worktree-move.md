# Moving this conversation into a worktree

Use this when a conversation started in the main checkout and the user asks to execute its work in isolation. You keep the conversation, pane, history, launch settings, and existing task association. You do not need to launch another agent or write a handoff.

```bash
"$ATRIUM_CLI_PATH" agent move --help
"$ATRIUM_CLI_PATH" agent move --new-worktree feature/my-work
```

The command schedules preparation and returns immediately. **Finish your current turn without starting more repository work.** atrium waits for the turn to finish, moves the conversation, refreshes its working directory and context, then sends a continuation prompt. Do not poll waiting for completion inside that turn: the move is waiting for you to finish.

- `--worktree <id>` selects an existing worktree project from `worktree list`. Unbound worktrees must be adopted first.
- `--base <ref>` chooses the starting commit for a new branch; the default is the source checkout's current `HEAD`.
- Repeat `--include <repository-relative-file>` to copy selected uncommitted files. Files in the source checkout remain intact. Destination conflicts refuse the move; submodule changes must be committed or transferred separately.
- `--no-continue` moves the session and waits for the next user message.
- `--status` reads the last move's actual result. `--cancel` cancels before the conversation starts switching. A prepared worktree stays available.
- `--pane <id>` targets another session when the user has asked you to move it. Without it, the CLI uses `ATRIUM_PANE_ID`.

Claude and Codex chat sessions can move between checkouts of the same repository on the same machine. Pause active Codex goals, stop Claude goals or scheduled loops, and finish or stop the session's background agents and commands first. Standalone workspace commands keep running in their original project.

After moving, refresh applicable project instructions and check absolute paths from earlier messages before editing. The working directory may retain its relative subdirectory when that directory exists in the destination. A worktree setup failure leaves the original conversation available and reports the prepared path for recovery.
