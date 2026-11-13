$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Removal.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
$module=Get-Module SteamNite.Removal;$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;$false}catch{$true}}
$root=Join-Path $PSScriptRoot ('.tmp\remove-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root -Force)
function New-Draft([string]$Title,[string]$ManagedId,[string]$Suffix){
    $d=New-Object SteamNite.ShortcutDraft;$d.Title=$Title;$d.ManagedId=$ManagedId;$d.Exe='"C:\Fixture\'+$Suffix+'.exe"';$d.StartDir='"C:\Fixture"';$d.LaunchOptions='--keep-custom-options';$d.AppId=[SteamNite.SteamShortcuts]::AppId($d.Exe,$d.Title);$d
}
try{
    $registrations=[pscustomobject]@{Records=@(
        [pscustomobject]@{Key='stale-entitlement';Values=@{DisplayName='Uninstalled game'}},
        [pscustomobject]@{Key='installed';Values=@{InstallDir='D:\Games\Installed'}},
        [pscustomobject]@{Key='updating';Values=@{InstallLocation='D:\Games\Updating'}}
    )}
    $eaIds=@(& $module {param($snapshot) Get-UninstallRegistrationIds $snapshot 'EA'} $registrations)
    Assert ($eaIds.Count -eq 2 -and 'stale-entitlement' -notin $eaIds) 'EA display-name/entitlement leftovers do not count as installation registrations'
    Assert ('updating' -in $eaIds) 'EA registrations with a location remain conservative during updates'
    $gogIds=@(& $module {param($snapshot) Get-UninstallRegistrationIds $snapshot 'GOG'} $registrations)
    Assert ($gogIds.Count -eq 3) 'EA-specific leftover handling does not relax other platforms'
    $drafts=@(
        (New-Draft 'Gone Xbox' '' 'manual'),
        (New-Draft 'Gone Xbox' 'steamnite:xbox:Gone' 'xbox'),
        (New-Draft 'Gone Epic' 'steamnite:epic:gone' 'epic'),
        (New-Draft 'Gone Amazon' 'steamnite:amazon:gone' 'amazon'),
        (New-Draft 'Installed game' 'steamnite:xbox:Installed' 'installed'),
        (New-Draft 'Still registered' 'steamnite:xbox:Registered' 'registered'),
        (New-Draft 'No history' 'steamnite:xbox:Untracked' 'untracked')
    )
    $file=[SteamNite.SteamShortcuts]::new([byte[]]$null)
    [byte[]]$original=$file.Append([SteamNite.ShortcutDraft[]]$drafts)
    $file=[SteamNite.SteamShortcuts]::new($original)
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');SteamRoot=$root;AccountId='fixture'};[IO.File]::WriteAllBytes($profile.ShortcutPath,$original)
    $installed=Join-Path $root 'installed';[void](New-Item -ItemType Directory -Path $installed)
    $history=@(
        [pscustomobject]@{Id='xbox:Gone';InstallPath=(Join-Path $root 'gone-xbox')},
        [pscustomobject]@{Id='epic:gone';InstallPath=(Join-Path $root 'gone-epic')},
        [pscustomobject]@{Id='amazon:gone';InstallPath=(Join-Path $root 'gone-amazon')},
        [pscustomobject]@{Id='xbox:Installed';InstallPath=$installed},
        [pscustomobject]@{Id='xbox:Registered';InstallPath=(Join-Path $root 'registered')}
    )
    $historyPath=Join-Path $root 'history.json';Update-GameInstallHistory $historyPath $history
    Update-GameInstallHistory $historyPath @([pscustomobject]@{Id='xbox:Installed';InstallPath=$installed})
    Assert (@((Get-Content $historyPath -Raw|ConvertFrom-Json).Games).Count -eq 5) 'Install history retains missing games when newer scans contain fewer entries'
    Assert ((Get-UninstallPathState $installed) -eq 'Present') 'Existing install directories are recognized'
    Assert ((Get-UninstallPathState (Join-Path $root 'absent')) -eq 'Missing') 'A missing path on an available drive is distinguished from an offline drive'
    Assert ((Get-UninstallPathState '\\offline\share\game') -eq 'Unknown') 'Unverifiable network paths cannot authorize removals'
    $unused=@(90..70|ForEach-Object{[string][char]$_+':\'}|Where-Object{-not (Test-Path -LiteralPath $_)})[0]
    if($unused){Assert ((Get-UninstallPathState ($unused+'game')) -eq 'Unavailable') 'Unavailable drives do not look like uninstalled games'}
    $inventory=[pscustomobject]@{XboxComplete=$true;XboxNames=@('Registered');EpicComplete=$true;EpicIds=@();AmazonComplete=$true;AmazonIds=@();Notices=@()}
    Assert ((Get-ShortcutUninstallState $file.Items[0] $history $inventory).Status -eq 'Keep') 'Manual shortcuts are preserved even when their names match uninstalled games'
    foreach($i in @(1,2,3)){Assert ((Get-ShortcutUninstallState $file.Items[$i] $history $inventory).Status -eq 'Removal candidate') ('Missing installation plus absent platform identity authorizes candidate '+$i)}
    Assert ((Get-ShortcutUninstallState $file.Items[4] $history $inventory).Status -eq 'Keep') 'An existing installation is preserved even if registration is absent'
    Assert ((Get-ShortcutUninstallState $file.Items[5] $history $inventory).Status -eq 'Keep') 'Registered games and updates are preserved despite missing content paths'
    Assert ((Get-ShortcutUninstallState $file.Items[6] $history $inventory).Status -eq 'Cannot verify') 'Missing install history never authorizes removal'
    $partial=$inventory.PSObject.Copy();$partial.EpicComplete=$false
    Assert ((Get-ShortcutUninstallState $file.Items[2] $history $partial).Status -eq 'Cannot verify') 'Failed platform scans block removal instead of implying an uninstall'
    $offlineHistory=@([pscustomobject]@{Id='xbox:Gone';InstallPath='\\offline\share\game'})
    Assert ((Get-ShortcutUninstallState $file.Items[1] $offlineHistory $inventory).Status -eq 'Cannot verify') 'Unverifiable install locations are preserved even after a complete platform scan'
    Assert (Throws{[void]$file.RemoveManaged([uint32[]]@($drafts[0].AppId))}) 'The binary writer refuses to remove manual entries'
    Assert (Throws{[void]$file.RemoveManaged([uint32[]]@(1))}) 'Unknown shortcut IDs cannot be removed'
    Assert (Throws{[void]$file.RemoveManaged([uint32[]]@($drafts[1].AppId,$drafts[1].AppId))}) 'Duplicate removal IDs are rejected'
    $removed=[SteamNite.SteamShortcuts]::new($file.RemoveManaged([uint32[]]@($drafts[1].AppId)))
    Assert ($removed.Items.Count -eq 6 -and $removed.Items[0].Title -eq $drafts[0].Title -and $removed.Items[0].LaunchOptions -eq '--keep-custom-options') 'Removing a managed entry preserves unrelated manual shortcut settings'
    Assert (($removed.Items|ForEach-Object {$_.Index}) -join ',' -eq '0,1,2,3,4,5') 'Remaining containers are reindexed for Steam'
    Assert ([Convert]::ToBase64String($file.RemoveManaged([uint32[]]@())) -eq [Convert]::ToBase64String($original)) 'An empty removal selection leaves every byte unchanged'
    $allManaged=[uint32[]]@($drafts|Where-Object ManagedId|ForEach-Object {$_.AppId})
    Assert (([SteamNite.SteamShortcuts]::new($file.RemoveManaged($allManaged))).Items.Count -eq 1) 'Removing all managed entries still preserves manual shortcuts'
    & $module {param($state) $script:inventory=$state;$script:running=$false;function script:Get-UninstallInventory{$script:inventory};function script:Test-SteamRunning{$script:running}} $inventory
    $plan=New-SteamRemovalPlan $profile $historyPath
    Assert (@($plan.Rows|Where-Object Status -eq 'Removal candidate').Count -eq 3) 'Removal preview identifies only confirmed managed candidates'
    Assert ((Get-ShortcutSnapshot $profile.ShortcutPath).Hash -eq $plan.OriginalHash) 'Creating a preview never modifies Steam shortcuts'
    & $module {$script:running=$true}
    Assert (Throws{Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[1].AppId))}) 'Running Steam blocks removal writes'
    & $module {$script:running=$false;$script:inventory.XboxNames=@('Registered','Gone')}
    Assert (Throws{Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[1].AppId))}) 'A reinstall or registration change after preview blocks removal'
    & $module {$script:inventory.XboxNames=@('Registered')}
    [void](New-Item -ItemType Directory -Path $history[0].InstallPath)
    Assert (Throws{Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[1].AppId))}) 'Reappearing install files invalidate removal evidence'
    Remove-Item -LiteralPath $history[0].InstallPath
    Assert (Throws{Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[0].AppId))}) 'Unreviewed or manual entries cannot be removed through the plan API'
    $result=Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[1].AppId))
    Assert ($result.Removed -eq 1 -and (Test-Path -LiteralPath $result.BackupPath)) 'Applying selected removals creates a backup'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath)) -eq [Convert]::ToBase64String($original)) 'Removal backup is an exact copy of the previous shortcut file'
    $after=(Get-ShortcutSnapshot $profile.ShortcutPath).File
    Assert ($after.Items.Count -eq 6 -and @($after.Items|Where-Object AppId -eq $drafts[1].AppId).Count -eq 0) 'Only the checked candidate is removed'
    Assert (@($after.Items|Where-Object AppId -eq $drafts[2].AppId).Count -eq 1 -and (Test-Path -LiteralPath $installed)) 'Unchecked candidates and installed game directories stay intact'
    Assert (Throws{Save-SteamRemovalPlan $plan ([uint32[]]@($drafts[2].AppId))}) 'Stale removal previews cannot overwrite newer shortcut changes'
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count -eq 0) 'Removal leaves no temporary files behind'
    $reviewIds=[uint32[]]@($drafts[0].AppId,$drafts[2].AppId)
    $beforeReview=[IO.File]::ReadAllBytes($profile.ShortcutPath)
    $review=New-ReviewedShortcutRemoval $profile $reviewIds
    Assert ($review.Rows.Count -eq 2 -and $review.ManualCount -eq 1) 'Explicit bulk review includes exactly the selected managed and manual shortcuts'
    Assert (Throws {Save-ReviewedShortcutRemoval $review $false $true}) 'Explicit removal requires confirmation'
    Assert (Throws {Save-ReviewedShortcutRemoval $review $true $false}) 'Manual shortcuts require separate explicit consent'
    Assert (Throws {$after.RemoveReviewed([uint32[]]@($drafts[0].AppId),$false)}) 'The reviewed writer cannot bypass manual protection without consent'
    Assert (Throws {New-ReviewedShortcutRemoval $profile ([uint32[]]@($drafts[0].AppId,$drafts[0].AppId))}) 'Duplicate explicit removal selections are rejected'
    Assert (Throws {New-ReviewedShortcutRemoval $profile ([uint32[]]@(1))}) 'Unknown explicit shortcut selections are rejected'
    & $module {$script:running=$true}
    Assert (Throws {Save-ReviewedShortcutRemoval $review $true $true}) 'Running Steam also blocks explicitly requested removal'
    & $module {$script:running=$false}
    $changed=New-Draft 'Concurrent shortcut' '' 'new'
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$after.Append([SteamNite.ShortcutDraft[]]@($changed)))
    Assert (Throws {Save-ReviewedShortcutRemoval $review $true $true}) 'Concurrent changes invalidate explicit removal reviews'
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$beforeReview)
    $savedReview=Save-ReviewedShortcutRemoval $review $true $true
    $reviewedFile=(Get-ShortcutSnapshot $profile.ShortcutPath).File
    Assert ($savedReview.Removed -eq 2 -and @($reviewedFile.Items|Where-Object {$_.AppId -in $reviewIds}).Count -eq 0) 'Confirmed explicit bulk removal removes both selected ownership types'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($savedReview.BackupPath)) -eq [Convert]::ToBase64String($beforeReview)) 'Explicit bulk removal saves an exact shortcut backup'
    Assert ($reviewedFile.Items.Count -eq 4 -and (Test-Path -LiteralPath $installed)) 'Unselected shortcuts and installed game files remain intact'
    "`nAll $script:passed removal checks passed. Real games and Steam records were not changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
