param(
    [switch]$Restart,
    [switch]$DryRun,
    [string]$Uri
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if ($Uri) {
    switch -Regex ($Uri.TrimEnd('/')) {
        "^${UriScheme}:shutdown$" { $Restart = $false }
        "^${UriScheme}:restart$" { $Restart = $true }
        default { Write-Log "ignored unknown uri $Uri"; exit 1 }
    }
}

& (Join-Path $PSScriptRoot 'Save-Snapshot.ps1')
$action = if ($Restart) { 'restart' } else { 'shut down' }
Write-Log "snapshot saved before $action"
if ($DryRun) { "snapshot saved; would $action"; exit 0 }

$shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
$mode = if ($Restart) { '/r' } else { '/s' }
& $shutdown $mode /t 0
