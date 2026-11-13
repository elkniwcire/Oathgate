$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Library.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
$root=Join-Path $PSScriptRoot ('.tmp\library-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root -Force)
function Draft($Name,$Id,$Exe){$d=New-Object SteamNite.ShortcutDraft;$d.Title=$Name;$d.ManagedId=$Id;$d.Exe='"'+$Exe+'"';$d.StartDir='"'+$root+'"';$d.LaunchOptions='';$d.AppId=[SteamNite.SteamShortcuts]::AppId($d.Exe,$d.Title);$d}
try{
    $helper=Join-Path $root 'gamelaunchhelper.exe';[IO.File]::WriteAllBytes($helper,[byte[]]@())
    $drafts=@((Draft 'Installed fixture' 'steamnite:xbox:installed' $helper),(Draft 'Removed fixture' 'steamnite:epic:removed' 'C:\Fixture\removed.exe'),(Draft 'Offline fixture' 'steamnite:amazon:offline' 'C:\Fixture\offline.exe'),(Draft 'Manual fixture' '' 'C:\Fixture\manual.exe'),(Draft 'Undetected fixture' 'steamnite:xbox:undetected' 'C:\Fixture\undetected.exe'))
    $file=[SteamNite.SteamShortcuts]::new(([SteamNite.SteamShortcuts]::new([byte[]]$null)).Append([SteamNite.ShortcutDraft[]]$drafts))
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');AccountId='fixture';SteamRoot=$root}
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$file.Append([SteamNite.ShortcutDraft[]]@()))
    $game=[pscustomobject]@{Id='xbox:installed';Title='Installed fixture';Platform='Xbox';InstallPath=$root;Method='Xbox launch helper';Target=$helper;Arguments='';Status='Ready to test';Evidence='fixture';Note=''}
    $plan=[pscustomobject]@{Shortcuts=$file.Items.ToArray();Rows=@(
        [pscustomobject]@{AppId=$drafts[0].AppId;Status='Keep';Reason='Installation exists'},
        [pscustomobject]@{AppId=$drafts[1].AppId;Status='Removal candidate';Reason='Confirmed uninstalled'},
        [pscustomobject]@{AppId=$drafts[2].AppId;Status='Cannot verify';Reason='Drive unavailable'},
        [pscustomobject]@{AppId=$drafts[3].AppId;Status='Keep';Reason='Manual shortcut'},
        [pscustomobject]@{AppId=$drafts[4].AppId;Status='Keep';Reason='Still registered'}
    )}
    $historyPath=Join-Path $root 'history.json'
    @{Games=@([pscustomobject]@{Id='epic:removed';InstallPath='D:\Previous\removed'})}|ConvertTo-Json|Set-Content -LiteralPath $historyPath -Encoding UTF8
    $library=@(Get-UnifiedGameLibrary @($game) $profile $plan $historyPath)
    Assert ($library.Count -eq 5) 'Installed games and Steam-only shortcuts form one combined library'
    $installed=@($library|Where-Object NativeGameId -eq $game.Id)
    Assert ($installed.Count -eq 1 -and $installed[0].InstallState -eq 'Installed' -and $installed[0].SteamSyncStatus -eq 'Synced') 'An installed synced game appears once with both states'
    Assert (-not $installed[0].CanRemove -and $installed[0].Target -eq $helper) 'Installed entries retain launch recipes and are not removable'
    $removed=@($library|Where-Object NativeGameId -eq 'epic:removed')[0]
    Assert ($removed.InstallState -eq 'Not installed' -and $removed.SteamSyncStatus -eq 'Synced' -and $removed.CanRemove) 'A confirmed uninstall remains visible in Steam and can be selected for removal'
    Assert ($removed.SteamAppId -eq $drafts[1].AppId -and $removed.InstallPath -eq 'D:\Previous\removed') 'Steam-only rows preserve actual shortcut IDs and recorded locations'
    Assert ($removed.Status -ne 'Ready to test' -and $removed.Target -eq '') 'Uninstalled rows cannot accidentally launch or be re-added as installed games'
    $offline=@($library|Where-Object NativeGameId -eq 'amazon:offline')[0]
    Assert ($offline.InstallState -eq 'Unverified' -and -not $offline.CanRemove) 'Unverifiable Steam-only entries are not mislabeled uninstalled'
    $manual=@($library|Where-Object Title -eq 'Manual fixture')[0]
    Assert ($manual.InstallState -eq 'Manual shortcut' -and $manual.Platform -eq 'Manual' -and -not $manual.CanRemove) 'Manual shortcuts are visible but protected'
    Assert ($manual.CanRemoveExplicitly -and $removed.CanRemoveExplicitly) 'Manual and managed shortcuts can both enter user-requested removal review'
    $undetected=@($library|Where-Object NativeGameId -eq 'xbox:undetected')[0]
    Assert ($undetected.InstallState -eq 'Not detected' -and -not $undetected.CanRemove) 'Still-registered or residual installs are not removal candidates'
    $withoutProfile=@(Get-UnifiedGameLibrary -InstalledGames @($game))
    Assert ($withoutProfile.Count -eq 1 -and $withoutProfile[0].SteamSyncStatus -eq 'No profile') 'Without a Steam account the installed library remains available'
    $unresolved=$game.PSObject.Copy();$unresolved.Status='Unresolved'
    $attention=@(Get-UnifiedGameLibrary @($unresolved) $profile $plan $historyPath)
    Assert (@($attention|Where-Object NativeGameId -eq $game.Id).Count -eq 1) 'Unresolved installed entries do not acquire duplicate Steam-only rows'
    $legacy=Draft $game.Title '' $helper
    $legacyFile=[SteamNite.SteamShortcuts]::new(([SteamNite.SteamShortcuts]::new([byte[]]$null)).Append([SteamNite.ShortcutDraft[]]@($legacy)))
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$legacyFile.Append([SteamNite.ShortcutDraft[]]@()))
    $legacyPlan=[pscustomobject]@{Shortcuts=$legacyFile.Items.ToArray();Rows=@([pscustomobject]@{AppId=$legacy.AppId;Status='Keep';Reason='Manual shortcut'})}
    $merged=@(Get-UnifiedGameLibrary @($game) $profile $legacyPlan $historyPath)
    Assert ($merged.Count -eq 1 -and $merged[0].SteamSyncStatus -eq 'Synced' -and -not $merged[0].CanRemove) 'Legacy manual shortcuts matching an installed launch target are merged without losing protection'
    $empty=@(Get-UnifiedGameLibrary -InstalledGames @() -Profile $profile -RemovalPlan $legacyPlan -HistoryPath $historyPath)
    Assert ($empty.Count -eq 1 -and $empty[0].InstallState -eq 'Manual shortcut') 'Steam-only games remain visible when no installed games are discovered'
    $gonePath=Join-Path $root 'gone-manual';$goneTarget=Join-Path $gonePath 'gamelaunchhelper.exe'
    $goneDraft=Draft 'Legacy Xbox (Xbox)' '' $goneTarget
    $goneFile=[SteamNite.SteamShortcuts]::new(([SteamNite.SteamShortcuts]::new([byte[]]$null)).Append([SteamNite.ShortcutDraft[]]@($goneDraft)))
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$goneFile.Append([SteamNite.ShortcutDraft[]]@()))
    $record=[pscustomobject]@{Id='xbox:legacy';Title='Legacy Xbox';InstallPath=$gonePath;Method='Xbox launch helper';Target=$goneTarget;Arguments=''}
    @{Games=@($record)}|ConvertTo-Json|Set-Content -LiteralPath $historyPath -Encoding UTF8
    $manualPlan=[pscustomobject]@{Shortcuts=$goneFile.Items.ToArray();Rows=@();Inventory=[pscustomobject]@{XboxComplete=$true;XboxNames=@()}}
    $gone=@(Get-UnifiedGameLibrary @() $profile $manualPlan $historyPath)[0]
    Assert ($gone.InstallState -eq 'Not installed' -and $gone.Platform -eq 'Xbox') 'An exact historical manual launch target can show its confirmed uninstall'
    Assert (-not $gone.CanRemove -and -not $gone.NativeGameId -and $gone.SteamSyncDetail -like '*protected*') 'Historical association never grants ownership or removal permission'
    Assert ($gone.AttentionDetail -like '*protected*') 'The selected-game panel explains why a manually added uninstall cannot be removed'
    $manualPlan.Inventory.XboxComplete=$false
    $unverified=@(Get-UnifiedGameLibrary @() $profile $manualPlan $historyPath)[0]
    Assert ($unverified.InstallState -eq 'Unverified' -and -not $unverified.CanRemove) 'Incomplete platform evidence cannot label a historical manual game uninstalled'
    $manualPlan.Inventory.XboxComplete=$true
    @{Games=@($record,$record)}|ConvertTo-Json|Set-Content -LiteralPath $historyPath -Encoding UTF8
    $ambiguous=@(Get-UnifiedGameLibrary @() $profile $manualPlan $historyPath)[0]
    Assert ($ambiguous.InstallState -eq 'Manual shortcut') 'Ambiguous historical matches remain manual and unverified'
    "`nAll $script:passed unified library checks passed. No real Steam files changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
