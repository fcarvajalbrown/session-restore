param(
    [switch]$DryRun,
    [switch]$NoPopup
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$logonId = Get-LogonId
$restoredFor = if (Test-Path $RestoredMarkerPath) { (Get-Content $RestoredMarkerPath -Raw).Trim() } else { '' }
if (-not (Test-Path $SnapshotPath) -or ($restoredFor -eq $logonId -and -not $DryRun)) { exit 0 }

$snapshot = Get-Content $SnapshotPath -Raw | ConvertFrom-Json
if ($snapshot.LogonId -eq $logonId -and -not $DryRun) {
    Set-Content -Path $RestoredMarkerPath -Value $logonId -Encoding UTF8
    exit 0
}

function Start-Launch([string]$File, [string[]]$Arguments, [string]$Directory) {
    if ($DryRun) { return }
    $options = @{ FilePath = $File }
    if ($Arguments) { $options.ArgumentList = $Arguments }
    if ($Directory) { $options.WorkingDirectory = $Directory }
    Start-Process @options
}

function Quote([string]$Text) { "'" + $Text.Replace("'", "''") + "'" }

function Get-Label($Session) { if ($Session.Name) { $Session.Name } else { $Session.SessionId.Substring(0, 8) } }
function Get-ValidPath([string]$Path) { if ($Path -and (Test-Path $Path)) { $Path } else { $null } }

function Start-SessionWindow($Session) {
    $shell = Get-ValidPath $Session.ShellPath
    if (-not $shell) { $shell = Join-Path $PSHOME 'powershell.exe' }
    $claudePath = Get-ValidPath $Session.ClaudePath
    $claude = if ($claudePath) { "& $(Quote $claudePath)" } else { 'claude' }
    $command = "`$Host.UI.RawUI.WindowTitle = $(Quote (Get-Label $Session)); $claude --resume $($Session.SessionId)"
    Start-Launch $shell @('-NoExit', '-Command', $command) $Session.Cwd
}

$lines = New-Object System.Collections.Generic.List[string]
$sessions = @($snapshot.Sessions | Sort-Object SessionId -Unique)
$running = Get-Process -ErrorAction SilentlyContinue | ForEach-Object { "$($_.ProcessName).exe" }
$outcome = @{}
$editorSessions = @(foreach ($session in $sessions) {
    if (-not (Test-Path -LiteralPath $session.Cwd)) {
        $outcome[$session.SessionId] = 'NOT reopened: folder missing (drive disconnected?)'
    } elseif ($session.Entrypoint -ne 'cli') {
        $outcome[$session.SessionId] = 'NOT reopened: it ran in the editor''s Claude panel; reopen it from there or use the resume line'
    } elseif ($session.Editor -and (Get-ValidPath $session.EditorPath)) {
        $session
    }
})

if (-not $DryRun) {
    Remove-Item -LiteralPath $ClaimDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-JsonAtomic $EditorPendingPath ([pscustomobject]@{
        LogonId  = $logonId
        Sessions = @($editorSessions | ForEach-Object {
            [pscustomobject]@{
                SessionId  = $_.SessionId
                Label      = Get-Label $_
                Cwd        = $_.Cwd
                Editor     = $_.Editor
                ShellPath  = Get-ValidPath $_.ShellPath
                ClaudePath = Get-ValidPath $_.ClaudePath
            }
        })
    })
}

foreach ($editor in @($snapshot.Editors)) {
    if ($editor.Name -in $running) { continue }
    if (Test-Path $editor.Path) {
        Start-Launch $editor.Path
        $lines.Add("Reopened $($editor.Name -replace '\.exe$', '')")
    } else {
        $lines.Add("Not found: $($editor.Path)")
    }
}
if ($snapshot.Editors -and -not $DryRun) { Start-Sleep -Seconds 8 }

$openedFolders = @{}
foreach ($session in $editorSessions) {
    $key = "$($session.EditorPath)|$($session.Cwd.ToLowerInvariant().TrimEnd('\'))"
    if (-not $openedFolders.ContainsKey($key)) {
        Start-Launch $session.EditorPath @("`"$($session.Cwd)`"")
        $openedFolders[$key] = $true
    }
}

foreach ($session in $sessions) {
    if ($outcome.ContainsKey($session.SessionId) -or $session -in $editorSessions) { continue }
    Start-SessionWindow $session
    $outcome[$session.SessionId] = 'reopened in a PowerShell window'
}

$deadline = (Get-Date).AddSeconds($EditorClaimTimeoutSeconds)
while (-not $DryRun -and $editorSessions.Count -and (Get-Date) -lt $deadline) {
    $unclaimed = @($editorSessions | Where-Object { -not (Test-Path (Join-Path $ClaimDir $_.SessionId)) })
    if (-not $unclaimed.Count) { break }
    Start-Sleep -Seconds 2
}
foreach ($session in $editorSessions) {
    $editorName = $session.Editor -replace '\.exe$', ''
    if ($DryRun -or (Test-Path (Join-Path $ClaimDir $session.SessionId))) {
        $outcome[$session.SessionId] = "reopened in a $editorName terminal"
    } else {
        Start-SessionWindow $session
        $outcome[$session.SessionId] = "reopened in a PowerShell window ($editorName did not pick it up; is the Session Restore Terminals extension installed?)"
    }
}
if (-not $DryRun) { Remove-Item -LiteralPath $EditorPendingPath -Force -ErrorAction SilentlyContinue }

foreach ($session in $sessions) {
    $lines.Add('')
    $lines.Add((Get-Label $session))
    $lines.Add("  folder: $($session.Cwd)")
    $lines.Add("  resume: cd $(Quote $session.Cwd); claude --resume $($session.SessionId)")
    $lines.Add("  $($outcome[$session.SessionId])")
}

foreach ($shellRecord in @($snapshot.Shells)) {
    if (-not $shellRecord) { continue }
    $lines.Add('')
    $lines.Add("PowerShell: $($shellRecord.Folder)")
    if (-not (Test-Path -LiteralPath $shellRecord.Folder)) {
        $lines.Add('  NOT reopened: folder missing (drive disconnected?)')
        continue
    }
    $shell = if ($shellRecord.ShellPath -and (Test-Path $shellRecord.ShellPath)) { $shellRecord.ShellPath } else { Join-Path $PSHOME 'powershell.exe' }
    Start-Launch $shell @('-NoExit') $shellRecord.Folder
    $lines.Add('  reopened in its folder')
}

$text = ($lines -join "`r`n").Trim()
Write-Log ("restore for logon $logonId from snapshot $($snapshot.TakenAt):`r`n$text")

if (-not $DryRun) {
    Set-Content -Path $RestoredMarkerPath -Value $logonId -Encoding UTF8
    Move-Item -Path $SnapshotPath -Destination (Join-Path $StateDir 'last-restored.json') -Force
}

if ($DryRun) { $text }
if (-not $text -or $NoPopup) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = "Restored after restart: $($sessions.Count) Claude session(s), $(@($snapshot.Shells | Where-Object { $_ }).Count) PowerShell window(s)"
$form.Size = New-Object System.Drawing.Size(900, 520)
$form.StartPosition = 'CenterScreen'
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Consolas', 10)
$box.Text = $text + "`r`n`r`nLog: $LogPath"
$form.Controls.Add($box)
[void]$form.ShowDialog()
