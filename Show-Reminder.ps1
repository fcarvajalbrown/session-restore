param(
    [string]$Title = 'Reminder',
    [string]$TextPath = (Join-Path (Join-Path $env:LOCALAPPDATA 'SessionRestore') 'reminder.txt')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $TextPath)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.Size = New-Object System.Drawing.Size(820, 300)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Consolas', 11)
$box.Text = (Get-Content $TextPath -Raw)
$form.Controls.Add($box)
[void]$form.ShowDialog()
