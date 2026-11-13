# Headless, session-scoped operations. No UI assemblies, command evaluation or
# client-supplied plans/recipes. Secrets travel only through the private pipe.
param([Parameter(Mandatory)][string]$Workspace,[switch]$LibraryOnly)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$WarningPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
foreach($name in @('Core','Steam','Artwork','Removal','Library','Settings','Preparation','Workflow')){Import-Module (Join-Path $Workspace ('src\SteamNite.'+$name+'.psm1')) -Force}
Import-Module (Join-Path $Workspace 'src\SteamNite.Storage.psm1')
$script:data=if($LibraryOnly){Get-OathgateDataDirectory}else{Initialize-OathgateStorage -LegacyDirectory (Join-Path $Workspace 'data')};$script:settingsPath=Join-Path $script:data 'settings.json'
$script:state=@{Profile=$null;Games=@();Library=@();Plan=$null;Removal=$null;Worker=$null;Handle=$null;Activity=$null;Cancel=$null;Progress=$null;Key='';Matches=@();Sets=@{};Match=$null;Selections=@{};Art=$null}
function Read-NativeLibrary {
    if($script:state.Profile){
        $available=@(Get-SteamProfiles|Where-Object ShortcutPath -eq $script:state.Profile.ShortcutPath)
        if($available.Count -ne 1){throw 'The selected Steam account is no longer available. Choose an account again.'}
        $script:state.Profile=$available[0]
    }
    $settings=Get-AppSettings $script:settingsPath
    $scan=Get-GameScan -ExtraRoots @($settings.ExtraRoots)
    $script:state.Games=@($scan.Games)
    $removal=if($script:state.Profile){New-SteamRemovalPlan $script:state.Profile (Join-Path $script:data 'install-history.json')}else{$null}
    $script:state.Library=@(Get-UnifiedGameLibrary $scan.Games $script:state.Profile $removal (Join-Path $script:data 'install-history.json'))
}
function Select-NativeGames($ids,[string]$action){
    if(-not @($ids).Count -or @($ids).Count -gt 500){throw 'Select between 1 and 500 games.'}
    $request=[pscustomobject]@{Action=$action;GameIds=@($ids|Select-Object -Unique)}
    @(Resolve-WorkflowSelection $request $script:state.Library)
}
function Set-NativeProfile([string]$path){
    $profiles=@(Get-SteamProfiles);$found=@($profiles|Where-Object ShortcutPath -eq $path)
    if($found.Count -ne 1){throw 'Choose an available Steam account.'}
    $script:state.Profile=$found[0]
    $script:state.Plan=$null;$script:state.Art=$null;$script:state.Selections=@{};$script:state.Removal=$null;$script:state.RemoveIds=@();$script:state.Matches=@();$script:state.Match=$null;$script:state.Sets=@{}
}
function Assert-NativeIdle {if($script:state.Worker){throw 'Finish or stop the current operation first.'}}
function Get-NativeKey {if(-not $script:state.Key){$script:state.Key=Get-ArtworkApiKey $script:data};if(-not $script:state.Key){throw 'Enter a SteamGridDB API key.'};$script:state.Key}
function Get-NativeArtState {
    $rows=@(foreach($kind in @('Cover','Wide','Hero','Logo','Icon')){
        $paths=@(Get-ExistingArtwork $script:state.Art $kind)
        $path=if($paths.Count){$paths[0]}elseif($kind -eq 'Icon'){$script:state.Art.Icon.Trim('"')}else{''}
        @{Kind=$kind;Path=$path;Exists=[bool]$path;Queued=$script:state.Selections.ContainsKey($kind)}
    })
    @{AppId=$script:state.Art.AppId;Title=$script:state.Art.Game.Title;ProfileLabel=$script:state.Profile.Label;AccountId=$script:state.Profile.AccountId;Categories=$rows;Queued=@($script:state.Selections.Keys)}
}
function Get-NativePlanView($plan){
    @{Rows=@($plan.Rows|ForEach-Object {@{GameId=$_.GameId;Title=$_.Title;Action=$_.Action;Artwork=$_.Artwork;Detail=$_.Detail;Eligible=$_.Eligible;Current=$(if($_.Existing){$_.Existing.Exe+' | '+$_.Existing.StartDir+' | '+$_.Existing.LaunchOptions}else{''});Proposed=$(if($_.Draft){$_.Draft.Exe+' | '+$_.Draft.StartDir+' | '+$_.Draft.LaunchOptions}else{''})}});AddCount=$plan.AddCount;RepairCount=$plan.RepairCount;ArtworkCount=$plan.ArtworkCount;Profile=$plan.Profile.Label;IncludeArtwork=$plan.IncludeArtwork}
}
function Invoke-NativeOperation($request){
    if(@($request.PSObject.Properties|Where-Object Name -notin @('Operation','Data')).Count){throw 'Unsupported request fields.'}
    $d=$request.Data
    if($request.Operation -notin @('Poll','Stop','SteamState')){Assert-NativeIdle}
    switch([string]$request.Operation){
        'Setup'{
            $script:state.Profile=$null;$script:state.Plan=$null;$script:state.Removal=$null;$script:state.Art=$null
            $settings=Get-AppSettings $script:settingsPath -Recover;$profiles=@(Get-SteamProfiles)
            $path=if($d.Profile){[string]$d.Profile}else{[string]$settings.SteamShortcutPath}
            if($path){if(@($profiles|Where-Object ShortcutPath -eq $path).Count -eq 1){Set-NativeProfile $path}}elseif($profiles.Count -eq 1){Set-NativeProfile $profiles[0].ShortcutPath}
            Read-NativeLibrary
            @{Profiles=$profiles;Profile=$(if($script:state.Profile){$script:state.Profile.ShortcutPath}else{''});ExtraRoots=@($settings.ExtraRoots);AutomaticRoots=@(Get-AutomaticScanFolders);HasKey=[bool](Get-ArtworkApiKey $script:data)}
        }
        'Profile'{Set-NativeProfile ([string]$d.Profile);Read-NativeLibrary;@{Profile=$script:state.Profile.Label}}
        'SaveSettings'{
            if($d.PSObject.Properties.Name -contains 'ExtraRoots'){Save-AppSettings $script:settingsPath @{ExtraRoots=@(Get-NormalizedScanFolders @($d.ExtraRoots))}}
            if($d.PSObject.Properties.Name -contains 'Profile'){Set-NativeProfile ([string]$d.Profile);Save-AppSettings $script:settingsPath @{SteamShortcutPath=$script:state.Profile.ShortcutPath}}
            @{Detail='Settings saved.'}
        }
        'Key'{
            if($d.Forget){Remove-ArtworkApiKey $script:data;$script:state.Key=''}
            elseif($d.Key){$script:state.Key=[string]$d.Key;if($d.Remember){Set-ArtworkApiKey $script:data $script:state.Key}}
            @{HasKey=[bool]($script:state.Key -or (Get-ArtworkApiKey $script:data))}
        }
        'SteamState'{@{Running=(Test-SteamRunning)}}
        'ShutdownSteam'{if(-not $script:state.Profile){throw 'Choose a Steam account.'};Request-SteamShutdown $script:state.Profile;@{Detail='Requested normal Steam shutdown.'}}
        'OpenSteam'{if(-not $script:state.Profile){throw 'Choose a Steam account.'};if(-not (Test-SteamRunning)){Open-SteamClient $script:state.Profile};@{Detail='Steam opened.'}}
        'Launch'{Read-NativeLibrary;$games=@(Select-NativeGames $d.Ids 'Launch');Start-DetectedGame $games[0];@{Detail='Launch requested.'}}
        'Ignore'{Read-NativeLibrary;$games=@(Select-NativeGames $d.Ids $(if($d.Ignored){'Ignore'}else{'Unignore'}));Set-GameIgnored -GameIds @($games.NativeGameId) -Ignored ([bool]$d.Ignored);@{Detail='Exclusions saved.'}}
        'LaunchInfo'{Read-NativeLibrary;$g=@(Select-NativeGames $d.Ids 'EditLaunch')[0];$detected=if($g.DetectedGame){$g.DetectedGame}else{$g};@{Title=$g.Title;DetectedMethod=$detected.Method;DetectedTarget=$detected.Target;Executable=$(if($g.HasLaunchOverride -or $g.Method -eq 'Xbox launch helper'){$g.Target}else{''});WorkingDirectory=$(if($g.HasLaunchOverride){$g.LaunchWorkingDirectory}else{$g.InstallPath});Arguments=$(if($g.HasLaunchOverride){$g.Arguments}else{''})}}
        'SaveLaunch'{Read-NativeLibrary;$g=@(Select-NativeGames $d.Ids 'EditLaunch')[0];Set-GameLaunchOverride -GameId $g.Id -Executable ([string]$d.Executable) -WorkingDirectory ([string]$d.WorkingDirectory) -Arguments ([string]$d.Arguments) -Reset:([bool]$d.Reset);@{Detail='Launch settings saved. Prepare in Steam to review the shortcut update.'}}
        'Preview'{
            if(-not $script:state.Profile){throw 'Choose a Steam account.'}
            Read-NativeLibrary
            $games=@(if($d.All){$script:state.Library|Where-Object {$_.InstallState -eq 'Installed' -and -not $_.Ignored -and $_.SteamSyncStatus -eq 'Synced'}}else{Select-NativeGames $d.Ids 'Prepare'})
            if(-not $games.Count){throw 'No eligible games are available.'}
            $script:state.Plan=New-SteamPreparationPlan $script:state.Profile $games ([bool]$d.Artwork)
            Get-NativePlanView $script:state.Plan
        }
        'StartPrepare'{
            $plan=$script:state.Plan;if(-not $plan){throw 'Refresh the preview first.'}
            Read-NativeLibrary;$current=@(Select-NativeGames @($plan.Games.Id) 'Prepare')
            $fresh=New-SteamPreparationPlan $script:state.Profile $current $plan.IncludeArtwork
            if((Get-PreparationSignature $fresh) -ne (Get-PreparationSignature $plan) -or $fresh.SyncPlan.OriginalHash -ne $plan.SyncPlan.OriginalHash){$script:state.Plan=$null;throw 'The preview changed. Refresh and review before applying.'}
            if(Test-SteamRunning){throw 'Steam must be fully closed.'}
            $key=if($plan.IncludeArtwork -and $plan.ArtworkCount -gt 0){Get-NativeKey}else{''}
            Save-AppSettings $script:settingsPath @{SteamShortcutPath=$script:state.Profile.ShortcutPath}
            Update-GameInstallHistory (Join-Path $script:data 'install-history.json') $script:state.Games
            $script:state.Cancel=[hashtable]::Synchronized(@{Stop=$false});$script:state.Progress=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]';$script:state.Activity=$null
            $worker=[PowerShell]::Create()
            [void]$worker.AddScript({param($module,$plan,$data,$key,$cancel,$progress) $ErrorActionPreference='Stop';Import-Module $module -Force;Invoke-SteamPreparation $plan $data $key $cancel $progress}).AddArgument((Join-Path $Workspace 'src\SteamNite.Preparation.psm1')).AddArgument($fresh).AddArgument($script:data).AddArgument($key).AddArgument($script:state.Cancel).AddArgument($script:state.Progress)
            try{$handle=$worker.BeginInvoke();$script:state.Worker=$worker;$script:state.Handle=$handle}catch{$worker.Dispose();throw}
            @{Running=$true}
        }
        'Poll'{
            $update=$null
            if($script:state.Progress){while($script:state.Progress.TryDequeue([ref]$update)){$script:state.Activity=$update|ConvertFrom-Json}}
            if($script:state.Handle -and $script:state.Handle.IsCompleted){
                $worker=$script:state.Worker
                try{$result=@($worker.EndInvoke($script:state.Handle));if($worker.HadErrors -or -not $result.Count){throw 'Operation stopped unexpectedly. Check Activity history before retrying.'};$script:state.Activity=$result[-1]}
                finally{$worker.Dispose();$script:state.Worker=$null;$script:state.Handle=$null}
            }
            @{Running=[bool]$script:state.Worker;Activity=$script:state.Activity}
        }
        'Stop'{if($script:state.Cancel){$script:state.Cancel.Stop=$true};@{Detail='Stopping after the current step finishes safely.'}}
        'History'{@{Activities=@(Get-PreparationActivities $script:data)}}
        'Retry'{
            $activity=@(Get-PreparationActivities $script:data|Where-Object Id -eq $d.Id)
            if($activity.Count -ne 1 -or -not $activity[0].Profile){throw 'The original activity is unavailable.'}
            Set-NativeProfile $activity[0].Profile.ShortcutPath;Read-NativeLibrary
            $games=@(Get-PreparationRetryGames $activity[0] $script:state.Library $script:state.Profile)
            if(-not $games.Count){throw 'No unfinished games are currently installed.'}
            $script:state.Plan=New-SteamPreparationPlan $script:state.Profile $games ([bool]$activity[0].IncludeArtwork)
            Get-NativePlanView $script:state.Plan
        }
        'RemovalPreview'{
            Read-NativeLibrary;$games=@(Select-NativeGames $d.Ids 'ExplicitRemove')
            $ids=@($games.SteamAppId);$script:state.RemoveIds=$ids
            $script:state.Removal=New-ReviewedShortcutRemoval $script:state.Profile $ids
            @{Rows=$script:state.Removal.Rows;ManualCount=$script:state.Removal.ManualCount;Profile=$script:state.Profile.Label}
        }
        'Remove'{
            if(-not $script:state.Removal -or -not $d.Confirmed){throw 'Review and confirm the removal first.'}
            Read-NativeLibrary
            foreach($id in $script:state.RemoveIds){$g=@($script:state.Library|Where-Object {$_.SteamAppId -eq $id -and $_.CanRemoveExplicitly -and -not $_.Ignored});if($g.Count -ne 1){throw 'Removal eligibility changed. Refresh and review again.'}}
            $result=Save-ReviewedShortcutRemoval $script:state.Removal ([bool]$d.Confirmed) ([bool]$d.ConfirmManual);$script:state.Removal=$null;$result
        }
        'ArtContext'{
            Read-NativeLibrary;$g=@(Select-NativeGames $d.Ids 'Artwork')[0]
            $script:state.Art=Get-SteamArtworkContext $script:state.Profile $g;$script:state.Selections=@{};$script:state.Match=$null;$script:state.Sets=@{}
            Get-NativeArtState
        }
        'ArtSearch'{
            $script:state.Match=$null;$script:state.Sets=@{};$script:state.Selections=@{}
            $script:state.Matches=@(Search-ArtworkGames ([string]$d.Query) (Get-NativeKey));$savedId=0
            if($script:state.Art){$path=Join-Path $script:data ('artwork-'+$script:state.Art.AppId+'.json');if(Test-Path -LiteralPath $path){try{$saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;if($saved.GameId -eq $script:state.Art.Game.Id){$savedId=[long]$saved.SgdbId}}catch{}}}
            @{Matches=@($script:state.Matches|Select-Object id,name);Index=(Get-LikelyArtworkMatchIndex ([string]$d.Query) $script:state.Matches $savedId);State=(Get-NativeArtState)}
        }
        'ArtCandidates'{
            $matches=@($script:state.Matches|Where-Object id -eq $d.MatchId);if($matches.Count -ne 1){throw 'Choose a current game match.'}
            if(-not $script:state.Match -or $script:state.Match.id -ne $d.MatchId){$script:state.Selections=@{};$script:state.Sets=@{}}
            $script:state.Match=$matches[0];$kind=[string]$d.Kind
            if($kind -notin @('Cover','Wide','Hero','Logo','Icon')){throw 'Unknown artwork category.'}
            if(-not $script:state.Sets.ContainsKey($kind)){$sets=Get-ArtworkCandidates $d.MatchId (Get-NativeKey) $kind;$script:state.Sets[$kind]=@($sets[$kind])}
            $assets=@($script:state.Sets[$kind])
            @{Assets=@(foreach($asset in $assets){@{Id=$asset.id;Author=$asset.author.name;Width=$asset.width;Height=$asset.height}});State=(Get-NativeArtState)}
        }
        'ArtThumbnail'{
            $assets=@($script:state.Sets[[string]$d.Kind]|Where-Object id -eq $d.AssetId);if($assets.Count -ne 1){throw 'Select a current artwork image.'}
            $thumb=@(Get-ArtworkThumbnails $assets (Join-Path $script:data 'artwork-cache'))|Select-Object -First 1
            @{Path=$thumb.Path}
        }
        'ArtImage'{
            $assets=@($script:state.Sets[[string]$d.Kind]|Where-Object id -eq $d.AssetId);if($assets.Count -ne 1){throw 'Select a current artwork image.'}
            $asset=$assets[0];$path=Get-CachedArtwork $asset (Join-Path $script:data 'artwork-cache')
            if($d.Queue){$script:state.Selections[[string]$d.Kind]=[pscustomobject]@{Path=$path;AssetId=$asset.id;Url=$asset.url;Author=$asset.author.name}}
            @{Path=$path;State=(Get-NativeArtState)}
        }
        'ArtClear'{$script:state.Selections=@{};Get-NativeArtState}
        'ArtApply'{
            if($d.RecommendAll -and (-not $d.ConfirmRecommended -or $d.Fill)){throw 'Confirm replacement of existing artwork before applying all recommendations.'}
            if(-not $script:state.Art -or -not $script:state.Match){throw 'Choose artwork first.'}
            Read-NativeLibrary;$g=@(Select-NativeGames @($script:state.Art.Game.Id) 'Artwork')[0]
            $fresh=Get-SteamArtworkContext $script:state.Profile $g
            if($fresh.AppId -ne $script:state.Art.AppId){throw 'The Steam shortcut changed. Reopen artwork to review.'}
            if($d.Fill -or $d.RecommendAll){$sets=Get-ArtworkCandidates $script:state.Match.id (Get-NativeKey);$recommended=Get-RecommendedArtwork $sets $fresh (Join-Path $script:data 'artwork-cache') -ReplaceExisting:([bool]$d.RecommendAll);$selections=$recommended.Selections}else{$selections=$script:state.Selections}
            $result=Save-SteamArtwork $fresh $selections -Replace:(-not [bool]$d.Fill)
            @{GameId=$g.Id;SteamAppId=$fresh.AppId;SgdbId=$script:state.Match.id;SgdbTitle=$script:state.Match.name;Assets=$selections;AppliedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $script:data ('artwork-'+$fresh.AppId+'.json')) -Encoding UTF8
            $script:state.Art=Get-SteamArtworkContext $script:state.Profile $g;$script:state.Selections=@{}
            @{Result=$result;State=(Get-NativeArtState);Unavailable=$(if($d.Fill -or $d.RecommendAll){@($recommended.Unavailable)}else{@()})}
        }
        default{throw 'Unsupported native operation.'}
    }
}
if($LibraryOnly){return}
try{
    while($null -ne ($line=[Console]::ReadLine())){
        try{
            if($line.Length -gt 1MB){throw 'Request exceeds size limit.'}
            try{$request=$line|ConvertFrom-Json}catch{throw 'Invalid native request JSON.'}
            $result=Invoke-NativeOperation $request
            $response=@{Ok=$true;Data=$result}|ConvertTo-Json -Depth 16 -Compress
        }catch{
            $message=$_.Exception.GetBaseException().Message
            if($script:state.Key){$message=$message.Replace($script:state.Key,'[redacted]')}
            if($request.Data.Key){$message=$message.Replace([string]$request.Data.Key,'[redacted]')}
            if($message.Length -gt 4000){$message=$message.Substring(0,4000)+'…'}
            $response=@{Ok=$false;Error=$message}|ConvertTo-Json -Compress
        }
        [Console]::WriteLine($response);[Console]::Out.Flush()
    }
}finally{
    if($script:state.Worker){$script:state.Cancel.Stop=$true;try{[void]$script:state.Worker.EndInvoke($script:state.Handle)}finally{$script:state.Worker.Dispose()}}
    $script:state.Key=''
}
