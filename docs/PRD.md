# session-restore: product requirements

## Problem

Hibernating is a habit that sticks because shutting down costs the work context. After a real shutdown you no longer know which editors, folders and terminal sessions were open, or which coding-agent conversation you were in the middle of. Sleep is unreliable on some laptops, and a machine that never shuts down drifts: updates wait, memory leaks pile up, drivers stay in odd states.

The disk cost is concrete. On Felipe's machine (15.8 GB RAM, Windows 10, auto-managed pagefile) after 12 days of hibernating without a restart, `pagefile.sys` had grown to 45.7 GB (peak use 14.3 GB) and `hiberfil.sys` was 6.8 GB. Windows grows an auto-managed pagefile under memory pressure and drops those extensions on restart, so regular real restarts are what keep that space free. The pagefile must stay auto-managed: a fixed 1,600 MB pagefile caused the editor crash storms fixed in July.

## Goal

Make a full shutdown or restart cost nothing in context. Turn the machine off, turn it on, and the work you had open comes back, or at least a list of it with the exact lines to resume it.

## Users

Anyone on Windows who keeps several editors and agent CLI sessions open across projects and hibernates to avoid losing track of them.

## How it works

- **Snapshot.** A hidden scheduled task records what is open: editors and their folders, terminal shells, and agent CLI sessions with their ids and working folders. The snapshot is tagged with the Windows logon id.
- **Restore.** At logon, a hidden task compares logon ids. A new logon means a real boot or sign-in, so it reopens what the snapshot lists. Resuming from hibernation or sleep keeps the logon id, so nothing happens.
- **Report.** A popup lists every session with its folder and a copyable resume line, including the ones it could not reopen. When there is nothing to restore it shows nothing.

## Scope

In scope:
- Windows 10 and 11, current user, no admin rights.
- Editors: VS Code, VSCodium.
- Shells: Windows PowerShell, PowerShell 7.
- Agent CLIs through one adapter each. Claude Code is the first adapter.
- A way to save a fresh snapshot at the moment of shutdown.

Out of scope for now:
- Restoring unsaved editor buffers or terminal scrollback.
- Linux and macOS.

## Constraints

- PowerShell and built-in Windows components only, no installed runtime.
- Runs hidden: no console flashes at logon or during snapshots.
- No comments in code; names carry the meaning.
