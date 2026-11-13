$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Preparation.psm1') -Force
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\preparation-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$data=Join-Path $root 'data';$prefs=Join-Path $root 'preferences.json'
$steam=Get-Module SteamNite.Steam;$module=Get-Module SteamNite.Preparation
& $steam {param($path) $script:preferences=$path;function script:Get-GamePreferencesPath {$script:preferences};function script:Test-SteamRunning {$false}} $prefs
$state=@{Calls=(New-Object 'System.Collections.Generic.List[string]');Statuses=@{};Cancel=$null;StopAfter='';Running=$false}
& $module {
    param($state)
    $script:fixture=$state
    function script:Test-SteamRunning {$script:fixture.Running}
    function script:Invoke-BulkArtworkGame {
        param($Game,$Profile,$DataDirectory,$ApiKey)
        $script:fixture.Calls.Add($Game.Id)
        $status=if($script:fixture.Statuses.ContainsKey($Game.Id)){$script:fixture.Statuses[$Game.Id]}else{'Applied'}
        if($Game.Id -eq $script:fixture.StopAfter){$script:fixture.Cancel.Stop=$true}
        if($status -eq 'Throw'){throw ('Synthetic error '+$ApiKey)}
        if($status -eq 'Applied'){
            $snapshot=Get-ShortcutSnapshot $Profile.ShortcutPath
            $id=@($snapshot.File.Items|Where-Object ManagedId -eq ('steamnite:'+$Game.Id))[0].AppId
            $grid=Join-Path (Split-Path $Profile.ShortcutPath) 'grid';[void][IO.Directory]::CreateDirectory($grid)
            foreach($suffix in @('p','','_hero','_logo','_icon')){[IO.File]::WriteAllBytes((Join-Path $grid ($id.ToString()+$suffix+'.png')),[byte[]]@(1))}
        }
        [pscustomobject]@{GameId=$Game.Id;Title=$Game.Title;Status=$status;Detail=('Synthetic artwork result '+$status+' '+$ApiKey);Added=$(if($status -eq 'Applied'){5}else{0});StopBatch=($status -eq 'Failed')}
    }
} $state
function Profile($Name){$path=Join-Path $root $Name;[void][IO.Directory]::CreateDirectory($path);[pscustomobject]@{SteamRoot=$path;AccountId=$Name;ShortcutPath=(Join-Path $path 'shortcuts.vdf')}}
function Game($Name){
    $path=Join-Path $root ('game-'+$Name);[void][IO.Directory]::CreateDirectory($path);$exe=Join-Path $path 'gamelaunchhelper.exe';[IO.File]::WriteAllBytes($exe,[byte[]]@())
    [pscustomobject]@{Id=('xbox:prepare-'+$Name);Title=$Name;Platform='Xbox';Method='Xbox launch helper';InstallPath=$path;Target=$exe;Arguments='';Status='Ready to test';Evidence='fixture';Note=''}
}
try{
    $a=Game 'First';$b=Game 'Second';$ignored=Game 'Ignored';$blocked=Game 'Blocked';$blocked.Status='Unresolved'
    $profile=Profile 'main';Set-GameIgnored @($ignored.Id) $true $prefs
    $plan=New-SteamPreparationPlan $profile @($a,$b,$ignored,$blocked)
    Assert ($plan.AddCount -eq 2 -and $plan.ArtworkCount -eq 2) 'One preview combines selected additions and missing artwork'
    Assert (-not (Test-Path $profile.ShortcutPath)) 'Preparation preview never writes Steam files'
    Assert ((@($plan.Rows|Where-Object GameId -eq $ignored.Id)[0].Action -eq 'Ignored') -and -not @($plan.Rows|Where-Object GameId -eq $blocked.Id)[0].Eligible) 'Excluded and unresolved games are explained and not actionable'
    $state.Statuses[$b.Id]='Needs match'
    $progress=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $activity=Invoke-SteamPreparation $plan $data 'synthetic-key' -Progress $progress
    Assert ($activity.Added -eq 2 -and $activity.ImagesAdded -eq 5 -and $activity.Status -eq 'Needs attention') 'One operation adds shortcuts, fills artwork and reports uncertain matches'
    Assert ($state.Calls.Count -eq 2 -and $ignored.Id -notin $state.Calls -and $blocked.Id -notin $state.Calls) 'Only eligible selected games reach artwork lookup'
    Assert ($progress.Count -gt 0) 'Background progress is delivered through the shared queue'
    $history=@(Get-PreparationActivities $data)
    Assert ($history.Count -eq 1 -and $history[0].Added -eq 2 -and $history[0].Rows.Count -eq 4) 'Activity history survives a read from disk with per-game outcomes'
    $json=Get-Content -LiteralPath (Join-Path $data ('operations\'+$activity.Id+'.json')) -Raw
    Assert (-not $json.Contains('synthetic-key') -and -not $json.Contains($a.Target)) 'History redacts API credentials and excludes stored executable recipes'
    $retry=@(Get-PreparationRetryGames $activity @($a,$b,$ignored,$blocked) $profile)
    Assert ($retry.Count -eq 2 -and $a.Id -notin $retry.Id -and $ignored.Id -notin $retry.Id) 'Retry includes unfinished games and excludes completed or ignored games'
    $retry=@(Get-PreparationRetryGames $activity @($a,$b) $profile)
    Assert ($retry.Count -eq 1 -and $retry[0].Id -eq $b.Id) 'Retry skips games no longer installed instead of reviving historical paths'
    Assert (Throws {Get-PreparationRetryGames $activity @($b) (Profile 'other')}) 'Retry cannot silently target another Steam account'
    $state.Statuses.Remove($b.Id)
    $retryPlan=New-SteamPreparationPlan $profile $retry
    Assert ($retryPlan.AddCount -eq 0 -and $retryPlan.ArtworkCount -eq 1) 'Retry replans the already-added shortcut and only missing artwork'
    $retried=Invoke-SteamPreparation $retryPlan $data 'synthetic-key'
    Assert ($retried.Status -eq 'Complete' -and $retried.Added -eq 0 -and $retried.ImagesAdded -eq 5) 'Retry finishes artwork without duplicating shortcuts'
    $complete=New-SteamPreparationPlan $profile @($a,$b)
    $calls=$state.Calls.Count
    $completed=Invoke-SteamPreparation $complete $data
    Assert ($completed.Status -eq 'Complete' -and $state.Calls.Count -eq $calls) 'Already-complete games require no API key or artwork requests'
    $shortcutFile=(Get-ShortcutSnapshot $profile.ShortcutPath).File
    Assert ($shortcutFile.Items.Count -eq 2) 'Repeated preparation is idempotent'
    $moved=Game 'Moved';$moved.Id=$a.Id;$moved.Title=$a.Title
    $repairPlan=New-SteamPreparationPlan $profile @($moved)
    $calls=$state.Calls.Count
    $repair=Invoke-SteamPreparation $repairPlan $data
    Assert ($repair.Added -eq 0 -and $repair.Repaired -eq 1 -and $repair.Rows[0].Shortcut -eq 'Repaired') 'The combined workflow applies a repair without adding a duplicate'
    $afterRepair=(Get-ShortcutSnapshot $profile.ShortcutPath).File
    Assert ($afterRepair.Items[0].AppId -eq $shortcutFile.Items[0].AppId -and $state.Calls.Count -eq $calls -and (Test-Path $repair.BackupPath)) 'Repair retains artwork identity, skips complete artwork and records its backup'
    $noArtProfile=Profile 'no-art'
    $noArt=Invoke-SteamPreparation (New-SteamPreparationPlan $noArtProfile @($a) $false) $data
    if($noArt.Status -ne 'Complete'){throw ('Shortcut-only preparation failed: '+$noArt.Detail)}
    Assert ($noArt.Added -eq 1 -and $noArt.Status -eq 'Complete' -and $noArt.Rows[0].Artwork -eq 'Skipped') 'Shortcut-only preparation works without credentials'
    $missingKey=New-SteamPreparationPlan (Profile 'missing-key') @($a)
    Assert (Throws {Invoke-SteamPreparation $missingKey $data}) 'Missing credentials are rejected before any shortcut write'
    Assert (-not (Test-Path $missingKey.Profile.ShortcutPath)) 'Credential validation leaves unsynced games unchanged'
    $conflictProfile=Profile 'manual-conflict';$manual=New-Object SteamNite.ShortcutDraft
    $manual.Title=$a.Title;$manual.Exe='"C:\Manual\different.exe"';$manual.StartDir='"C:\Manual"';$manual.LaunchOptions='';$manual.ManagedId='';$manual.AppId=[SteamNite.SteamShortcuts]::AppId($manual.Exe,$manual.Title)
    $manualBytes=([SteamNite.SteamShortcuts]::new([byte[]]$null)).Append([SteamNite.ShortcutDraft[]]@($manual));[IO.File]::WriteAllBytes($conflictProfile.ShortcutPath,$manualBytes)
    $conflict=Invoke-SteamPreparation (New-SteamPreparationPlan $conflictProfile @($a)) $data
    Assert ($conflict.Rows[0].Status -eq 'Blocked' -and $conflict.ImagesAdded -eq 0) 'A manual title conflict is reported without linking or applying artwork'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($conflictProfile.ShortcutPath)) -eq [Convert]::ToBase64String($manualBytes)) 'Combined preparation preserves conflicting manual shortcuts byte-for-byte'
    $cancel=[hashtable]::Synchronized(@{Stop=$true});$cancelProfile=Profile 'cancelled'
    $cancelled=Invoke-SteamPreparation (New-SteamPreparationPlan $cancelProfile @($a)) $data 'synthetic-key' $cancel
    Assert ($cancelled.Status -eq 'Stopped' -and -not (Test-Path $cancelProfile.ShortcutPath)) 'Cancellation before the first phase performs no Steam writes'
    $stopProfile=Profile 'stop-after-current';$cancel.Stop=$false;$state.Cancel=$cancel;$state.StopAfter=$a.Id
    $stopped=Invoke-SteamPreparation (New-SteamPreparationPlan $stopProfile @($a,$b)) $data 'synthetic-key' $cancel
    Assert ($stopped.Added -eq 2 -and $stopped.Rows[0].Status -eq 'Complete' -and $stopped.Rows[1].Status -eq 'Cancelled') 'Stopping preserves finished work and leaves later artwork retryable'
    $state.StopAfter='';$cancel.Stop=$false
    $failedProfile=Profile 'api-failure';$state.Statuses[$a.Id]='Failed'
    $failed=Invoke-SteamPreparation (New-SteamPreparationPlan $failedProfile @($a,$b)) $data 'synthetic-key'
    Assert ($failed.Status -eq 'Stopped' -and $failed.Added -eq 2 -and $failed.Rows[1].Status -eq 'Cancelled') 'An artwork stop condition retains successful imports and stops later requests'
    $state.Statuses[$a.Id]='Throw'
    $thrown=Invoke-SteamPreparation (New-SteamPreparationPlan (Profile 'throw') @($a,$b)) $data 'synthetic-key'
    Assert ($thrown.Status -eq 'Failed' -and $thrown.Added -eq 2 -and -not $thrown.Detail.Contains('synthetic-key')) 'Unexpected failures preserve shortcut results and redact error credentials'
    $state.Statuses.Clear()
    $stale=New-SteamPreparationPlan (Profile 'stale-policy') @($a)
    Set-GameIgnored @($a.Id) $true $prefs
    Assert (Throws {Invoke-SteamPreparation $stale $data 'synthetic-key'}) 'An exclusion changed after review invalidates the preparation preview'
    Set-GameIgnored @($a.Id) $false $prefs
    $state.Running=$true
    Assert (Throws {Invoke-SteamPreparation $stale $data 'synthetic-key'}) 'Preparation never closes or writes through a running Steam client by itself'
    $state.Running=$false
    $intentProfile=Profile 'intent-failure';$badData=Join-Path $root 'not-a-directory';[IO.File]::WriteAllText($badData,'fixture')
    Assert (Throws {Invoke-SteamPreparation (New-SteamPreparationPlan $intentProfile @($a) $false) $badData}) 'Failure to create the intent log aborts before changing Steam'
    Assert (-not (Test-Path $intentProfile.ShortcutPath)) 'An unavailable history destination leaves Steam untouched'
    $interrupted=$activity.PSObject.Copy();$interrupted.Id=[guid]::NewGuid().ToString('N');$interrupted.Status='Running'
    & $module {param($entry,$path) Save-PreparationActivity $entry $path} $interrupted $data
    Assert (@(Get-PreparationActivities $data|Where-Object Id -eq $interrupted.Id)[0].Status -eq 'Interrupted') 'Incomplete prior sessions appear as interrupted rather than successful'
    '{'|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $data 'operations\bad.json')
    Assert (@(Get-PreparationActivities $data|Where-Object Status -eq 'Unreadable').Count -eq 1) 'A damaged activity file does not hide other history'
    $uninstalled=$a.PSObject.Copy();$uninstalled|Add-Member NoteProperty InstallState 'Not installed'
    Assert (Throws {New-SteamPreparationPlan $profile @($uninstalled)}) 'Uninstalled entries cannot enter the preparation workflow'
    $asyncProfile=Profile 'async';$asyncPlan=New-SteamPreparationPlan $asyncProfile @($a) $false;$worker=[PowerShell]::Create()
    try{
        [void]$worker.AddScript({param($path,$plan,$data) Import-Module (Join-Path (Split-Path $path) 'SteamNite.Steam.psm1') -Force;Import-Module $path -Force;& (Get-Module SteamNite.Steam) {function script:Test-SteamRunning {$false}};& (Get-Module SteamNite.Preparation) {function script:Test-SteamRunning {$false}};Invoke-SteamPreparation $plan $data}).AddArgument((Join-Path $PSScriptRoot '..\src\SteamNite.Preparation.psm1')).AddArgument($asyncPlan).AddArgument($data)
        $handle=$worker.BeginInvoke();$output=@($worker.EndInvoke($handle))
        if($worker.HadErrors){throw ($worker.Streams.Error -join "`n")}
        Assert (-not $worker.HadErrors -and $output[-1].Added -eq 1 -and $output[-1].Status -eq 'Complete') 'The real background runspace accepts the reviewed plan and returns durable results'
    }finally{$worker.Dispose()}
    "`nAll $script:passed preparation checks passed. No network, real games or Steam files were used."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
