$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $workspace 'winui\Native.Service.ps1') -Workspace $workspace -LibraryOnly
$root=Join-Path $PSScriptRoot ('.tmp\native-service-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$script:data=$root;$script:settingsPath=Join-Path $root 'settings.json'
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw "FAIL: $Message"};$script:passed++;"PASS: $Message"}
function Throws($Code){try{& $Code;return $false}catch{return $true}}
function Call($Operation,$Data=@{}) {Invoke-NativeOperation ([pscustomobject]@{Operation=$Operation;Data=[pscustomobject]$Data})}
function Read-NativeLibrary {}
try{
    $g=[pscustomobject]@{Id='gog:one';NativeGameId='gog:one';Title='One';InstallState='Installed';Status='Ready to test';Ignored=$false;CanRemove=$false}
    $script:state.Library=@($g)
    Assert (@(Select-NativeGames @('gog:one') 'Prepare').Count -eq 1) 'A single selected game remains an explicit selection'
    Assert (Throws {Call 'RunCommand' @{Command='anything'}}) 'Unknown native operations are rejected'
    Assert (Throws {Invoke-NativeOperation ([pscustomobject]@{Operation='History';Data=@{};Command='anything'})}) 'Unexpected top-level request fields are rejected'
    Assert (Throws {Call 'Launch' @{Ids=@('missing')}}) 'A stale game identity cannot launch'
    Assert (Throws {Call 'Launch' @{Ids=@('gog:one','other')}}) 'Multi-game launch cannot silently use the first item'
    Assert (Throws {Call 'Remove' @{Confirmed=$true}}) 'Removal requires a server-held review plan'
    Assert (Throws {Call 'StartPrepare'}) 'Preparation requires a server-held preview'
    Assert (Throws {Call 'ArtImage' @{Kind='Cover';AssetId=1;Path='C:\anything'}}) 'Artwork accepts only server-held provider candidates'
    Assert (Throws {Call 'ArtApply' @{RecommendAll=$true;Fill=$false}}) 'Replacing existing artwork with recommendations requires explicit confirmation'
    Assert (Throws {Call 'SaveLaunch' @{Ids=@('missing');Executable='C:\anything.exe'}}) 'Launch overrides must resolve a current installed identity'
    $ignored=$g.PSObject.Copy();$ignored.Ignored=$true;$script:state.Library=@($ignored)
    Assert (Throws {Call 'ArtContext' @{Ids=@('gog:one')}}) 'Ignored games cannot enter artwork writes'
    $script:state.Library=@($g)
    $script:state.Worker=New-Object object
    Assert (Throws {Call 'SaveSettings' @{ExtraRoots=@()}}) 'An active write blocks conflicting settings mutations'
    $script:state.Cancel=[hashtable]::Synchronized(@{Stop=$false});[void](Call 'Stop')
    Assert ($script:state.Cancel.Stop) 'Stop signals cooperative cancellation without killing a process'
    $script:state.Worker=$null
    [void](Call 'SaveSettings' @{ExtraRoots=@('D:\Games')})
    [void](Call 'SaveSettings' @{ExtraRoots=@('C:\Games')})
    Assert ((Get-AppSettings $script:settingsPath).ExtraRoots[0] -eq 'C:\Games') 'Native settings use the existing persistence layer'
    Assert ((Call 'History').Activities.Count -eq 0) 'Empty native history is represented explicitly'
    Assert (Throws {Call 'Profile' @{Profile='C:\not-a-Steam-account'}}) 'Account paths must resolve an available Steam profile'
    function New-SteamPreparationPlan($Profile,[object[]]$Games,[bool]$IncludeArtwork){[pscustomobject]@{Rows=@($Games|ForEach-Object {[pscustomobject]@{GameId=$_.Id;Title=$_.Title;Eligible=$true;Action='Keep existing';Artwork='Complete';Detail='Fixture'}});Profile=$Profile;IncludeArtwork=$IncludeArtwork;AddCount=0;RepairCount=0;ArtworkCount=0}}
    $script:state.Profile=[pscustomobject]@{Label='Fixture account'}
    $preview=Call 'Preview' @{Ids=@('gog:one');All=$false;Artwork=$true}
    Assert ($preview.Rows.Count -eq 1 -and $preview.Rows[0].GameId -eq 'gog:one') 'A one-game native preview does not collapse its selection in PowerShell 5.1'
    $second=$g.PSObject.Copy();$second.Id='gog:two';$second.NativeGameId='gog:two';$script:state.Library=@($g,$second)
    $preview=Call 'Preview' @{Ids=@('gog:one','gog:two');All=$false;Artwork=$false}
    Assert ($preview.Rows.Count -eq 2 -and -not $preview.IncludeArtwork) 'A native multi-selection preview preserves both identities and the artwork option'
    function Get-PreparationSignature($Plan){(@($Plan.Rows.GameId) -join ',')+'|'+$Plan.IncludeArtwork}
    function Test-SteamRunning {$false}
    $fixtureWorkspace=Join-Path $root 'worker';[void][IO.Directory]::CreateDirectory((Join-Path $fixtureWorkspace 'src'))
    @'
function Invoke-SteamPreparation {
    param($Plan,$DataDirectory,$ApiKey,$Cancellation,$Progress)
    $activity=[pscustomobject]@{Id='fixture';Status='Running';Detail='Fixture worker';Rows=@($Plan.Rows);BackupPath=''}
    $Progress.Enqueue(($activity|ConvertTo-Json -Depth 6 -Compress))
    Start-Sleep -Milliseconds 200
    $activity.Status=if($Cancellation.Stop){'Stopped'}else{'Complete'}
    $activity|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $DataDirectory 'worker-result.json')
    $activity
}
Export-ModuleMember -Function Invoke-SteamPreparation
'@ | Set-Content -Encoding UTF8 (Join-Path $fixtureWorkspace 'src\SteamNite.Preparation.psm1')
    $Workspace=$fixtureWorkspace
    $script:state.Profile=[pscustomobject]@{Label='Fixture';ShortcutPath=(Join-Path $root 'shortcuts.vdf')}
    # Use the real native worker lifecycle with a synthetic preparation module;
    # the actual preparation module's writes/guards are covered separately.
    $script:state.Plan|Add-Member NoteProperty SyncPlan ([pscustomobject]@{OriginalHash='fixture'}) -Force
    $fixturePlan=$script:state.Plan
    function New-SteamPreparationPlan($Profile,[object[]]$Games,[bool]$IncludeArtwork){$fixturePlan}
    [void](Call 'StartPrepare')
    $deadline=[datetime]::UtcNow.AddSeconds(10)
    do{$poll=Call 'Poll';if(-not $poll.Running){break};Start-Sleep -Milliseconds 30}while([datetime]::UtcNow -lt $deadline)
    Assert (-not $poll.Running -and $poll.Activity.Status -eq 'Complete') 'The native worker returns completion through polling and releases its runspace'
    Assert (Test-Path (Join-Path $root 'worker-result.json')) 'Native worker receives the isolated data destination'
    [void](Call 'StartPrepare');[void](Call 'Stop')
    do{$poll=Call 'Poll';if(-not $poll.Running){break};Start-Sleep -Milliseconds 30}while([datetime]::UtcNow -lt $deadline)
    Assert (-not $poll.Running -and $poll.Activity.Status -eq 'Stopped') 'The native Stop operation reaches the active worker cooperatively'
    function Get-SteamProfiles { [pscustomobject]@{Label='Other fixture';ShortcutPath='C:\fixture\other\shortcuts.vdf'} }
    $script:state.Removal=New-Object object;$script:state.Art=New-Object object
    [void](Call 'Profile' @{Profile='C:\fixture\other\shortcuts.vdf'})
    Assert ($null -eq $script:state.Plan -and $null -eq $script:state.Removal -and $null -eq $script:state.Art) 'Changing accounts invalidates all pending write contexts'
    $script:state.Profile=[pscustomobject]@{Label='Fixture account';AccountId='fixture'}
    $script:state.Art=[pscustomobject]@{AppId=[uint32]123;Game=[pscustomobject]@{Title='Fixture artwork'};Icon='';GridDirectory=$root}
    $script:state.Selections=@{Cover=[pscustomobject]@{}}
    $art=Get-NativeArtState
    Assert ($art.Title -eq 'Fixture artwork' -and $art.AccountId -eq 'fixture') 'Artwork context carries title and destination without a duplicate discovery request'
    Assert ($art.Categories.Count -eq 5 -and @($art.Categories|Where-Object {$_.Kind -eq 'Cover' -and $_.Queued}).Count -eq 1) 'Artwork context exposes coverage and queued state for category tabs'
    Assert ('Key' -notin @($art.Keys) -and 'ApiKey' -notin @($art.Keys)) 'Artwork layout metadata never returns credentials'
    function Search-ArtworkGames { @() }
    $script:state.Key='fixture-key';$script:state.Match=[pscustomobject]@{id=1};$script:state.Sets=@{Cover=@()}
    $search=Call 'ArtSearch' @{Query='No match fixture'}
    Assert ($search.Index -eq -1 -and $search.Matches.Count -eq 0 -and $search.State.Queued.Count -eq 0 -and $null -eq $script:state.Match) 'A new empty artwork search clears stale matches and queued choices'
    "All $script:passed native service checks passed. No Steam files changed."
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
