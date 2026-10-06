$StateDir = Join-Path $env:LOCALAPPDATA 'SessionRestore'
$SnapshotPath = Join-Path $StateDir 'snapshot.json'
$RestoredMarkerPath = Join-Path $StateDir 'restored-logon.txt'
$LogPath = Join-Path $StateDir 'restore.log'
$EditorNames = @('Code.exe', 'VSCodium.exe')
$ShellNames = @('powershell.exe', 'pwsh.exe')
$ShellFolderDir = Join-Path $StateDir 'shells'
$TrackerPath = Join-Path $PSScriptRoot 'Track-ShellFolder.ps1'
$ProfileHookLine = "if (Test-Path '$TrackerPath') { . '$TrackerPath' }"

function Get-ShellProfilePaths {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
}

function Get-LogonId {
    $whoami = Join-Path $env:SystemRoot 'System32\whoami.exe'
    (& $whoami /logonid).Trim()
}

function Write-JsonAtomic([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $temporary = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 6 | Set-Content -Path $temporary -Encoding UTF8
    Move-Item -Path $temporary -Destination $Path -Force
}

function Write-Log([string]$Text) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    Add-Content -Path $LogPath -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Text) -Encoding UTF8
}
