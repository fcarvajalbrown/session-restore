Get-ScheduledTask -TaskName 'SessionRestore*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
'SessionRestore tasks removed. State stays in ' + (Join-Path $env:LOCALAPPDATA 'SessionRestore')
