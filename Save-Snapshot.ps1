$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$logonId = Get-LogonId

if (Test-Path $SnapshotPath) {
    $previous = Get-Content $SnapshotPath -Raw | ConvertFrom-Json
    $restoredFor = if (Test-Path $RestoredMarkerPath) { (Get-Content $RestoredMarkerPath -Raw).Trim() } else { '' }
    if ($previous.LogonId -ne $logonId -and $restoredFor -ne $logonId) {
        exit 0
    }
}

$processes = Get-CimInstance Win32_Process
$byId = @{}
foreach ($process in $processes) { $byId[[int]$process.ProcessId] = $process }

function Get-Ancestors([int]$Id) {
    $chain = @()
    for ($step = 0; $step -lt 8; $step++) {
        $process = $byId[$Id]
        if (-not $process) { break }
        $chain += $process
        $Id = [int]$process.ParentProcessId
    }
    $chain
}

$editors = @(foreach ($name in $EditorNames) {
    $running = $processes | Where-Object { $_.Name -eq $name -and $_.ExecutablePath } | Select-Object -First 1
    if ($running) { [pscustomobject]@{ Name = $name; Path = $running.ExecutablePath } }
})

$sessionFiles = Get-ChildItem (Join-Path $env:USERPROFILE '.claude\sessions\*.json') -ErrorAction SilentlyContinue
$sessions = @(foreach ($file in $sessionFiles) {
    $record = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $claude = $byId[[int]$record.pid]
    if (-not $claude -or $claude.Name -ne 'claude.exe' -or $record.kind -ne 'interactive') { continue }
    $ancestors = Get-Ancestors ([int]$record.pid) | Select-Object -Skip 1
    $editor = $ancestors | Where-Object { $_.Name -in $EditorNames } | Select-Object -First 1
    $shell = $ancestors | Where-Object { $_.Name -in @('powershell.exe', 'pwsh.exe') } | Select-Object -First 1
    [pscustomobject]@{
        SessionId  = $record.sessionId
        Name       = $record.name
        Cwd        = $record.cwd
        Entrypoint = $record.entrypoint
        ClaudePath = $claude.ExecutablePath
        Editor     = if ($editor) { $editor.Name } else { $null }
        EditorPath = if ($editor) { $editor.ExecutablePath } else { $null }
        ShellPath  = if ($shell) { $shell.ExecutablePath } else { $null }
    }
})

Write-JsonAtomic $SnapshotPath ([pscustomobject]@{
    LogonId  = $logonId
    TakenAt  = (Get-Date).ToString('o')
    Editors  = $editors
    Sessions = $sessions
})
