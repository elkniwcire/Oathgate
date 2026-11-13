$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.BulkArtwork.psm1') -Force
$module=Get-Module SteamNite.BulkArtwork
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
$root=Join-Path $PSScriptRoot ('.tmp\bulk-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $root -Force)
try{
    Assert ((Get-ArtworkTitleKey ('Pok'+[char]0x00e9+'mon: Game - Edition')) -eq (Get-ArtworkTitleKey 'Pokemon Game Edition')) 'Exact matching tolerates punctuation, case and accents'
    Assert ((Get-ArtworkTitleKey 'Game II') -ne (Get-ArtworkTitleKey 'Game III')) 'Matching preserves sequel numbers'
    Assert ((Get-ArtworkTitleKey 'Game') -ne (Get-ArtworkTitleKey 'Game Deluxe')) 'Matching preserves edition names'
    $game=[pscustomobject]@{Id='fixture:one';Title='Example Game'}
    $context=[pscustomobject]@{AppId=123;Icon='';Profile=@{ShortcutPath='fixture'}}
    & $module {
        $script:searchCount=0;$script:matches=@([pscustomobject]@{id=1;name='Example: Game'},[pscustomobject]@{id=2;name='Example Game Dedicated Server'})
        function script:Search-ArtworkGames($Query,$ApiKey){$script:searchCount++;$script:matches}
    }
    $match=Resolve-BulkArtworkMatch $game $context $root 'synthetic-key'
    Assert ($match.id -eq 1 -and $match.Source -eq 'Exact title match') 'Only a unique exact normalized title is accepted automatically'
    & $module {$script:matches=@([pscustomobject]@{id=1;name='Example: Game'},[pscustomobject]@{id=2;name='Example Game'})}
    Assert ($null -eq (Resolve-BulkArtworkMatch $game $context $root 'synthetic-key')) 'Ambiguous exact matches require a manual choice'
    & $module {$script:matches=@([pscustomobject]@{id=3;name='Example Game II'})}
    Assert ($null -eq (Resolve-BulkArtworkMatch $game $context $root 'synthetic-key')) 'Similar titles are not silently selected'
    @{GameId=$game.Id;SgdbId=99;SgdbTitle='Confirmed edition'}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $root 'artwork-123.json')
    $before=& $module {$script:searchCount}
    $saved=Resolve-BulkArtworkMatch $game $context $root 'synthetic-key'
    Assert ($saved.id -eq 99 -and (& $module {$script:searchCount}) -eq $before) 'Saved confirmed game identities bypass title search'
    @{GameId='different:game';SgdbId=88;SgdbTitle='Wrong game'}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $root 'artwork-123.json')
    Assert ($null -eq (Resolve-BulkArtworkMatch $game $context $root 'synthetic-key')) 'A saved match for another game is never reused'
    & $module {
        $script:running=$true;$script:synced=$true;$script:complete=$false;$script:saveCount=0;$script:contextCount=0;$script:failSave=$false
        function script:Test-SteamRunning{$script:running}
        function script:Get-SteamArtworkContext($Profile,$Game){$script:contextCount++;if(-not $script:synced){throw 'Not synced'};[pscustomobject]@{AppId=123;Icon='';Profile=$Profile}}
        function script:Get-ExistingArtwork($Context,$Kind){if($script:complete){'existing.png'}}
        function script:Get-ArtworkCandidates($Id,$Key){@{Cover=@()}}
        function script:Get-RecommendedArtwork($Sets,$Context,$CacheDirectory){[pscustomobject]@{Selections=@{Cover=@{Path='fixture.png'}};Unavailable=@('Logo');Preserved=@()}}
        function script:Save-SteamArtwork($Context,$Selections){$script:saveCount++;if($script:failSave){throw 'Fixture rate limit reached'};[pscustomobject]@{Added=@('Cover');Skipped=@();BackupPath=''}}
    }
    $blocked=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($blocked.StopBatch -and $blocked.Status -eq 'Stopped' -and (& $module {$script:contextCount}) -eq 0) 'A running Steam client stops the batch before any game work'
    & $module {$script:running=$false;$script:synced=$false}
    $unsynced=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($unsynced.Status -eq 'Not synced' -and -not $unsynced.StopBatch) 'Unsynced games are skipped without ending the batch'
    & $module {$script:synced=$true;$script:complete=$true}
    $before=& $module {$script:searchCount}
    $complete=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($complete.Status -eq 'Complete' -and (& $module {$script:searchCount}) -eq $before) 'Games with all artwork are preserved without API calls'
    & $module {$script:complete=$false}
    $uncertain=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($uncertain.Status -eq 'Needs match' -and (& $module {$script:saveCount}) -eq 0) 'Uncertain matches cannot write artwork'
    & $module {$script:matches=@([pscustomobject]@{id=7;name='Example Game'})}
    $applied=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($applied.Status -eq 'Partial' -and $applied.Added -eq 1 -and $applied.Detail -like '*Logo*') 'Batch results report added artwork and unavailable categories per game'
    $record=Get-Content (Join-Path $root 'artwork-123.json') -Raw|ConvertFrom-Json
    Assert ($record.GameId -eq $game.Id -and $record.SgdbId -eq 7 -and -not ($record|ConvertTo-Json -Depth 7).Contains('synthetic-key')) 'Successful batches save public match data without credentials'
    [void](Invoke-BulkArtworkGame $game @{} $root 'synthetic-key')
    Assert ((& $module {$script:contextCount}) -ge 5) 'Every game operation obtains a fresh Steam shortcut snapshot'
    & $module {$script:failSave=$true}
    $failed=Invoke-BulkArtworkGame $game @{} $root 'synthetic-key'
    Assert ($failed.Status -eq 'Failed' -and $failed.StopBatch) 'Rate limits stop further batch work and retain a per-game error'
    "`nAll $script:passed bulk artwork checks passed. No network or real Steam writes."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
