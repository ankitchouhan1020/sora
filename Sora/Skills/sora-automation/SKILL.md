---
name: sora-automation
description: Coordinate bounded coding-agent work through Sora Spaces, tabs, panes, and agents.
---

# Sora Automation

Use Sora's bundled CLI from a Sora terminal. The invoking terminal's Space is
the capability boundary; IDs from other Spaces are rejected.

## Delegate work

1. Inspect existing layout: `sora tab list` and `sora pane list`.
2. Create layout explicitly when needed:

   ```sh
   sora tab create --pinned --name worker
   # or: sora pane split --right
   ```

3. Start the agent in an available terminal returned above:

   ```sh
   sora agent start worker --kind pi --pane PANE_ID
   ```

   `agent start` never creates, moves, pins, focuses, or closes layout. It sends
   structured argv and waits until Sora recognizes the provider.
4. Prompt the running agent directly:

   ```sh
   sora agent prompt worker --text "Change only the parser, run its focused check, and report changed files."
   ```

   Prompts do not pass through a shell. Multiline text uses bracketed paste.
5. Wait and inspect without stealing focus:

   ```sh
   sora agent wait worker --state idle,done,blocked --timeout 1800000
   sora agent read worker --lines 160
   ```

6. Independently review the worker's diff and verification.

## Boundaries

- Use `agent prompt` for conversation. `pane send` is raw terminal I/O, not an
  agent shortcut.
- Treat `blocked` as a user handoff. Never answer permission, trust, credential,
  login, secret, or destructive-action prompts for the user.
- Never infer lifecycle from terminal text. Without a provider integration,
  state may remain `unknown`; read output and report that limitation.
- Do not focus panes, alter pinned/temporary state, close layout, remove Spaces,
  discard changes, commit, or push unless explicitly authorized.
