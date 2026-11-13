$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Steam.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Artwork.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Removal.psm1')
function Find-HistoricalManualGame($Shortcut,[object[]]$History) {
    # Display-only association by an exact, game-specific executable and args.
    # Never infer ownership or match by title/shared launcher executable.
    $matches=@($History|Where-Object {
        $_.Method -in @('Xbox launch helper','GOG executable','Custom executable') -and
        $_.Target -and $_.InstallPath -and
        $_.Target.Trim('"') -eq $Shortcut.Exe.Trim('"') -and
        [string]$_.Arguments -ceq [string]$Shortcut.LaunchOptions
    })
    if($matches.Count -eq 1){return $matches[0]}
}
function Get-LibraryArtworkState($Profile,$AppId,$Shortcut) {
    if(-not $Profile){return [pscustomobject]@{Text='No profile';Missing=@();Detail='Choose a Steam account.'}}
    if($null -eq $AppId){return [pscustomobject]@{Text='Not linked';Missing=@();Detail='A unique Steam shortcut is required to check artwork.'}}
    $context=[pscustomobject]@{AppId=$AppId;GridDirectory=(Join-Path (Split-Path $Profile.ShortcutPath) 'grid')}
    try{
        $missing=@(foreach($kind in @('Cover','Wide','Hero','Logo','Icon')){
            $exists=@(Get-ExistingArtwork $context $kind).Count -gt 0
            # Custom icon references are occupied slots, even on an offline drive;
            # artwork application deliberately preserves these references too.
            if($kind -eq 'Icon' -and $Shortcut -and $Shortcut.Icon){$exists=$true}
            if(-not $exists){$kind}
        })
        return [pscustomobject]@{Text=('{0}/5' -f (5-$missing.Count));Missing=$missing;Detail=$(if($missing.Count){'Missing: '+($missing -join ', ')}else{'All five artwork categories are present.'})}
    }catch{return [pscustomobject]@{Text='Unknown';Missing=@();Detail=('Artwork could not be checked: '+$_.Exception.Message)}}
}
function Test-LibraryAttentionFilter($Game,[string]$Filter) {
    switch($Filter){
        'Needs attention'{return [bool]$Game.NeedsAttention}
        'Not in Steam'{return $Game.InstallState -eq 'Installed' -and $Game.SteamSyncStatus -eq 'Not synced' -and -not $Game.Ignored}
        'Needs repair'{return $Game.SteamSyncStatus -eq 'Needs repair' -and -not $Game.Ignored}
        'Missing artwork'{return @($Game.MissingArtwork).Count -gt 0 -and $Game.InstallState -eq 'Installed' -and -not $Game.Ignored}
        'Ignored'{return [bool]$Game.Ignored}
        default{return $true}
    }
}
function Get-UnifiedGameLibrary {
    param([object[]]$InstalledGames,$Profile=$null,$RemovalPlan=$null,[string]$HistoryPath='')
    $history=@();if($HistoryPath -and (Test-Path -LiteralPath $HistoryPath)){$history=@((Get-Content -LiteralPath $HistoryPath -Raw -Encoding UTF8|ConvertFrom-Json).Games)}
    $states=@{};foreach($state in @(Get-GameSteamStatuses -Games $InstalledGames -Profile $Profile)){$states[$state.GameId]=$state}
    $games=New-Object 'System.Collections.Generic.List[object]';$installedIds=@{};$usedIndexes=@{}
    foreach($game in $InstalledGames){
        $installedIds[$game.Id]=$true;$state=$states[$game.Id]
        $copy=Get-EffectiveGameLaunch $game
        $copy|Add-Member -Force NoteProperty InstallState 'Installed'
        $copy|Add-Member -Force NoteProperty SteamSyncStatus $state.Status
        $copy|Add-Member -Force NoteProperty SteamSyncDetail $state.Detail
        $copy|Add-Member -Force NoteProperty CanRemove $false
        $copy|Add-Member -Force NoteProperty SteamAppId $state.AppId
        $copy|Add-Member -Force NoteProperty NativeGameId $game.Id
        $games.Add($copy)
        if($RemovalPlan){foreach($shortcut in $RemovalPlan.Shortcuts){if($shortcut.ManagedId -eq ('steamnite:'+$game.Id) -or ($null -ne $state.AppId -and $shortcut.AppId -eq $state.AppId)){$usedIndexes[$shortcut.Index]=$true}}}
    }
    if($RemovalPlan){foreach($shortcut in $RemovalPlan.Shortcuts){
        if($usedIndexes.ContainsKey($shortcut.Index)){continue}
        $managed=$shortcut.ManagedId -match '^steamnite:(xbox|epic|amazon|gog|ubisoft|ea):.+$'
        $id=if($managed){$shortcut.ManagedId.Substring(10)}else{''}
        if($id -and $installedIds.ContainsKey($id)){continue}
        $checks=@($RemovalPlan.Rows|Where-Object {$_.AppId -eq $shortcut.AppId})
        $check=if($checks.Count -eq 1){$checks[0]}else{$null}
        $historical=$null
        if(-not $managed -and $RemovalPlan.Inventory){
            $historical=Find-HistoricalManualGame $shortcut $history
            if($historical){
                $id=$historical.Id
                $displayShortcut=[pscustomobject]@{AppId=$shortcut.AppId;Title=$shortcut.Title;ManagedId=('steamnite:'+$id)}
                $check=Get-ShortcutUninstallState $displayShortcut $history $RemovalPlan.Inventory
            }
        }
        $canRemove=$managed -and $null -ne $check -and $check.Status -eq 'Removal candidate'
        $installState=if($canRemove -or ($historical -and $check.Status -eq 'Removal candidate')){'Not installed'}elseif(-not $managed -and -not $historical){'Manual shortcut'}elseif($check -and $check.Status -eq 'Keep'){'Not detected'}else{'Unverified'}
        $reason=if($check){$check.Reason}else{'The Steam shortcut could not be verified. Preserved.'}
        if($historical){$reason+=' This manually added shortcut is protected from automatic cleanup. Use Remove from Steam for explicit removal.'}
        $records=@($history|Where-Object {$_.Id -eq $id})
        $path=if($records.Count -eq 1){$records[0].InstallPath}else{$shortcut.StartDir.Trim('"')}
        $platform=if($id -like 'xbox:*'){'Xbox'}elseif($id -like 'epic:*'){'Epic'}elseif($id -like 'amazon:*'){'Amazon'}elseif($id -like 'gog:*'){'GOG'}elseif($id -like 'ubisoft:*'){'Ubisoft'}elseif($id -like 'ea:*'){'EA'}else{'Manual'}
        $games.Add([pscustomobject]@{
            Id=('steam:'+$shortcut.AppId+':'+$shortcut.Index);Title=$shortcut.Title;Platform=$platform;InstallPath=$path
            Method='Steam shortcut';Target='';Arguments='';Status=$installState;Evidence=('Steam shortcut '+$shortcut.AppId);Note=$reason
            InstallState=$installState;SteamSyncStatus='Synced';SteamSyncDetail=$reason;SteamAppId=$shortcut.AppId;NativeGameId=$(if($managed){$id}else{''});CanRemove=$canRemove
        })
    }}
    $ignored=@(Get-IgnoredGameIds)
    $shortcuts=if($RemovalPlan){@($RemovalPlan.Shortcuts)}elseif($Profile){@((Get-ShortcutSnapshot $Profile.ShortcutPath).File.Items)}else{@()}
    foreach($game in $games){
        $isIgnored=$game.NativeGameId -and $game.NativeGameId -in $ignored
        $game|Add-Member -Force NoteProperty Ignored ([bool]$isIgnored)
        if($isIgnored){$game.CanRemove=$false;$game.SteamSyncStatus='Ignored';$game.SteamSyncDetail='Excluded from SteamNite changes. Unignore to resume management.'}
        $shortcut=@($shortcuts|Where-Object {$_.AppId -eq $game.SteamAppId})
        $game|Add-Member -Force NoteProperty CanRemoveExplicitly ([bool]($Profile -and $null -ne $game.SteamAppId -and $shortcut.Count -eq 1 -and -not $isIgnored))
        $art=Get-LibraryArtworkState $Profile $game.SteamAppId $(if($shortcut.Count -eq 1){$shortcut[0]}else{$null})
        $game|Add-Member -Force NoteProperty ArtworkStatus $art.Text
        $game|Add-Member -Force NoteProperty MissingArtwork @($art.Missing)
        $game|Add-Member -Force NoteProperty ArtworkDetail $art.Detail
        $reasons=@()
        if(-not $isIgnored){
            if($game.CanRemove){$reasons+='Uninstalled shortcut can be removed.'}
            if($game.InstallState -in @('Unverified','Not detected')){$reasons+=$game.Note}
            if($game.InstallState -eq 'Installed'){
                if($game.Status -ne 'Ready to test'){$reasons+='Launch configuration needs attention.'}
                if($game.SteamSyncStatus -ne 'Synced'){$reasons+=$game.SteamSyncDetail}
                if($art.Missing.Count -or $art.Text -eq 'Unknown'){$reasons+=$art.Detail}
            }
        }
        $game|Add-Member -Force NoteProperty NeedsAttention ($reasons.Count -gt 0)
        $detail=$reasons -join ' '
        if(-not $detail -and $game.InstallState -eq 'Not installed' -and -not $game.CanRemove){$detail=$game.Note}
        $game|Add-Member -Force NoteProperty AttentionDetail $detail
    }
    return @($games|Sort-Object Title,Platform,Id)
}
Export-ModuleMember -Function Get-UnifiedGameLibrary, Get-LibraryArtworkState, Test-LibraryAttentionFilter
