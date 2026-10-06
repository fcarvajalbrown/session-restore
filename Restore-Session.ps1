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

$lines = New-Object System.Collections.Generic.List[string]
$sessions = @($snapshot.Sessions | Sort-Object SessionId -Unique)
$running = Get-Process -ErrorAction SilentlyContinue | ForEach-Object { "$($_.ProcessName).exe" }

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

foreach ($session in $sessions) {
    $label = if ($session.Name) { $session.Name } else { $session.SessionId.Substring(0, 8) }
    $resume = "claude --resume $($session.SessionId)"
    $lines.Add('')
    $lines.Add("$label")
    $lines.Add("  folder: $($session.Cwd)")
    $lines.Add("  resume: cd $(Quote $session.Cwd); $resume")

    if (-not (Test-Path -LiteralPath $session.Cwd)) {
        $lines.Add('  NOT reopened: folder missing (drive disconnected?)')
        continue
    }
    if ($session.Entrypoint -ne 'cli') {
        $lines.Add('  NOT reopened: it ran in the editor''s Claude panel; reopen it from there or use the resume line')
        continue
    }
    if ($session.EditorPath -and (Test-Path $session.EditorPath)) {
        Start-Launch $session.EditorPath @("`"$($session.Cwd)`"")
    }
    $shell = if ($session.ShellPath -and (Test-Path $session.ShellPath)) { $session.ShellPath } else { Join-Path $PSHOME 'powershell.exe' }
    $claude = if ($session.ClaudePath -and (Test-Path $session.ClaudePath)) { "& $(Quote $session.ClaudePath)" } else { 'claude' }
    $command = "`$Host.UI.RawUI.WindowTitle = $(Quote $label); $claude --resume $($session.SessionId)"
    Start-Launch $shell @('-NoExit', '-Command', $command) $session.Cwd
    $where = if ($session.Editor) { " (was in $($session.Editor -replace '\.exe$', ''); editor reopened on the folder)" } else { '' }
    $lines.Add("  reopened in a PowerShell window$where")
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
$form.Text = "Restored after restart: $($sessions.Count) Claude session(s)"
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
