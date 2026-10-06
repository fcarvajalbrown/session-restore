# Roadmap

The goal: shut down for real instead of hibernating, and get the work context back on the next boot. Vision and scope are in [docs/PRD.md](docs/PRD.md).

## Open items

- Phase 1: design of the agent adapter interface needs a decision (ADR) before code.
- Phase 2: pick the route for saving at shutdown. The registry cannot add an entry to the native Power flyout (see Phase 2 findings).
- No ADRs written yet. Each phase below gets its ADR once its design is decided.

## Phase 0: Windows restore for one agent CLI

Status: Done

- Snapshot every 3 minutes, hidden, tagged with the logon id.
- Restore at logon only when the logon id changed, so hibernate and sleep resume do nothing.
- Reopens VS Code and VSCodium, each session's folder in its editor, and one PowerShell window per Claude Code session running `claude --resume <id>`.
- Plain PowerShell windows outside the editors reopen in the folder they were in, tracked through a profile line.
- Popup listing every session, with folder and resume line. Silent when there is nothing to restore.
- One-time reminder popups (`Add-Reminder.ps1`).

## Phase 1: pluggable agent CLIs

Status: Not Started

- Split the Claude Code logic out of `Save-Snapshot.ps1` and `Restore-Session.ps1` into an adapter: how to list live sessions, how to tell which process owns each, and the command that resumes one.
- The core only knows editors, shells, folders and adapters.
- Adapters after Claude Code: Codex CLI, Gemini CLI, Aider. Each one needs its session store and resume command checked against the real tool before it is written.
- Adapter discovery: drop a file in `adapters/` and it is picked up.

## Phase 2: save at shutdown

Status: Not Started

- Close the 3-minute blind spot: take a fresh snapshot at the moment of shutdown or restart.
- Wanted: a "Save and shut down" item inside the Start menu Power flyout, next to Shut down and Restart.

Findings:
- The registry and Group Policy only show or hide the built-in entries (Sleep, Hibernate, Lock). No documented key adds a custom entry to the native Power flyout.
- Open-Shell (open source Start menu replacement) supports custom commands inside its shutdown submenu, so a "Save and shut down" entry is possible there, at the cost of replacing the Windows Start menu.
- Windows sends `WM_QUERYENDSESSION` to every top-level window when a shutdown or restart starts. A hidden listener window can take a snapshot at that moment, which makes the native Shut down and Restart entries save first without changing the menu.
- A scheduled task on System event 1074 (shutdown initiated) is reported as unreliable: it fires too late or fails under the SYSTEM account.
- Last resort: a pinned "Save and shut down" Start and taskbar shortcut.

## Phase 3: more apps and windows

Status: Not Started

- Windows Terminal: tabs, their shells and folders.
- JetBrains IDEs and their open projects.
- File Explorer windows and their folders.
- Browser windows, as far as each browser exposes them without an extension.
