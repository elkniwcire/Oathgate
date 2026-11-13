$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Artwork.psm1') -Force
$script:passed=0
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw ('FAIL: '+$Message) }; $script:passed++; 'PASS: '+$Message }
function Throws($Action) { try { & $Action; $false } catch { $true } }
$root=Join-Path $PSScriptRoot ('.tmp\art-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root -Force)
$module=Get-Module SteamNite.Artwork
& $module { function script:Test-SteamRunning { $false } }
function New-Fixture([string]$Name) {
    $dir=Join-Path $root $Name; [void](New-Item -ItemType Directory -Path $dir -Force)
    $helper=Join-Path $dir 'gamelaunchhelper.exe'; [IO.File]::WriteAllBytes($helper,[byte[]]@())
    $d=New-Object SteamNite.ShortcutDraft
    $d.Title='Artwork fixture';$d.Exe='"'+$helper+'"';$d.StartDir='"'+$dir+'"';$d.LaunchOptions='';$d.ManagedId='steamnite:xbox:fixture'
    $d.AppId=[SteamNite.SteamShortcuts]::AppId($d.Exe,$d.Title)
    $manual=New-Object SteamNite.ShortcutDraft
    $manual.Title='Manual game';$manual.Exe='"C:\Manual\game.exe"';$manual.StartDir='"C:\Manual"';$manual.LaunchOptions='--manual';$manual.ManagedId=''
    $manual.AppId=[SteamNite.SteamShortcuts]::AppId($manual.Exe,$manual.Title)
    $file=[SteamNite.SteamShortcuts]::new([byte[]]$null)
    [byte[]]$bytes=$file.Append([SteamNite.ShortcutDraft[]]@($manual,$d))
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $dir 'shortcuts.vdf');SteamRoot=$dir;AccountId='fixture'}
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$bytes)
    $game=[pscustomobject]@{Id='xbox:fixture';Title=$d.Title;Status='Ready to test';Method='Xbox launch helper';Target=$helper;InstallPath=$dir}
    [pscustomobject]@{Context=(Get-SteamArtworkContext $profile $game);Bytes=$bytes;Dir=$dir;Profile=$profile;Game=$game}
}
try {
    Assert ([SteamNite.ArtworkHttp]::AllowedImageUrl('https://cdn2.steamgriddb.com/grid/a.png')) 'Official HTTPS artwork URLs are accepted'
    Assert (-not [SteamNite.ArtworkHttp]::AllowedImageUrl('https://steamgriddb.com.evil.example/a.png')) 'Lookalike artwork domains are rejected'
    Assert (-not [SteamNite.ArtworkHttp]::AllowedImageUrl('http://cdn2.steamgriddb.com/a.png')) 'Unencrypted image URLs are rejected'
    Assert (-not [SteamNite.ArtworkHttp]::AllowedImageUrl('file:///C:/private.png')) 'Local-file artwork URLs are rejected'
    Assert (-not [SteamNite.ArtworkHttp]::AllowedImageUrl('https://user@cdn2.steamgriddb.com/a.png')) 'Artwork URLs containing credentials are rejected'
    Assert (Throws { [void][SteamNite.ArtworkHttp]::Api('/search/autocomplete/test',"bad`nkey") }) 'Invalid API credentials fail before making a request'
    Set-ArtworkApiKey $root 'synthetic-test-key-not-a-real-credential'
    Assert ((Get-ArtworkApiKey $root) -eq 'synthetic-test-key-not-a-real-credential') 'Remembered key round-trips through Windows account protection'
    Assert (-not ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $root 'steamgriddb.key')))).Contains('synthetic-test-key')) 'Saved key file does not contain plaintext credentials'
    Remove-ArtworkApiKey $root
    Assert ((Get-ArtworkApiKey $root) -eq '') 'Forget key removes the protected credential'

    Assert ((Get-ArtworkStem 2325823140 'Cover') -eq '2325823140p') 'Cover naming uses the actual unsigned Steam shortcut ID'
    Assert ((Get-ArtworkStem 2325823140 'Wide') -eq '2325823140') 'Wide artwork uses the shortcut ID without a suffix'
    Assert ((Get-ArtworkStem 2325823140 'Hero') -eq '2325823140_hero') 'Hero artwork uses the Steam hero suffix'
    Assert ((Get-ArtworkStem 2325823140 'Logo') -eq '2325823140_logo') 'Logo artwork uses the Steam logo suffix'
    Assert (Throws { Get-ArtworkStem 1 '../outside' }) 'Unknown artwork types cannot become destination paths'
    $png=Join-Path $root 'source.png'; $jpg=Join-Path $root 'source.jpg'
    $bitmap=New-Object Drawing.Bitmap(60,90)
    try { $bitmap.SetPixel(1,1,[Drawing.Color]::CornflowerBlue);$bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Save($jpg,[Drawing.Imaging.ImageFormat]::Jpeg) } finally { $bitmap.Dispose() }
    $converted=Join-Path $root 'converted.png'; ConvertTo-ArtworkPng $jpg $converted
    $image=[Drawing.Image]::FromFile($converted)
    try { Assert ($image.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Png.Guid -and $image.Width -eq 60) 'JPEG downloads are decoded and normalized to real PNG files' } finally { $image.Dispose() }
    $invalid=Join-Path $root 'invalid.png'; 'not-an-image' | Set-Content -Encoding UTF8 -LiteralPath $invalid
    Assert (Throws { ConvertTo-ArtworkPng $invalid (Join-Path $root 'invalid-output.png') }) 'Invalid image payloads cannot be applied'
    $oversized=Join-Path $root 'large.png'; $stream=[IO.File]::Create($oversized)
    try { $stream.SetLength(20MB+1) } finally { $stream.Dispose() }
    Assert (Throws { ConvertTo-ArtworkPng $oversized (Join-Path $root 'large-output.png') }) 'Oversized image payloads are rejected before decoding'

    $f=New-Fixture 'fill'; $ctx=$f.Context
    Assert ($ctx.AppId -eq ([SteamNite.SteamShortcuts]::new($f.Bytes)).Items[1].AppId) 'Artwork context resolves the matching shortcut identity'
    [void](New-Item -ItemType Directory -Path $ctx.GridDirectory -Force)
    $existingCover=Join-Path $ctx.GridDirectory ((Get-ArtworkStem $ctx.AppId 'Cover')+'.jpg')
    [IO.File]::Copy($jpg,$existingCover)
    $coverHash=(Get-FileHash $existingCover).Hash
    $selections=@{}; foreach($kind in @('Cover','Wide','Hero','Logo','Icon')) { $selections[$kind]=[pscustomobject]@{Path=$png} }
    & $module { function script:Test-SteamRunning { $true } }
    Assert (Throws { Save-SteamArtwork $ctx $selections }) 'Artwork writes are blocked while Steam runs'
    Assert (@(Get-ChildItem $ctx.GridDirectory -File).Count -eq 1) 'Blocked application creates no artwork files'
    & $module { function script:Test-SteamRunning { $false } }
    $result=Save-SteamArtwork $ctx $selections
    Assert ($result.Added.Count -eq 4 -and $result.Skipped -contains 'Cover') 'Applying fills only missing slots and preserves existing JPG artwork'
    Assert ((Get-FileHash $existingCover).Hash -eq $coverHash) 'Existing manual artwork remains byte-for-byte unchanged'
    Assert (-not (Test-Path (Join-Path $ctx.GridDirectory ((Get-ArtworkStem $ctx.AppId 'Cover')+'.png')))) 'No competing PNG is created beside existing JPG cover art'
    Assert (Test-Path -LiteralPath $result.BackupPath) 'Icon registration creates a shortcut backup'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath)) -eq [Convert]::ToBase64String($f.Bytes)) 'Icon backup exactly preserves all original shortcuts'
    $expected=([SteamNite.SteamShortcuts]::new($f.Bytes)).WithIcon($ctx.AppId,(Join-Path $ctx.GridDirectory ((Get-ArtworkStem $ctx.AppId 'Icon')+'.png')))
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($f.Profile.ShortcutPath)) -eq [Convert]::ToBase64String($expected)) 'Only the selected shortcut icon field is changed'
    $after=(Get-ShortcutSnapshot $f.Profile.ShortcutPath).File
    Assert ($after.Items[0].LaunchOptions -eq '--manual' -and $after.Items[1].Exe -eq ('"'+$f.Game.Target+'"')) 'Manual shortcut settings and game launch paths remain intact'
    Assert (Throws { Save-SteamArtwork $ctx $selections }) 'Stale shortcut snapshots cannot apply artwork'
    $fresh=Get-SteamArtworkContext $f.Profile $f.Game
    $repeat=Save-SteamArtwork $fresh $selections
    Assert ($repeat.Added.Count -eq 0 -and $repeat.Skipped.Count -eq 5) 'Repeated application preserves all five existing slots'
    $g=New-Fixture 'custom-icon'
    [IO.File]::WriteAllBytes($g.Profile.ShortcutPath,([SteamNite.SteamShortcuts]::new($g.Bytes)).WithIcon($g.Context.AppId,'C:\Custom\icon.ico'))
    $custom=Get-SteamArtworkContext $g.Profile $g.Game
    $r=Save-SteamArtwork $custom @{Icon=[pscustomobject]@{Path=$png}}
    Assert ($r.Added.Count -eq 0 -and $r.Skipped -contains 'Icon') 'An existing custom icon reference is preserved even if its file is offline'
    $h=New-Fixture 'invalid-batch'
    Assert (Throws { Save-SteamArtwork $h.Context @{Hero=[pscustomobject]@{Path=$png};Logo=[pscustomobject]@{Path=$invalid}} }) 'All selected files must validate before any artwork is committed'
    Assert (@(Get-ChildItem $h.Context.GridDirectory -File).Count -eq 0) 'Failed image validation leaves no partial artwork or temporary files'
    $rollback=New-Fixture 'rollback'
    & $module { $script:processChecks=0; function script:Test-SteamRunning { $script:processChecks++; $script:processChecks -ge 3 } }
    Assert (Throws { Save-SteamArtwork $rollback.Context @{Hero=[pscustomobject]@{Path=$png};Icon=[pscustomobject]@{Path=$png}} }) 'Steam starting during icon registration aborts the update'
    Assert (@(Get-ChildItem $rollback.Context.GridDirectory -File).Count -eq 0) 'An interrupted icon update rolls back only newly added artwork'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($rollback.Profile.ShortcutPath)) -eq [Convert]::ToBase64String($rollback.Bytes)) 'Interrupted icon update leaves shortcut bytes unchanged'
    & $module { function script:Test-SteamRunning { $false } }

    # Validate API request construction without sending any credentials or network traffic.
    & $module { $script:requests=New-Object 'System.Collections.Generic.List[string]'; function script:Invoke-Sgdb($Path,$ApiKey) { $script:requests.Add($Path); @() } }
    [void](Search-ArtworkGames 'Game / Edition & More' 'fixture-key')
    [void](Get-ArtworkCandidates 123 'fixture-key')
    $requests=& $module { $script:requests.ToArray() }
    Assert ($requests[0] -eq '/search/autocomplete/Game%20%2F%20Edition%20%26%20More') 'Game search safely encodes special title characters'
    Assert ($requests.Count -eq 6 -and $requests[1] -like '*dimensions=600x900*' -and $requests[2] -like '*dimensions=920x430,460x215*') 'All five artwork types use the expected API routes and grid dimensions'
    Assert (@($requests | Select-Object -Skip 1 | Where-Object { $_ -notlike '*types=static*nsfw=false*' }).Count -eq 0) 'Artwork requests filter for static images and exclude flagged content'
    Assert ($requests[4] -notlike '*jpeg*' -and $requests[5] -notlike '*jpeg*') 'Logo and icon queries use only the MIME type accepted by those endpoints'
    & $module {
        function script:Invoke-Sgdb($Path,$ApiKey) {
            @([pscustomobject]@{id=9;score=0;url='https://cdn2.steamgriddb.com/a.png'},[pscustomobject]@{id=3;score=99;url='https://cdn2.steamgriddb.com/b.png'})
        }
    }
    $ranked=Get-ArtworkCandidates 123 'fixture-key'
    Assert ($ranked.Cover[0].id -eq 9 -and $ranked.Cover[1].id -eq 3) 'Provider ranking is preserved instead of being scrambled by hidden score fields'
    & $module {
        $script:downloadUrls=New-Object 'System.Collections.Generic.List[string]'
        function script:Get-CachedArtwork($Asset,$CacheDirectory) {
            $script:downloadUrls.Add([string]$Asset.url)
            if ($Asset.id -eq 'broken' -or $Asset.url -like '*broken*') { throw 'fixture download failed' }
            return (Join-Path $CacheDirectory 'source.png')
        }
    }
    $auto=New-Fixture 'recommended'
    [void](New-Item -ItemType Directory -Path $auto.Context.GridDirectory -Force)
    [IO.File]::Copy($png,(Join-Path $auto.Context.GridDirectory ((Get-ArtworkStem $auto.Context.AppId 'Hero')+'.png')))
    $sets=@{
        Cover=@([pscustomobject]@{id='broken';url='https://cdn2.steamgriddb.com/broken.png'},[pscustomobject]@{id=2;url='https://cdn2.steamgriddb.com/cover.png';author=@{name='Cover artist'}},[pscustomobject]@{id=3;url='https://cdn2.steamgriddb.com/lower.png'})
        Wide=@([pscustomobject]@{id=4;url='https://cdn2.steamgriddb.com/wide.png';author=@{name='Wide artist'}})
        Hero=@([pscustomobject]@{id=5;url='https://cdn2.steamgriddb.com/hero.png'})
        Logo=@()
        Icon=@([pscustomobject]@{id=6;url='https://cdn2.steamgriddb.com/icon.png';author=@{name='Icon artist'}})
    }
    $recommended=Get-RecommendedArtwork $sets $auto.Context $root
    Assert ($recommended.Selections.Count -eq 3 -and $recommended.Selections.Cover.AssetId -eq 2) 'Recommendations fall back to the next ranked image when a download fails'
    Assert ($recommended.Preserved -contains 'Hero' -and -not $recommended.Selections.ContainsKey('Hero')) 'Automatic recommendations preserve existing artwork slots'
    Assert ($recommended.Unavailable -contains 'Logo') 'Missing recommendation categories are reported without blocking available artwork'
    $downloadUrls=& $module { $script:downloadUrls.ToArray() }
    Assert ($downloadUrls -notcontains 'https://cdn2.steamgriddb.com/lower.png' -and $downloadUrls -notcontains 'https://cdn2.steamgriddb.com/hero.png') 'Recommendations stop after a successful choice and do not download preserved slots'
    $applied=Save-SteamArtwork $auto.Context $recommended.Selections
    Assert ($applied.Added.Count -eq 3) 'Recommended artwork uses the same validated apply and icon backup flow'
    $allRecommended=Get-RecommendedArtwork $sets $auto.Context $root -ReplaceExisting
    Assert ($allRecommended.Selections.Count -eq 4 -and $allRecommended.Selections.Hero.AssetId -eq 5) 'Explicit recommended replacement considers occupied artwork categories too'
    Assert ($allRecommended.Preserved.Count -eq 0 -and $allRecommended.Unavailable -contains 'Logo') 'Recommended replacement reports unavailable categories without clearing their current artwork'
    $thumbResults=@(Get-ArtworkThumbnails @(
        [pscustomobject]@{id=1;url='https://cdn2.steamgriddb.com/full.png';thumb='https://cdn2.steamgriddb.com/thumb.png'},
        [pscustomobject]@{id=2;url='https://cdn2.steamgriddb.com/fallback.png';thumb='https://untrusted.example/thumb.png'},
        [pscustomobject]@{id=3;url='https://cdn2.steamgriddb.com/broken.png';thumb=''}
    ) $root)
    Assert ($thumbResults.Count -eq 3 -and $thumbResults[0].Path -and $thumbResults[2].Error) 'Thumbnail failures are isolated so the rest of the grid can load'
    $downloadUrls=& $module { $script:downloadUrls.ToArray() }
    Assert ($downloadUrls -contains 'https://cdn2.steamgriddb.com/thumb.png' -and $downloadUrls -contains 'https://cdn2.steamgriddb.com/fallback.png' -and $downloadUrls -notcontains 'https://untrusted.example/thumb.png') 'Thumbnail downloads use provider thumbnails and reject untrusted thumbnail URLs'
    $matchOptions=@([pscustomobject]@{id=10;name='Valheim Dedicated Server'},[pscustomobject]@{id=20;name='Valheim'})
    Assert ((Get-LikelyArtworkMatchIndex 'Valheim' $matchOptions) -eq 1) 'Automatic selection prefers the exact game over a dedicated server'
    Assert ((Get-LikelyArtworkMatchIndex 'Valheim' $matchOptions 10) -eq 0) 'A saved match is respected when present in search results'
    Assert ((Get-LikelyArtworkMatchIndex 'Unknown' @()) -eq -1) 'Empty searches have no automatic selection'
    Assert ((Get-LikelyArtworkMatchIndex 'Example Game Deluxe' @([pscustomobject]@{id=1;name='Example Game'},[pscustomobject]@{id=2;name='Example Game Deluxe'})) -eq 1) 'Automatic selection distinguishes game editions'
    Assert ((Get-LikelyArtworkMatchIndex 'Example Game' @([pscustomobject]@{id=1;name='Different Title'},[pscustomobject]@{id=2;name='Example Game Remastered'})) -eq 1) 'Likely selection uses title overlap when no exact match exists'
    Assert ((Get-LikelyArtworkMatchIndex 'Game' @([pscustomobject]@{id=1;name='Game Demo'},[pscustomobject]@{id=2;name='Game Complete'})) -eq 1) 'Automatic selection downranks demos when the query is for the game'
    & $module {$script:requests=New-Object 'System.Collections.Generic.List[string]';function script:Invoke-Sgdb($Path,$ApiKey){$script:requests.Add($Path);@()}}
    $category=Get-ArtworkCandidates 123 'fixture-key' 'Hero'
    $categoryRequests=@(& $module {$script:requests.ToArray()})
    Assert ($category.Count -eq 1 -and $category.ContainsKey('Hero') -and $categoryRequests.Count -eq 1 -and $categoryRequests[0] -like '/heroes/game/123*') 'Changing category can fetch only that category instead of all five'
    $cancel=New-Object Threading.CancellationTokenSource;$cancel.Cancel()
    try {Assert (@(Get-ArtworkThumbnails @([pscustomobject]@{id=99;url='https://cdn2.steamgriddb.com/unused.png'}) $root $cancel).Count -eq 0) 'Obsolete thumbnail requests stop before downloading more images'}finally{$cancel.Dispose()}
    "`nAll $script:passed artwork checks passed. No real artwork or API credentials were used."
} finally {
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
