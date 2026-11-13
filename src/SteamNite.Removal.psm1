$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Steam.psm1')

function Update-GameInstallHistory([string]$Path,[object[]]$Games) {
    $records=@{}
    if(Test-Path -LiteralPath $Path){foreach($record in @((Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json).Games)){if($record.Id){$records[$record.Id]=$record}}}
    foreach($game in $Games){if($game.Id){$records[$game.Id]=$game}}
    [void](New-Item -ItemType Directory -Path (Split-Path $Path) -Force)
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{@{Games=@($records.Values);UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $temp -Encoding UTF8;Move-Item -LiteralPath $temp -Destination $Path -Force}
    finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Get-UninstallRegistrationIds($Snapshot,[string]$Platform) {
    foreach($record in $Snapshot.Records){
        if($Platform -eq 'EA'){
            if($null -eq $record.Values){$record.Key;continue}
            # EA retains entitlement/display-name keys after uninstall. A key
            # without any install location is not an installation registration.
            $locations=@(foreach($name in @('path','InstallDir','Install Dir','InstallLocation','InstallPath')){if($record.Values[$name]){[string]$record.Values[$name]}})
            if(-not $locations.Count){continue}
        }
        $record.Key
    }
}
function Get-UninstallInventory {
    $state=[pscustomobject]@{XboxComplete=$false;XboxNames=@();EpicComplete=$false;EpicIds=@();AmazonComplete=$false;AmazonIds=@();GOGComplete=$false;GOGIds=@();UbisoftComplete=$false;UbisoftIds=@();EAComplete=$false;EAIds=@();Notices=@()}
    $notices=New-Object 'System.Collections.Generic.List[string]'
    try{$state.XboxNames=@(Get-AppxPackage -ErrorAction Stop|ForEach-Object {$_.Name});$state.XboxComplete=$true}catch{$notices.Add('Xbox: package registration could not be read.')}
    try{
        $root=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Epic\EpicGamesLauncher\Data\Manifests'
        $ids=New-Object 'System.Collections.Generic.List[string]'
        foreach($file in @(Get-ChildItem -LiteralPath $root -Filter '*.item' -ErrorAction Stop)){
            $m=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
            if(-not $m.AppName){throw 'Manifest identity missing'};$ids.Add([string]$m.AppName)
        }
        $state.EpicIds=$ids.ToArray();$state.EpicComplete=$true
    }catch{$notices.Add('Epic: install records are missing, unreadable, or malformed.')}
    try{
        $db=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Amazon Games\Data\Games\Sql\GameInstallInfo.sqlite'
        if(-not (Test-Path -LiteralPath $db -PathType Leaf)){throw 'Database missing'}
        if(-not ('SteamNite.NativeSqlite' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'NativeSqlite.cs')}
        $rows=[SteamNite.NativeSqlite]::Read($db,'SELECT Id FROM DbSet WHERE Installed = 1;')
        $state.AmazonIds=@($rows|ForEach-Object {$_['Id']});$state.AmazonComplete=$true
    }catch{$notices.Add('Amazon: installed-game database could not be read.')}
    foreach($platform in @('GOG','Ubisoft','EA')){
        try{
            $snapshot=Get-LauncherRegistrySnapshot $platform
            $state.($platform+'Complete')=$snapshot.Complete
            $state.($platform+'Ids')=@(Get-UninstallRegistrationIds $snapshot $platform|Select-Object -Unique)
            if($platform -eq 'EA'){$state.EAComplete=$snapshot.Complete -and 'SOFTWARE\Origin Games' -in $snapshot.Roots}
            if(-not $state.($platform+'Complete')){$notices.Add($platform+': install registration cannot establish an uninstall. Preserved.')}
        }catch{$notices.Add($platform+': install records could not be read. Preserved.')}
    }
    $state.Notices=$notices.ToArray();return $state
}
function Get-UninstallPathState([string]$Path) {
    if($Path -notmatch '^[a-zA-Z]:[\\/]' -or -not [IO.Path]::IsPathRooted($Path)){return 'Unknown'}
    try{
        $root=[IO.Path]::GetPathRoot($Path)
        $drive=New-Object IO.DriveInfo($root)
        if(-not $drive.IsReady){return 'Unavailable'}
        [void][IO.File]::GetAttributes($root)
        try{[void][IO.File]::GetAttributes($Path);return 'Present'}
        catch [IO.FileNotFoundException]{return 'Missing'}
        catch [IO.DirectoryNotFoundException]{return 'Missing'}
        catch{return 'Unknown'}
    }catch{return 'Unavailable'}
}
function Get-ShortcutUninstallState($Shortcut,[object[]]$History,$Inventory) {
    $row=[pscustomobject]@{AppId=$Shortcut.AppId;Title=$Shortcut.Title;GameId='';Status='Keep';Reason='Manually added shortcut; protected from automatic cleanup. Explicit removal is available through Remove from Steam.'}
    if($Shortcut.ManagedId -notmatch '^steamnite:(xbox|epic|amazon|gog|ubisoft|ea):.+$'){return $row}
    $id=$Shortcut.ManagedId.Substring(10);$row.GameId=$id
    if($id -in @(Get-IgnoredGameIds)){$row.Reason='Ignored game; excluded from SteamNite changes.';return $row}
    $records=@($History|Where-Object {$_.Id -eq $id})
    $row.Status='Cannot verify'
    if($records.Count -ne 1 -or -not $records[0].InstallPath){$row.Reason='No unique previous install location is recorded. Preserved.';return $row}
    $location=Get-UninstallPathState $records[0].InstallPath
    if($location -eq 'Present'){$row.Status='Keep';$row.Reason='The recorded installation still exists (or is updating).';return $row}
    if($location -ne 'Missing'){$row.Reason='The install drive or path cannot be checked reliably. Preserved.';return $row}
    $registered=$true;$complete=$false
    switch -Regex ($id){
        '^xbox:'{$name=$id.Substring(5).Split(':')[0];$complete=$Inventory.XboxComplete;$registered=$name -in $Inventory.XboxNames;break}
        '^epic:'{$complete=$Inventory.EpicComplete;$registered=$id.Substring(5) -in $Inventory.EpicIds;break}
        '^amazon:'{$complete=$Inventory.AmazonComplete;$registered=$id.Substring(7) -in $Inventory.AmazonIds;break}
        '^gog:'{$complete=$Inventory.GOGComplete;$registered=$id.Substring(4) -in $Inventory.GOGIds;break}
        '^ubisoft:'{$complete=$Inventory.UbisoftComplete;$registered=$id.Substring(8) -in $Inventory.UbisoftIds;break}
        '^ea:'{
            $known=@($records[0].RemovalRegistryIds|Where-Object {$_})
            $complete=$Inventory.EAComplete -and $known.Count -gt 0
            $registered=@($known|Where-Object {$_ -in $Inventory.EAIds}).Count -gt 0
            break
        }
    }
    if(-not $complete){$row.Reason='The platform install records could not be checked. Preserved.';return $row}
    if($registered){$row.Status='Keep';$row.Reason='The platform still reports this game as installed, registered, or updating.';return $row}
    $row.Status='Removal candidate';$row.Reason='Installation path is missing on an available drive, and the platform no longer records this game as installed.'
    return $row
}
function New-SteamRemovalPlan {
    param($Profile,[string]$HistoryPath)
    $history=@();if(Test-Path -LiteralPath $HistoryPath){$history=@((Get-Content -LiteralPath $HistoryPath -Raw -Encoding UTF8|ConvertFrom-Json).Games)}
    $snapshot=Get-ShortcutSnapshot $Profile.ShortcutPath;$inventory=Get-UninstallInventory
    $rows=@(foreach($item in $snapshot.File.Items){Get-ShortcutUninstallState $item $history $inventory})
    # An app ID collision must never authorize removing either entry.
    foreach($group in @($rows|Group-Object AppId|Where-Object Count -gt 1)){foreach($row in $group.Group){$row.Status='Cannot verify';$row.Reason='Duplicate Steam shortcut IDs. Preserved.'}}
    [pscustomobject]@{Profile=$Profile;HistoryPath=$HistoryPath;OriginalHash=$snapshot.Hash;Shortcuts=$snapshot.File.Items.ToArray();Rows=$rows;Inventory=$inventory;Notices=$inventory.Notices;ScannedAt=(Get-Date).ToString('o')}
}
function Save-SteamRemovalPlan {
    param($Plan,[uint32[]]$SelectedAppIds)
    if(Test-SteamRunning){throw 'Steam must be closed before removing shortcuts.'}
    if(-not $SelectedAppIds.Count){throw 'Select at least one removal candidate.'}
    $path=[IO.Path]::GetFullPath($Plan.Profile.ShortcutPath)
    if([IO.Path]::GetFileName($path) -ne 'shortcuts.vdf'){throw 'Invalid shortcut destination.'}
    $snapshot=Get-ShortcutSnapshot $path
    if($snapshot.Hash -ne $Plan.OriginalHash){throw 'Steam shortcuts changed. Refresh the removal preview.'}
    $fresh=New-SteamRemovalPlan $Plan.Profile $Plan.HistoryPath
    foreach($id in $SelectedAppIds){
        $was=@($Plan.Rows|Where-Object {$_.AppId -eq $id -and $_.Status -eq 'Removal candidate'})
        $now=@($fresh.Rows|Where-Object {$_.AppId -eq $id -and $_.Status -eq 'Removal candidate'})
        if($was.Count -ne 1 -or $now.Count -ne 1 -or $was[0].GameId -ne $now[0].GameId){throw 'An uninstall could not be reconfirmed. Refresh the preview; nothing was removed.'}
    }
    $bytes=$snapshot.File.RemoveManaged($SelectedAppIds)
    $suffix=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $temp=$path+'.steamnite-remove-'+$suffix+'.tmp';$backup=$path+'.steamnite-remove-'+$suffix+'.bak'
    try{
        [IO.File]::WriteAllBytes($temp,$bytes)
        if((Test-SteamRunning) -or (Get-ShortcutSnapshot $path).Hash -ne $Plan.OriginalHash){throw 'Steam state changed. No shortcuts were removed.'}
        [IO.File]::Replace($temp,$path,$backup)
        [pscustomobject]@{Removed=$SelectedAppIds.Count;BackupPath=$backup;ShortcutPath=$path}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function New-ReviewedShortcutRemoval($Profile,[uint32[]]$AppIds) {
    if(-not $AppIds.Count -or @($AppIds|Select-Object -Unique).Count -ne $AppIds.Count){throw 'Select unique Steam shortcuts for removal.'}
    $snapshot=Get-ShortcutSnapshot $Profile.ShortcutPath
    $rows=@(foreach($id in $AppIds){
        $matches=@($snapshot.File.Items|Where-Object AppId -eq $id)
        if($matches.Count -ne 1){throw 'A selected shortcut is missing or ambiguous. Rescan and review again.'}
        $item=$matches[0];$manual=$item.ManagedId -notmatch '^steamnite:(xbox|epic|amazon|gog|ubisoft|ea):.+$'
        [pscustomobject]@{AppId=$id;Title=$item.Title;Manual=$manual;Reason=$(if($manual){'Manually added shortcut. Removal requires your explicit confirmation.'}else{'SteamNite shortcut. Only this Steam entry will be removed.'})}
    })
    [pscustomobject]@{Kind='Explicit shortcut removal';Profile=$Profile;OriginalHash=$snapshot.Hash;Rows=$rows;ManualCount=@($rows|Where-Object Manual).Count}
}
function Save-ReviewedShortcutRemoval($Plan,[bool]$Confirmed,[bool]$ConfirmManual=$false) {
    if($Plan.Kind -ne 'Explicit shortcut removal' -or -not $Confirmed){throw 'Review and confirm these shortcut removals first.'}
    if($Plan.ManualCount -gt 0 -and -not $ConfirmManual){throw 'The review includes manually added shortcuts. Explicit manual-removal confirmation is required.'}
    if(Test-SteamRunning){throw 'Steam must be closed before removing shortcuts.'}
    $path=[IO.Path]::GetFullPath($Plan.Profile.ShortcutPath)
    if([IO.Path]::GetFileName($path) -ne 'shortcuts.vdf'){throw 'Invalid shortcut destination.'}
    $snapshot=Get-ShortcutSnapshot $path
    if($snapshot.Hash -ne $Plan.OriginalHash){throw 'Steam shortcuts changed. Refresh and review the removal again.'}
    $ids=[uint32[]]@($Plan.Rows.AppId)
    if(-not $ids.Count){throw 'The removal review is empty.'}
    $bytes=$snapshot.File.RemoveReviewed($ids,$ConfirmManual)
    $suffix=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $temp=$path+'.steamnite-remove-'+$suffix+'.tmp';$backup=$path+'.steamnite-remove-'+$suffix+'.bak'
    try{
        [IO.File]::WriteAllBytes($temp,$bytes)
        if((Test-SteamRunning) -or (Get-ShortcutSnapshot $path).Hash -ne $Plan.OriginalHash){throw 'Steam state changed. No shortcuts were removed.'}
        [IO.File]::Replace($temp,$path,$backup)
        [pscustomobject]@{Removed=$ids.Count;BackupPath=$backup;ShortcutPath=$path}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
Export-ModuleMember -Function Update-GameInstallHistory,Get-UninstallInventory,Get-UninstallPathState,Get-ShortcutUninstallState,New-SteamRemovalPlan,Save-SteamRemovalPlan,New-ReviewedShortcutRemoval,Save-ReviewedShortcutRemoval
