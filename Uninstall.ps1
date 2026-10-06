. (Join-Path $PSScriptRoot 'Common.ps1')
Get-ScheduledTask -TaskName 'SessionRestore*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
foreach ($profilePath in Get-ShellProfilePaths) {
    if (-not (Test-Path $profilePath)) { continue }
    $kept = @(Get-Content -LiteralPath $profilePath | Where-Object { $_ -ne $ProfileHookLine })
    Set-Content -LiteralPath $profilePath -Value $kept -Encoding UTF8
}
'SessionRestore tasks and profile line removed. State stays in ' + $StateDir
