# session-restore

Reopens the editors and Claude Code sessions that were open before a restart, and shows a popup listing every session with its folder and a copyable resume line.

## What it does

- `Save-Snapshot.ps1` runs every 3 minutes, hidden. It records whether VS Code and VSCodium are running and every interactive Claude session from `~/.claude/sessions`: id, name, folder, whether it ran in an editor terminal, in a standalone PowerShell or in the editor's Claude panel, and the exact `claude.exe` it used.
- `Restore-Session.ps1` runs 30 seconds after logon, hidden. It acts only when the snapshot comes from an earlier Windows logon, so waking from hibernation or sleep (same logon) does nothing. It reopens VS Code and VSCodium if they are not running, opens each session's folder in the editor it ran in, and opens one PowerShell window per session running `claude --resume <id>` in its folder. Then it shows the popup. With no snapshot it shows nothing.
- Sessions are listed but not reopened when their folder is missing (an unplugged drive) or when they ran in the editor's Claude panel, which cannot be started from outside.
- State and log: `%LOCALAPPDATA%\SessionRestore` (`snapshot.json`, `last-restored.json`, `restore.log`).

## Install and remove

```
powershell -ExecutionPolicy Bypass -File Install.ps1
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

`Install.ps1` registers two scheduled tasks for the current user, `SessionRestore Snapshot` and `SessionRestore Restore`, no admin needed. Both start through `Hidden.vbs`, so no console window flashes.

## Check without launching anything

```
powershell -ExecutionPolicy Bypass -File Restore-Session.ps1 -DryRun -NoPopup
```

prints what a restore would do from the current snapshot.

## Limits

- A session that lived in a VS Code terminal comes back in a separate PowerShell window next to the reopened editor, not inside the editor's terminal.
- A restart within 3 minutes of opening a session can miss it, since the snapshot is up to 3 minutes old.

## Reminders

```
powershell -ExecutionPolicy Bypass -File Add-Reminder.ps1 -At "2026-10-06 20:00" -TextFile note.txt -Name "My reminder"
```

shows the text of `note.txt` in a popup at that time, or at the next start if the computer was off. The task deletes itself a day after it expires.
