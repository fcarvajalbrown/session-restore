# Roadmap

The goal: shut down for real instead of hibernating, and get the work context back on the next boot. Vision and scope are in [docs/PRD.md](docs/PRD.md).

## Open items

- Phase 1: design of the agent adapter interface needs a decision (ADR) before code.
- Phase 2: Blocked. Explorer crashed after the Win+X entries were added (see Phase 2). The entries are out of the installer until the cause is known.
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

Status: Blocked

- Close the 3-minute blind spot: take a fresh snapshot at the moment of shutdown or restart.
- Wanted: a "Save and shut down" item inside the Start menu Power flyout, next to Shut down and Restart.
- Done: `Save-AndShutdown.ps1` (snapshot, then shut down, or restart with `-Restart`), and two entries in the native Win+X menu (right-click Start), next to "Shut down or sign out": "Save and shut down" and "Save and restart". `Uninstall.ps1` removes them.
- Blocked: after the two shortcuts were written and Explorer was force-restarted, explorer.exe crashed twice at the same offset (0x458aa, access violation 0xc0000005 and 0xc000041d) and the desktop stayed white. Moving the two shortcuts out and starting Explorer brought the shell back. Both were done at once, so it is not known whether the shortcuts or the forced restart caused the crash. `Install.ps1` no longer adds the entries. Never force-restart Explorer on the user's machine to test this; find the cause offline or in a VM.

Findings:
- The registry and Group Policy only show or hide the built-in entries (Sleep, Hibernate, Lock). No documented key adds a custom entry to the native Power flyout.
- Open-Shell (open source Start menu replacement) was tried and dropped: it replaces the Windows Start menu. It supports custom commands inside its shutdown submenu only in its Classic and Classic two-column styles (`MenuItems1` / `MenuItems2`, item `ShutdownBoxItem.Items`). Its default Windows 7 style has a fixed shutdown flyout; a custom item there can only go in the main menu columns.
- Windows sends `WM_QUERYENDSESSION` to every top-level window when a shutdown or restart starts. A hidden listener window can take a snapshot at that moment, which makes the native Shut down and Restart entries save first without changing the menu.
- A scheduled task on System event 1074 (shutdown initiated) is reported as unreliable: it fires too late or fails under the SYSTEM account.
- The Win+X menu is native and takes custom shortcuts on Windows 10, as `.lnk` files in `%LOCALAPPDATA%\Microsoft\Windows\WinX\Group1..3`. Each needs a hash stamped into its property store (key `{FB8D2D7B-90D1-4E34-BF60-6EAC09922BBF}`, 2): `HashData` over the lowercased generalized target path, arguments and a fixed salt, as published in hashlnk (MIT). `WinXShortcut.ps1` reimplements it; its output matches the stamped hash on every built-in file-target Win+X shortcut. Reports say it no longer works on newer Windows 11 builds.
- Last resort: a pinned "Save and shut down" Start and taskbar shortcut.

## Phase 3: more apps and windows

Status: Not Started

- Windows Terminal: tabs, their shells and folders.
- JetBrains IDEs and their open projects.
- File Explorer windows and their folders.
- Browser windows, as far as each browser exposes them without an extension.
