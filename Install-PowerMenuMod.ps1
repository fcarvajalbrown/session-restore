param(
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Remove) { $arguments += '-Remove' }
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

$windhawkIni = Join-Path $env:ProgramFiles 'Windhawk\windhawk.ini'
if (-not (Test-Path $windhawkIni)) { throw "Windhawk is not installed ($windhawkIni missing)" }
$windhawkDir = Split-Path $windhawkIni
$engineDir = Join-Path $windhawkDir ((Get-Content $windhawkIni | Where-Object { $_ -match '^EnginePath=' }) -replace '^EnginePath=', '')
$compilerDir = Join-Path $windhawkDir 'Compiler'
$modsDir = Join-Path $env:ProgramData 'Windhawk\Engine\Mods\64'
$registryKey = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$PowerMenuModId"
$logPath = Join-Path $env:ProgramData 'Windhawk\session-restore-power-menu.log'

function Remove-OldLibraries {
    Get-ChildItem -Path $modsDir -Filter "$($PowerMenuModId)_*.dll" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

if ($Remove) {
    if (Test-Path $registryKey) { Remove-Item -Path $registryKey -Recurse -Force }
    Start-Sleep -Seconds 2
    Remove-OldLibraries
    'Power menu mod removed' | Set-Content -Path $logPath
    exit 0
}

New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
foreach ($library in @(@('libc++.dll', 'libc++.whl'), @('libunwind.dll', 'libunwind.whl'), @('windhawk-mod-shim.dll', 'windhawk-mod-shim.dll'))) {
    $source = Join-Path $compilerDir "x86_64-w64-mingw32\bin\$($library[0])"
    $destination = Join-Path $modsDir $library[1]
    if (-not (Test-Path $destination) -or (Get-Item $destination).LastWriteTime -ne (Get-Item $source).LastWriteTime) {
        Copy-Item -Path $source -Destination $destination -Force
    }
}

$libraryName = '{0}_{1}_{2}.dll' -f $PowerMenuModId, $PowerMenuModVersion, (Get-Random -Minimum 100000 -Maximum 999999)
$clangArguments = @(
    '-std=c++23', '-O2', '-shared', '-DUNICODE', '-D_UNICODE',
    '-DWINVER=0x0A00', '-D_WIN32_WINNT=0x0A00', '-D_WIN32_IE=0x0A00', '-DNTDDI_VERSION=0x0A000008',
    '-D__USE_MINGW_ANSI_STDIO=0', '-DWH_MOD',
    "-DWH_MOD_ID=L`"$PowerMenuModId`"", "-DWH_MOD_VERSION=L`"$PowerMenuModVersion`"",
    (Join-Path $engineDir '64\windhawk.lib'),
    '-x', 'c++', $PowerMenuModSource,
    '-include', 'windhawk_api.h',
    '-target', 'x86_64-w64-mingw32',
    '-Wl,--export-all-symbols',
    '-o', (Join-Path $modsDir $libraryName),
    '-lruntimeobject', '-lole32', '-loleaut32', '-luser32'
)
Push-Location $compilerDir
try {
    $output = & (Join-Path $compilerDir 'bin\clang++.exe') @clangArguments 2>&1
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
$output | Out-String | Set-Content -Path $logPath
if ($exitCode -ne 0) { throw "compile failed with exit code $exitCode, see $logPath" }

$previous = (Get-ItemProperty -Path $registryKey -Name LibraryFileName -ErrorAction SilentlyContinue).LibraryFileName
New-Item -Path $registryKey -Force | Out-Null
$values = @{
    LibraryFileName = $libraryName
    Include = 'StartMenuExperienceHost.exe'
    Exclude = ''
    IncludeCustom = ''
    ExcludeCustom = ''
    Architecture = 'x86-64'
    Version = $PowerMenuModVersion
}
foreach ($name in $values.Keys) {
    New-ItemProperty -Path $registryKey -Name $name -Value $values[$name] -PropertyType String -Force | Out-Null
}
foreach ($name in @('Disabled', 'LoggingEnabled', 'DebugLoggingEnabled', 'IncludeExcludeCustomOnly')) {
    New-ItemProperty -Path $registryKey -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
}
New-ItemProperty -Path $registryKey -Name 'SettingsChangeTime' -Value ([int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 0x7fffffff)) -PropertyType DWord -Force | Out-Null
if ($previous -and $previous -ne $libraryName) {
    Start-Sleep -Seconds 2
    Remove-Item -Path (Join-Path $modsDir $previous) -Force -ErrorAction SilentlyContinue
}
"Power menu mod installed: $libraryName" | Add-Content -Path $logPath
