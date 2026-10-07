. (Join-Path $PSScriptRoot 'Common.ps1')
Get-ScheduledTask -TaskName 'SessionRestore*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ListenerPath)) -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath $ListenerPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $UriKey -Recurse -Force -ErrorAction SilentlyContinue
foreach ($profilePath in Get-ShellProfilePaths) {
    if (-not (Test-Path $profilePath)) { continue }
    $kept = @(Get-Content -LiteralPath $profilePath | Where-Object { $_ -ne $ProfileHookLine })
    Set-Content -LiteralPath $profilePath -Value $kept -Encoding UTF8
}
foreach ($entry in $PowerMenuEntries) {
    Remove-Item -LiteralPath (Join-Path $WinXGroupDir $entry.File) -Force -ErrorAction SilentlyContinue
}
'SessionRestore tasks, profile line and Win+X entries removed. State stays in ' + $StateDir
