$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$launcher = Join-Path $here 'Hidden.vbs'
$user = "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

$restoreTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$restoreTrigger.Delay = 'PT30S'
$restoreAction = New-ScheduledTaskAction -Execute $wscript -Argument "`"$launcher`" `"$(Join-Path $here 'Restore-Session.ps1')`""
$restoreSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'SessionRestore Restore' -Action $restoreAction -Trigger $restoreTrigger -Settings $restoreSettings -Principal $principal -Force | Out-Null

$snapshotTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$snapshotTrigger.Delay = 'PT5M'
$snapshotTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 3)).Repetition
$fromNowTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 3)
$snapshotAction = New-ScheduledTaskAction -Execute $wscript -Argument "`"$launcher`" `"$(Join-Path $here 'Save-Snapshot.ps1')`""
Register-ScheduledTask -TaskName 'SessionRestore Snapshot' -Action $snapshotAction -Trigger @($snapshotTrigger, $fromNowTrigger) -Settings $settings -Principal $principal -Force | Out-Null

. (Join-Path $here 'Common.ps1')
foreach ($profilePath in Get-ShellProfilePaths) {
    New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
    $existing = if (Test-Path $profilePath) { @(Get-Content -LiteralPath $profilePath) } else { @() }
    if ($existing -notcontains $ProfileHookLine) {
        Add-Content -LiteralPath $profilePath -Value $ProfileHookLine -Encoding UTF8
    }
    "Folder tracking in $profilePath"
}

$commandKey = Join-Path $UriKey 'shell\open\command'
New-Item -Path $commandKey -Force | Out-Null
Set-Item -Path $UriKey -Value "URL:$UriScheme"
New-ItemProperty -Path $UriKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
Set-Item -Path $commandKey -Value "`"$wscript`" `"$launcher`" `"$(Join-Path $here 'Save-AndShutdown.ps1')`" `"-Uri`" `"%1`""
"URI handler: ${UriScheme}:shutdown, ${UriScheme}:restart"

Get-ScheduledTask -TaskName 'SessionRestore*' |ForEach-Object { '{0}: {1}' -f $_.TaskName, $_.State }
