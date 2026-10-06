# session-restore

Shut down your Windows PC for real instead of hibernating, and get your work back on the next boot.

Hibernating is easy to fall into because a shutdown throws away what you were doing: which editors were open, on which folders, and which coding-agent sessions were half way through something. session-restore keeps a snapshot of that and reopens it after a restart. It also shows a popup with every session, its folder and a line you can copy to resume it. Resuming from hibernation or sleep does nothing.

Today it handles VS Code, VSCodium, PowerShell and Claude Code. Other agent CLIs are planned through adapters, see [ROADMAP.md](ROADMAP.md).

## What it does

- `Save-Snapshot.ps1` runs every 3 minutes, hidden. It records whether VS Code and VSCodium are running and every interactive Claude session from `~/.claude/sessions`: id, name, folder, whether it ran in an editor terminal, in a standalone PowerShell or in the editor's Claude panel, and the exact `claude.exe` it used.
- `Restore-Session.ps1` runs 30 seconds after logon, hidden. It acts only when the snapshot comes from an earlier Windows logon, so waking from hibernation or sleep (same logon) does nothing. It reopens VS Code and VSCodium if they are not running, opens each session's folder in the editor it ran in, and opens one PowerShell window per session running `claude --resume <id>` in its folder. Then it shows the popup. With no snapshot it shows nothing.
- Plain PowerShell windows come back too, each in the folder it was in. Windows doesn't expose which folder a PowerShell window is in, so `Install.ps1` adds one line to your PowerShell profile that loads `Track-ShellFolder.ps1`. It notes the folder each time the prompt shows. Terminals inside VS Code or VSCodium are skipped, because the editor brings its own back.
- Sessions are listed but not reopened when their folder is missing (an unplugged drive) or when they ran in the editor's Claude panel, which cannot be started from outside.
- State and log: `%LOCALAPPDATA%\SessionRestore` (`snapshot.json`, `last-restored.json`, `restore.log`).

## Install and remove

```
powershell -ExecutionPolicy Bypass -File Install.ps1
powershell -ExecutionPolicy Bypass -File Uninstall.ps1
```

`Install.ps1` registers two scheduled tasks for the current user, `SessionRestore Snapshot` and `SessionRestore Restore`, no admin needed. Both start through `Hidden.vbs`, so no console window flashes. It also adds the folder-tracking line to the Windows PowerShell profile, and to the PowerShell 7 profile when `pwsh` is installed. `Uninstall.ps1` removes the tasks and that line.

## Save and shut down

Right-click the Start button (or press Win+X). Next to "Shut down or sign out" there are two extra entries, "Save and shut down" and "Save and restart". They take a fresh snapshot and then power off, so nothing opened in the last 3 minutes is missed. `Save-AndShutdown.ps1 [-Restart]` does the same from a terminal.

Windows only accepts a Win+X shortcut when it carries a hash of its target. `WinXShortcut.ps1` computes it the same way as [hashlnk](https://github.com/riverar/hashlnk). The entries show up after Explorer restarts or at the next sign-in. Works on Windows 10; newer Windows 11 builds reportedly reject custom Win+X entries.

## Check without launching anything

```
powershell -ExecutionPolicy Bypass -File Restore-Session.ps1 -DryRun -NoPopup
```

prints what a restore would do from the current snapshot.

## Limits

- A session that lived in a VS Code terminal comes back in a separate PowerShell window next to the reopened editor, not inside the editor's terminal.
- A PowerShell window opened before the install, or one started with `-NoProfile`, has no folder recorded and is not reopened.
- A restart within 3 minutes of opening a session can miss it, since the snapshot is up to 3 minutes old.

## Reminders

```
powershell -ExecutionPolicy Bypass -File Add-Reminder.ps1 -At "2026-10-06 20:00" -TextFile note.txt -Name "My reminder"
```

shows the text of `note.txt` in a popup at that time, or at the next start if the computer was off. The task deletes itself a day after it expires.

## Licence

MIT, see [LICENSE](LICENSE).
