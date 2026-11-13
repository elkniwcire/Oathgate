$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Storage.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Settings.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Artwork.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
$root=Join-Path $PSScriptRoot ('.tmp\storage-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$previous=$env:OATHGATE_DATA_DIR;$passed=0
function Assert($Value,$Message) { if (-not $Value) { throw ('FAIL: '+$Message) };$script:passed++;Write-Output ('PASS: '+$Message) }
try {
    $env:OATHGATE_DATA_DIR=Join-Path $root 'isolated'
    Assert ((Get-OathgateDataDirectory) -eq $env:OATHGATE_DATA_DIR) 'Explicit absolute data location isolates test state'
    $env:OATHGATE_DATA_DIR='relative';$rejected=$false
    try { Get-OathgateDataDirectory } catch { $rejected=$true }
    Assert $rejected 'Relative data overrides are rejected'
    $env:OATHGATE_DATA_DIR=$null
    Assert ((Get-OathgateDataDirectory) -eq (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Oathgate')) 'Default state follows the current Windows user'
    $legacy=Join-Path $root 'legacy';$destination=Join-Path $root 'new'
    [void][IO.Directory]::CreateDirectory((Join-Path $legacy 'operations'))
    [void][IO.Directory]::CreateDirectory((Join-Path $legacy 'artwork-cache'))
    [void][IO.Directory]::CreateDirectory($destination)
    [IO.File]::WriteAllText((Join-Path $legacy 'settings.json'),'{"ExtraRoots":["X:\\Fixture"]}')
    [IO.File]::WriteAllText((Join-Path $legacy 'launch-overrides.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $legacy 'scan-private.json'),'private export must not migrate')
    [IO.File]::WriteAllText((Join-Path $legacy 'operations\fixture.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $legacy 'artwork-cache\fixture.png'),'fixture')
    [IO.File]::WriteAllText((Join-Path $destination 'launch-overrides.json'),'existing')
    Set-ArtworkApiKey $legacy 'synthetic-migration-key'
    [void](Initialize-OathgateStorage $legacy $destination)
    Assert ((Get-AppSettings (Join-Path $destination 'settings.json')).ExtraRoots[0] -eq 'X:\Fixture') 'Settings migrate without a machine-specific root'
    Assert ((Get-Content (Join-Path $destination 'launch-overrides.json') -Raw) -eq 'existing') 'Migration does not overwrite existing destination state'
    Assert ((Get-ArtworkApiKey $destination) -eq 'synthetic-migration-key') 'Encrypted credentials migrate for the same Windows user'
    Assert (Test-Path (Join-Path $destination 'operations\fixture.json')) 'Preparation history migrates'
    Assert (Test-Path (Join-Path $destination 'artwork-cache\fixture.png')) 'Artwork cache migrates'
    Assert (-not (Test-Path (Join-Path $destination 'scan-private.json'))) 'Personal scan exports are excluded from migration'
    Assert (Test-Path (Join-Path $legacy 'steamgriddb.key')) 'Original data remains available for rollback'
    [IO.File]::WriteAllText((Join-Path $legacy 'game-preferences.json'),'{}')
    [void](Initialize-OathgateStorage $legacy $destination)
    Assert (-not (Test-Path (Join-Path $destination 'game-preferences.json'))) 'Completed migration does not silently reimport stale legacy state'
    $settings=Join-Path $destination 'settings.json';[IO.File]::WriteAllText($settings,'{broken')
    $recovered=Get-AppSettings $settings -Recover
    Assert ($recovered.Count -eq 0 -and @(Get-ChildItem $destination -Filter 'settings.json.invalid-*').Count -eq 1) 'Invalid settings recover to defaults with an original-file backup'
    Save-AppSettings $settings @{ExtraRoots=@('X:\New')}
    Assert ((Get-AppSettings $settings).ExtraRoots[0] -eq 'X:\New') 'Settings can be saved after recovery'
    $overrides=Join-Path $root 'utf8-overrides.json'
    $unicode=[char]0x65E5+[string][char]0x672C
    [IO.File]::WriteAllText($overrides,(@{Overrides=@(@{GameId='fixture:utf8';Executable=('X:\'+$unicode+'\game.exe')})}|ConvertTo-Json -Depth 5))
    Assert ((Get-LaunchOverrides $overrides)[0].Executable.Contains($unicode)) 'UTF-8 without a BOM preserves non-ASCII launch paths'
    [IO.File]::WriteAllBytes((Join-Path $destination 'steamgriddb.key'),[byte[]]@(1,2,3))
    Assert ((Get-ArtworkApiKey $destination) -eq '') 'An undecryptable key behaves as a missing key'
    Set-ArtworkApiKey $destination 'synthetic-replacement-key'
    Assert ((Get-ArtworkApiKey $destination) -eq 'synthetic-replacement-key') 'A new key can replace an unreadable credential'
    $env:OATHGATE_DATA_DIR=Join-Path $root 'isolated'
    [void](Initialize-OathgateStorage $legacy)
    Assert (-not (Test-Path (Join-Path $env:OATHGATE_DATA_DIR 'settings.json'))) 'Test storage never imports personal legacy settings'
    "All $passed storage checks passed."
} finally { $env:OATHGATE_DATA_DIR=$previous }
