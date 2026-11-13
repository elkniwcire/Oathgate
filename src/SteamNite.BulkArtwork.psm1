$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Artwork.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Steam.psm1')

function Get-ArtworkTitleKey([string]$Title) {
    # Ignore punctuation/trademarks, but preserve words, numbers, editions and subtitles.
    return [regex]::Replace($Title.Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant(),'[^\p{L}\p{Nd}]','')
}
function Resolve-BulkArtworkMatch($Game,$Context,[string]$DataDirectory,[string]$ApiKey) {
    $path=Join-Path $DataDirectory ('artwork-'+$Context.AppId+'.json')
    if (Test-Path -LiteralPath $path) {
        try {
            $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.GameId -eq $Game.Id -and [long]$saved.SgdbId -gt 0) {
                return [pscustomobject]@{id=[long]$saved.SgdbId;name=$saved.SgdbTitle;Source='Saved match'}
            }
        } catch { }
    }
    $key=Get-ArtworkTitleKey $Game.Title
    $matches=@(Search-ArtworkGames $Game.Title $ApiKey | Where-Object { (Get-ArtworkTitleKey $_.name) -eq $key })
    if ($matches.Count -ne 1) { return $null }
    [pscustomobject]@{id=$matches[0].id;name=$matches[0].name;Source='Exact title match'}
}
function Invoke-BulkArtworkGame {
    param($Game,$Profile,[string]$DataDirectory,[string]$ApiKey)
    $result=[pscustomobject]@{GameId=$Game.Id;Title=$Game.Title;Status='';Detail='';Added=0;StopBatch=$false}
    if($Game.Id -in @(Get-IgnoredGameIds)){$result.Status='Ignored';$result.Detail='Excluded from SteamNite changes.';return $result}
    if (Test-SteamRunning) { $result.Status='Stopped';$result.Detail='Steam is running. Exit Steam before applying artwork.';$result.StopBatch=$true;return $result }
    try { $context=Get-SteamArtworkContext $Profile $Game }
    catch { $result.Status='Not synced';$result.Detail=$_.Exception.GetBaseException().Message;return $result }
    try {
        $missing=@(foreach($kind in @('Cover','Wide','Hero','Logo','Icon')) {
            if (@(Get-ExistingArtwork $context $kind).Count -eq 0 -and -not ($kind -eq 'Icon' -and $context.Icon)) { $kind }
        })
        if (-not $missing.Count) { $result.Status='Complete';$result.Detail='All five categories already exist; preserved without a lookup.';return $result }
        $match=Resolve-BulkArtworkMatch $Game $context $DataDirectory $ApiKey
        if (-not $match) { $result.Status='Needs match';$result.Detail='Choose the correct game in Artwork; no unique exact title match was found.';return $result }
        $sets=Get-ArtworkCandidates $match.id $ApiKey
        $choices=Get-RecommendedArtwork $sets $context (Join-Path $DataDirectory 'artwork-cache')
        if ($choices.Selections.Count) {
            $applied=Save-SteamArtwork $context $choices.Selections
            $result.Added=$applied.Added.Count
            $result.Detail='Added '+($applied.Added -join ', ')+'. '+$match.Source+'.'
            [void](New-Item -ItemType Directory -Path $DataDirectory -Force)
            @{GameId=$Game.Id;SteamAppId=$context.AppId;SgdbId=$match.id;SgdbTitle=$match.name;Assets=$choices.Selections;AppliedAt=(Get-Date).ToString('o')} |
                ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $DataDirectory ('artwork-'+$context.AppId+'.json')) -Encoding UTF8
        } else { $result.Detail='No usable images were available for missing categories.' }
        $result.Status=if ($choices.Unavailable.Count) {'Partial'} elseif ($result.Added) {'Applied'} else {'Complete'}
        if ($choices.Unavailable.Count) { $result.Detail+=' Unavailable: '+($choices.Unavailable -join ', ')+'.' }
    } catch {
        $result.Status='Failed';$result.Detail=$_.Exception.GetBaseException().Message
        if ((Test-SteamRunning) -or $result.Detail -match 'rate limit|rejected the request') { $result.StopBatch=$true }
    }
    return $result
}
Export-ModuleMember -Function Get-ArtworkTitleKey, Resolve-BulkArtworkMatch, Invoke-BulkArtworkGame
