# Roadmap

The goal: shut down for real instead of hibernating, and get the work context back on the next boot. Vision and scope are in [docs/PRD.md](docs/PRD.md).

## Open items

- Phase 1: design of the agent adapter interface needs a decision (ADR) before code.
- Phase 2: find a way to put a "Save and shut down" entry in the Start menu Power flyout. Registry is the first lead; no documented method is known yet.
- No ADRs written yet. Each phase below gets its ADR once its design is decided.

## Phase 0: Windows restore for one agent CLI

Status: Done

- Snapshot every 3 minutes, hidden, tagged with the logon id.
- Restore at logon only when the logon id changed, so hibernate and sleep resume do nothing.
- Reopens VS Code and VSCodium, each session's folder in its editor, and one PowerShell window per Claude Code session running `claude --resume <id>`.
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
- Preferred entry point: a "Save and shut down" item inside the Start menu Power flyout, next to Shut down and Restart. Research how, starting with the registry.
- Fallbacks if the flyout cannot be changed: catch Windows' end-of-session signal so the existing Shut down and Restart entries save first, or a pinned Start and taskbar shortcut.

## Phase 3: more apps and windows

Status: Not Started

- Windows Terminal: tabs, their shells and folders.
- JetBrains IDEs and their open projects.
- File Explorer windows and their folders.
- Browser windows, as far as each browser exposes them without an extension.
