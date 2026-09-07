# Moving this conversation into a worktree

Use this when a conversation started in the main checkout and the user asks to execute its work in isolation. You keep the conversation, pane, history, launch settings, and existing task association. You do not need to launch another agent or write a handoff.

```bash
"$ATRIUM_CLI_PATH" agent move --help
"$ATRIUM_CLI_PATH" agent move --new-worktree feature/my-work
```

The command schedules preparation and returns immediately. **Finish your current turn without starting more repository work.** If the agent was active when the move was requested, atrium waits for the turn to finish, moves the conversation, updates its working directory, then sends a continuation nudge. An idle conversation stays idle and receives only the move notice. Do not poll waiting for completion inside an active turn: the move is waiting for you to finish.

- `--worktree <id>` selects an existing worktree project from `worktree list`. Unbound worktrees must be adopted first.
- `--base <ref>` chooses the starting commit for a new branch; the default is the source checkout's current `HEAD`.
- No uncommitted changes are copied by default. Repeat `--include <repository-relative-file>` to opt in for selected files. Files in the source checkout remain intact. Destination conflicts refuse the move; submodule changes must be committed or transferred separately.
- `--no-continue` leaves the conversation idle after moving, even if the agent was active.
- `--status` reads the last move's actual result. `--cancel` cancels before the conversation starts switching. A prepared worktree stays available.
- `--pane <id>` targets another session when the user has asked you to move it. Without it, the CLI uses `ATRIUM_PANE_ID`.

Chat sessions from every tool can move between checkouts of the same repository on the same machine. Where supported, atrium resumes or forks the native conversation. Tools that cannot change directories on resume start a fresh engine session in the same pane and receive instructions to read the preserved conversation before continuing. No additional agent or terminal pane is created.

Pause or stop active goals and scheduled loops, and finish or stop the session's background agents and commands first. Standalone workspace commands keep running in their original project. Each move has a status card at its place in the conversation. If you are viewing the moving pane, focus follows it and returns to the source if the move fails.

After moving, use the destination as the current directory. Earlier absolute paths may point to the source checkout. Existing context remains useful; follow any instructions specific to the destination rather than rereading unchanged instructions by default. The working directory may retain its relative subdirectory when that directory exists in the destination. A worktree setup failure leaves the original conversation available and reports the prepared path for recovery.
