$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $workspace 'winui\Backend.Snapshot.ps1') -Workspace $workspace -Fixture
if($LASTEXITCODE -ne 0){throw 'Bridge process failed.'}
$snapshot=$output|ConvertFrom-Json
if(@($snapshot.Games).Count -ne 1 -or $snapshot.Games[0].Title -ne 'Fixture game'){throw 'Bridge response did not preserve the library contract.'}
if($null -eq $snapshot.Games[0].NeedsAttention -or $snapshot.Games[0].CoverPath -ne ''){throw 'Bridge response omitted readiness or artwork fields.'}
if(@($snapshot.Notices).Count -ne 1){throw 'Bridge response lost scan notices.'}
'All 3 WinUI bridge checks passed. Fixture scan only; no personal data changed.'
