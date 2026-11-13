$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Steam.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Library.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.BulkArtwork.psm1')

function New-SteamPreparationPlan {
    param($Profile,[object[]]$Games,[bool]$IncludeArtwork=$true)
    $installed=@($Games|Where-Object {-not $_.InstallState -or $_.InstallState -eq 'Installed'})
    if($installed.Count -ne $Games.Count){throw 'Prepare in Steam accepts installed games only. Removal remains a separate reviewed action.'}
    $sync=New-SteamSyncPlan -Profile $Profile -Games $Games
    $statuses=@(Get-GameSteamStatuses $Games $Profile)
    $snapshot=Get-ShortcutSnapshot $Profile.ShortcutPath
    $rows=@(foreach($row in $sync.Rows){
        $state=@($statuses|Where-Object GameId -eq $row.GameId)[0]
        $eligible=$row.Action -in @('Add','Repair') -or ($row.Action -eq 'Keep existing' -and $state.Status -eq 'Synced')
        $art='Skipped';$missing=@();$detail=$row.Reason
        if($eligible -and $IncludeArtwork){
            if($row.Action -eq 'Add'){$art='Fill after adding';$missing=@('Cover','Wide','Hero','Logo','Icon')}
            else{
                $shortcut=@($snapshot.File.Items|Where-Object AppId -eq $state.AppId)
                $coverage=Get-LibraryArtworkState $Profile $state.AppId $(if($shortcut.Count -eq 1){$shortcut[0]}else{$null})
                $missing=@($coverage.Missing)
                $art=if($coverage.Text -eq 'Unknown'){'Check artwork'}elseif($missing.Count){'Fill '+$missing.Count+' missing'}else{'Complete'}
                $detail+=' '+$coverage.Detail
            }
        }
        if($row.Action -eq 'Keep existing' -and -not $eligible){$detail=$state.Detail}
        [pscustomobject]@{GameId=$row.GameId;Title=$row.Title;Action=$row.Action;Artwork=$art;Missing=$missing;Eligible=$eligible;Detail=$detail.Trim();Draft=$row.Draft;Existing=$row.Existing}
    })
    [pscustomobject]@{Profile=$Profile;Games=$Games;IncludeArtwork=$IncludeArtwork;SyncPlan=$sync;Rows=$rows;AddCount=$sync.AddCount;RepairCount=$sync.RepairCount;ArtworkCount=@($rows|Where-Object {$_.Eligible -and $_.Artwork -notin @('Complete','Skipped')}).Count}
}
function Get-PreparationSignature($Plan) {
    [pscustomobject]@{Profile=$Plan.Profile.ShortcutPath;Sync=(Get-SteamPlanChangeSignature $Plan.SyncPlan);Artwork=$Plan.IncludeArtwork;Rows=@($Plan.Rows|Select-Object GameId,Artwork,Missing,Eligible)}|ConvertTo-Json -Depth 7 -Compress
}
function Save-PreparationActivity {
    param($Activity,[string]$DataDirectory)
    $directory=Join-Path $DataDirectory 'operations';[void][IO.Directory]::CreateDirectory($directory)
    if($Activity.Id -notmatch '^[a-f0-9]{32}$'){throw 'Invalid activity identity.'}
    $path=Join-Path $directory ($Activity.Id+'.json');$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $Activity|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Get-PreparationActivities([string]$DataDirectory) {
    $directory=Join-Path $DataDirectory 'operations'
    if(-not (Test-Path -LiteralPath $directory)){return @()}
    foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File|Sort-Object LastWriteTimeUtc -Descending)){
        try{
            $activity=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            if($activity.Id -notmatch '^[a-f0-9]{32}$' -or $activity.Kind -ne 'Prepare in Steam'){continue}
            # Running records from a previous session may have committed changes.
            # Retry always replans against current Steam files; never replay bytes.
            if($activity.Status -eq 'Running'){$activity.Status='Interrupted';$activity.Detail='The previous operation did not record completion. Check current state; retry safely replans unfinished games.'}
            $activity
        }catch{[pscustomobject]@{Id='';Kind='Prepare in Steam';StartedAt=$file.LastWriteTimeUtc.ToString('o');Status='Unreadable';Detail=('Activity file could not be read: '+$file.Name);Rows=@();Profile=$null;IncludeArtwork=$false}}
    }
}
function Get-PreparationRetryGames {
    param($Activity,[object[]]$InstalledGames,$Profile)
    if(-not $Activity.Profile -or $Profile.ShortcutPath -ne $Activity.Profile.ShortcutPath){throw 'Retry requires the original Steam account.'}
    $ids=@($Activity.Rows|Where-Object {$_.Status -notin @('Complete','Ignored')}|ForEach-Object {$_.GameId})
    # Only current discoveries can be retried. Removed games and stale stored
    # executable paths are never restored from history.
    return @($InstalledGames|Where-Object {$_.Id -in $ids -and (-not $_.InstallState -or $_.InstallState -eq 'Installed') -and -not $_.Ignored})
}
function Send-PreparationProgress($Activity,$Progress) {
    if($null -ne $Progress){$Progress.Enqueue(($Activity|ConvertTo-Json -Depth 9 -Compress))}
}
function Invoke-SteamPreparation {
    param($Plan,[string]$DataDirectory,[string]$ApiKey='',$Cancellation=$null,$Progress=$null)
    if(Test-SteamRunning){throw 'Steam must be closed before preparing games.'}
    $fresh=New-SteamPreparationPlan -Profile $Plan.Profile -Games $Plan.Games -IncludeArtwork $Plan.IncludeArtwork
    if($fresh.SyncPlan.OriginalHash -ne $Plan.SyncPlan.OriginalHash -or (Get-PreparationSignature $fresh) -ne (Get-PreparationSignature $Plan)){throw 'The preview changed. Review a fresh preview before applying.'}
    if($Plan.IncludeArtwork -and $Plan.ArtworkCount -gt 0 -and [string]::IsNullOrWhiteSpace($ApiKey)){throw 'Enter a SteamGridDB key or turn off recommended artwork before applying.'}
    $activity=[pscustomobject]@{
        Id=[guid]::NewGuid().ToString('N');Kind='Prepare in Steam';StartedAt=[datetime]::UtcNow.ToString('o');FinishedAt='';Status='Running';Detail='Preparing shortcuts.'
        Profile=[pscustomobject]@{AccountId=$Plan.Profile.AccountId;SteamRoot=$Plan.Profile.SteamRoot;ShortcutPath=$Plan.Profile.ShortcutPath}
        IncludeArtwork=$Plan.IncludeArtwork;Added=0;Repaired=0;ImagesAdded=0;BackupPath=''
        Rows=@($Plan.Rows|ForEach-Object {[pscustomobject]@{GameId=$_.GameId;Title=$_.Title;Action=$_.Action;Shortcut='Pending';Artwork='Pending';Status='Pending';Detail=$_.Detail;ImagesAdded=0}})
    }
    # A durable intent record must exist before touching any Steam file.
    Save-PreparationActivity $activity $DataDirectory
    $stop=$false
    try{
        if($Cancellation -and $Cancellation.Stop){$stop=$true}
        else{
            $saved=Save-SteamSyncPlan $fresh.SyncPlan
            $activity.Added=$saved.Added;$activity.Repaired=$saved.Repaired;$activity.BackupPath=$saved.BackupPath
            foreach($row in $activity.Rows){
                $preview=@($fresh.Rows|Where-Object GameId -eq $row.GameId)[0]
                if($preview.Action -eq 'Ignored'){$row.Shortcut='Ignored';$row.Artwork='Skipped';$row.Status='Ignored'}
                elseif(-not $preview.Eligible){$row.Shortcut='Needs attention';$row.Artwork='Skipped';$row.Status='Blocked'}
                else{$row.Shortcut=switch($preview.Action){'Add'{'Added'}'Repair'{'Repaired'}default{'Current'}}}
            }
            $activity.Detail='Shortcuts checked. Filling missing recommended artwork.'
            Save-PreparationActivity $activity $DataDirectory;Send-PreparationProgress $activity $Progress
        }
        foreach($row in $activity.Rows){
            if($row.Status -in @('Ignored','Blocked')){continue}
            if($stop -or ($Cancellation -and $Cancellation.Stop)){$stop=$true;$row.Status='Cancelled';$row.Artwork='Not attempted';$row.Detail='Stopped before artwork processing. Retry checks the current shortcut and fills only remaining artwork.';continue}
            if(Test-SteamRunning){$stop=$true;$row.Status='Stopped';$row.Artwork='Not attempted';$row.Detail='Steam started during preparation. Remaining writes were stopped.';continue}
            $preview=@($fresh.Rows|Where-Object GameId -eq $row.GameId)[0]
            if(-not $Plan.IncludeArtwork){$row.Artwork='Skipped';$row.Status='Complete';$row.Detail='Shortcut is ready; artwork was not requested.'}
            elseif($preview.Artwork -eq 'Complete'){$row.Artwork='Complete';$row.Status='Complete';$row.Detail='Shortcut and all five artwork categories are already configured.'}
            else{
                $activity.Detail='Artwork: '+$row.Title;Send-PreparationProgress $activity $Progress
                $game=@($Plan.Games|Where-Object Id -eq $row.GameId)[0]
                $art=Invoke-BulkArtworkGame -Game $game -Profile $Plan.Profile -DataDirectory $DataDirectory -ApiKey $ApiKey
                $row.Artwork=$art.Status;$row.ImagesAdded=$art.Added;$activity.ImagesAdded+=$art.Added
                $row.Status=if($art.Status -in @('Applied','Complete')){'Complete'}elseif($art.Status -eq 'Ignored'){'Ignored'}else{$art.Status}
                $row.Detail=$art.Detail
                if($ApiKey){$row.Detail=$row.Detail.Replace($ApiKey,'[redacted]')}
                if($art.StopBatch){$stop=$true}
            }
            Save-PreparationActivity $activity $DataDirectory;Send-PreparationProgress $activity $Progress
        }
        $remaining=@($activity.Rows|Where-Object {$_.Status -notin @('Complete','Ignored')}).Count
        $activity.Status=if($stop){'Stopped'}elseif($remaining){'Needs attention'}else{'Complete'}
        $activity.Detail=('{0} added; {1} repaired; {2} images added; {3} game(s) need attention.' -f $activity.Added,$activity.Repaired,$activity.ImagesAdded,$remaining)
    }catch{
        $activity.Status='Failed';$detail=$_.Exception.GetBaseException().Message
        if($ApiKey){$detail=$detail.Replace($ApiKey,'[redacted]')}
        $activity.Detail=$detail
        foreach($row in $activity.Rows|Where-Object Status -eq 'Pending'){$row.Status='Failed';$row.Detail='Operation stopped. '+$detail}
    }
    $activity.FinishedAt=[datetime]::UtcNow.ToString('o')
    # Never persist credentials or original game objects/launch arguments.
    if($ApiKey){$activity.Detail=$activity.Detail.Replace($ApiKey,'[redacted]');foreach($row in $activity.Rows){$row.Detail=$row.Detail.Replace($ApiKey,'[redacted]')}}
    Save-PreparationActivity $activity $DataDirectory;Send-PreparationProgress $activity $Progress
    return $activity
}
Export-ModuleMember -Function New-SteamPreparationPlan, Get-PreparationSignature, Invoke-SteamPreparation, Get-PreparationActivities, Get-PreparationRetryGames
