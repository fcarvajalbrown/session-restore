param(
    [Parameter(Mandatory)][datetime]$At,
    [Parameter(Mandatory)][string]$TextFile,
    [string]$Name = 'SessionRestore Reminder'
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$stateDir = Join-Path $env:LOCALAPPDATA 'SessionRestore'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$textPath = Join-Path $stateDir "$($Name -replace '[^\w-]', '_').txt"
Copy-Item -Path $TextFile -Destination $textPath -Force

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$launcher = Join-Path $here 'Hidden.vbs'
$script = Join-Path $here 'Show-Reminder.ps1'
$action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$launcher`" `"$script`" `"$textPath`""
$trigger = New-ScheduledTaskTrigger -Once -At $At
$trigger.EndBoundary = $At.AddDays(2).ToString('s')
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DeleteExpiredTaskAfter (New-TimeSpan -Days 1)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
'{0} set for {1}' -f $Name, (Get-ScheduledTaskInfo -TaskName $Name).NextRunTime
