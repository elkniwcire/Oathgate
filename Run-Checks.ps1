param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Run checks using Windows PowerShell 5.1 (powershell.exe).' }
$root=Join-Path $PSScriptRoot ('tests\.tmp\check-run-'+[guid]::NewGuid().ToString('N'))
$previous=$env:OATHGATE_DATA_DIR
try {
    $env:OATHGATE_DATA_DIR=Join-Path $root 'isolated-user-data'
    if (-not $SkipBuild) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-WinUI.ps1');if($LASTEXITCODE){throw 'Build failed.'} }
    foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tests') -Filter 'Run-*Tests.ps1' | Sort-Object Name)) {
        Write-Output ('Checking '+$test.Name)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test.FullName
        if ($LASTEXITCODE) { throw ('Failed: '+$test.Name) }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SteamNite.ps1') -SmokeTest
    if ($LASTEXITCODE) { throw 'UI construction failed.' }
    Write-Output 'All checks passed. No personal app state or Steam library was changed.'
} finally { $env:OATHGATE_DATA_DIR=$previous }
