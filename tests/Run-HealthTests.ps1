$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Library.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.BulkArtwork.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Artwork.psm1')
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\health-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$prefs=Join-Path $root 'preferences.json';$overrides=Join-Path $root 'overrides.json'
& (Get-Module SteamNite.Steam) {param($p) $script:fixturePreferences=$p;function script:Get-GamePreferencesPath {$script:fixturePreferences};function script:Test-SteamRunning {$false}} $prefs
& (Get-Module SteamNite.Core) {param($p) $script:fixtureOverrides=$p;function script:Get-LaunchOverridesPath {$script:fixtureOverrides}} $overrides
try{
    $old=Join-Path $root 'old';$new=Join-Path $root 'new'
    [void][IO.Directory]::CreateDirectory($old);[void][IO.Directory]::CreateDirectory($new)
    $oldExe=Join-Path $old 'gamelaunchhelper.exe';$newExe=Join-Path $new 'gamelaunchhelper.exe'
    [IO.File]::WriteAllBytes($oldExe,[byte[]]@());[IO.File]::WriteAllBytes($newExe,[byte[]]@())
    $d=New-Object SteamNite.ShortcutDraft;$d.Title='My custom Steam title';$d.Exe='"'+$oldExe+'"';$d.StartDir='"'+$old+'"';$d.LaunchOptions='--old';$d.ManagedId='steamnite:xbox:health';$d.AppId=[SteamNite.SteamShortcuts]::AppId($d.Exe,$d.Title)
    $manual=New-Object SteamNite.ShortcutDraft;$manual.Title='Unrelated manual game';$manual.Exe='"C:\Manual\game.exe"';$manual.StartDir='"C:\Manual"';$manual.LaunchOptions='--manual';$manual.ManagedId='';$manual.AppId=[SteamNite.SteamShortcuts]::AppId($manual.Exe,$manual.Title)
    $file=[SteamNite.SteamShortcuts]::new([byte[]]$null)
    $bytes=$file.Append([SteamNite.ShortcutDraft[]]@($manual,$d))
    $file=[SteamNite.SteamShortcuts]::new($bytes);$icon=Join-Path $root 'custom.ico';[IO.File]::WriteAllBytes($icon,[byte[]]@(1))
    $bytes=$file.WithIcon($d.AppId,$icon)
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');SteamRoot=$root;AccountId='fixture'}
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$bytes)
    $game=[pscustomobject]@{Id='xbox:health';Title='Detected title';Platform='Xbox';InstallPath=$new;Target=$newExe;Arguments='';Method='Xbox launch helper';Status='Ready to test';Note='';Evidence='fixture'}
    $plan=New-SteamSyncPlan $profile @($game)
    Assert ($plan.AddCount -eq 0 -and $plan.RepairCount -eq 1 -and $plan.Rows[0].Action -eq 'Repair') 'Moved game produces one repair instead of a duplicate'
    Assert ((Get-GameSteamStatuses @($game) $profile).Status -eq 'Needs repair') 'Outdated managed launch fields are not labeled synced'
    $needsRepair=@(Get-UnifiedGameLibrary @($game) $profile)[0]
    Assert ((Test-LibraryAttentionFilter $needsRepair 'Needs repair') -and (Test-LibraryAttentionFilter $needsRepair 'Needs attention')) 'Repair candidates appear in both repair and attention filters'
    Assert (-not (Test-LibraryAttentionFilter $needsRepair 'Not in Steam')) 'An outdated shortcut is not confused with a missing shortcut'
    Assert ((Get-ShortcutSnapshot $profile.ShortcutPath).Hash -eq $plan.OriginalHash) 'Repair preview leaves the file unchanged'
    $repaired=[SteamNite.SteamShortcuts]::new($plan.OutputBytes)
    $item=@($repaired.Items|Where-Object AppId -eq $d.AppId)[0]
    Assert ($item.Title -eq $d.Title -and $item.Icon -eq $icon -and $item.AppId -eq $d.AppId) 'Repair preserves custom title, icon and Steam artwork identity'
    Assert ($item.Exe -eq ('"'+$newExe+'"') -and $item.StartDir -eq ('"'+$new+'"') -and $item.LaunchOptions -eq '') 'Repair updates executable, working directory and arguments'
    $restored=$repaired.RepairLaunch($d.AppId,$d.ManagedId,$d)
    Assert ([Convert]::ToBase64String($restored) -eq [Convert]::ToBase64String($bytes)) 'Only launch field bytes change; unrelated records and managed settings survive exactly'
    Assert (Throws {$repaired.RepairLaunch($manual.AppId,$d.ManagedId,$d)}) 'Manual shortcuts cannot be repaired using another game identity'
    $result=Save-SteamSyncPlan $plan
    Assert ($result.Repaired -eq 1 -and $result.Added -eq 0 -and (Test-Path $result.BackupPath)) 'Repair-only apply creates an exact backup'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath)) -eq [Convert]::ToBase64String($bytes)) 'Repair backup preserves the original file'
    Assert ((New-SteamSyncPlan $profile @($game)).RepairCount -eq 0 -and (Get-GameSteamStatuses @($game) $profile).Status -eq 'Synced') 'Repaired game becomes current and repeat sync is idempotent'
    $library=@(Get-UnifiedGameLibrary @($game) $profile)
    Assert ($library[0].ArtworkStatus -eq '1/5' -and $library[0].MissingArtwork.Count -eq 4) 'Artwork completeness counts an existing custom icon'
    Assert (Test-LibraryAttentionFilter $library[0] 'Missing artwork') 'Missing-art filter includes an incomplete installed game'
    Assert (Test-LibraryAttentionFilter $library[0] 'Needs attention') 'Incomplete artwork contributes an actionable attention reason'
    $grid=Join-Path $root 'grid';[void][IO.Directory]::CreateDirectory($grid)
    foreach($kind in @('Cover','Wide','Hero','Logo')){[IO.File]::WriteAllBytes((Join-Path $grid ((Get-ArtworkStem $d.AppId $kind)+'.png')),[byte[]]@(1))}
    $library=@(Get-UnifiedGameLibrary @($game) $profile)
    Assert ($library[0].ArtworkStatus -eq '5/5' -and -not $library[0].NeedsAttention) 'Complete current game leaves the attention filter'
    Set-GameIgnored @($game.Id) $true $prefs
    Set-GameIgnored @('epic:another') $true $prefs
    Assert (@(Get-IgnoredGameIds $prefs).Count -eq 2) 'Exclusions persist across separate saves'
    $ignoredPlan=New-SteamSyncPlan $profile @($game)
    Assert ($ignoredPlan.Rows[0].Action -eq 'Ignored' -and $ignoredPlan.RepairCount -eq 0 -and $ignoredPlan.AddCount -eq 0) 'Excluded game never produces a Steam write'
    $library=@(Get-UnifiedGameLibrary @($game) $profile)
    Assert ($library[0].Ignored -and -not $library[0].NeedsAttention -and (Test-LibraryAttentionFilter $library[0] 'Ignored')) 'Ignored games remain visible but leave the attention queue'
    $bulk=Invoke-BulkArtworkGame $game $profile $root ''
    Assert ($bulk.Status -eq 'Ignored' -and $bulk.Added -eq 0) 'Bulk artwork skips excluded games without an API request'
    Set-GameIgnored @($game.Id) $false $prefs
    Assert ($game.Id -notin @(Get-IgnoredGameIds $prefs) -and 'epic:another' -in @(Get-IgnoredGameIds $prefs)) 'Unignore preserves other exclusions'
    Set-GameLaunchOverride -GameId $game.Id -Executable $oldExe -WorkingDirectory $old -Arguments '--custom "argument value"' -Path $overrides
    $effective=Get-EffectiveGameLaunch $game -Path $overrides
    Assert ($effective.HasLaunchOverride -and $effective.Target -eq $oldExe -and $effective.InstallPath -eq $new) 'Saved override changes launch configuration without changing install evidence'
    $launch=Start-DetectedGame $game -DryRun
    Assert ($launch.FileName -eq $oldExe -and $launch.WorkingDirectory -eq $old -and $launch.Arguments -eq '--custom "argument value"') 'Test launch uses the saved executable, folder and literal arguments'
    $overridePlan=New-SteamSyncPlan $profile @($game)
    Assert ($overridePlan.RepairCount -eq 1 -and $overridePlan.Rows[0].Draft.Exe -eq ('"'+$oldExe+'"') -and $overridePlan.Rows[0].Draft.LaunchOptions -eq $launch.Arguments) 'Steam repair uses the user override instead of the detected helper'
    Set-GameIgnored @($game.Id) $true $prefs
    Assert (Throws {Save-SteamSyncPlan $overridePlan}) 'Excluding a game after preview prevents a stale repair from applying'
    Set-GameIgnored @($game.Id) $false $prefs
    Assert (Throws {Set-GameLaunchOverride -GameId $game.Id -Executable (Join-Path $root 'missing.exe') -Path $overrides}) 'Missing executable overrides are rejected'
    Set-GameLaunchOverride -GameId $game.Id -Reset -Path $overrides
    Assert (Throws {Save-SteamSyncPlan $overridePlan}) 'Changing launch preferences after preview requires a fresh review'
    Assert ((Start-DetectedGame $effective -DryRun).FileName -eq $newExe) 'Resetting an override returns even an older selected row to its detected launch recipe'
    Assert ((New-SteamSyncPlan $profile @($game)).RepairCount -eq 0) 'Resetting an unapplied override does not change Steam'
    $activation=$game.PSObject.Copy();$activation.Id='xbox:activation';$activation.Method='Windows activation';$activation.Target='Fixture.Game_abcd!Game'
    Set-GameLaunchOverride -GameId $activation.Id -Executable $oldExe -WorkingDirectory $old -Path $overrides
    $selectedOverride=Get-EffectiveGameLaunch $activation
    Set-GameLaunchOverride -GameId $activation.Id -Reset -Path $overrides
    $activationPlan=New-SteamSyncPlan $profile @($selectedOverride)
    Assert ($activationPlan.Rows[0].Draft.LaunchOptions -eq 'shell:AppsFolder\Fixture.Game_abcd!Game') 'Resetting a package override restores Windows activation when syncing a previously selected row'
    Set-GameLaunchOverride -GameId $game.Id -Executable $oldExe -WorkingDirectory $old -Path $overrides
    Remove-Item -LiteralPath $oldExe
    Assert ((Get-EffectiveGameLaunch $game).Status -eq 'Override missing' -and (Throws {Start-DetectedGame $game -DryRun})) 'A removed override executable is reported and never silently falls back'
    $attention=@(Get-UnifiedGameLibrary @($game) $profile)[0]
    Assert ($attention.NeedsAttention -and $attention.Status -eq 'Override missing') 'A missing custom executable is visible in the attention queue'
    $unknown=Get-LibraryArtworkState $null $null $null
    Assert ($unknown.Text -eq 'No profile' -and $unknown.Missing.Count -eq 0) 'No Steam account is not misreported as missing artwork'
    Assert (Throws {Set-GameLaunchOverride -GameId $game.Id -Executable $newExe -WorkingDirectory (Join-Path $root 'missing-folder') -Path $overrides}) 'Invalid working directories cannot be saved'
    "`nAll $script:passed health and preference checks passed. No real Steam files changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
