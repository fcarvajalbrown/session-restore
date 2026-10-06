$global:SessionRestoreShellDir = Join-Path $env:LOCALAPPDATA 'SessionRestore\shells'
$global:SessionRestoreShellFile = Join-Path $global:SessionRestoreShellDir "$PID.txt"
$global:SessionRestoreLastFolder = $null
$global:SessionRestoreInnerPrompt = $function:prompt
New-Item -ItemType Directory -Force -Path $global:SessionRestoreShellDir | Out-Null

function global:prompt {
    $folder = $PWD.ProviderPath
    if ($PWD.Provider.Name -eq 'FileSystem' -and $folder -ne $global:SessionRestoreLastFolder) {
        try {
            [IO.File]::WriteAllText($global:SessionRestoreShellFile, $folder)
            $global:SessionRestoreLastFolder = $folder
        } catch {}
    }
    & $global:SessionRestoreInnerPrompt
}
