$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Steam.psm1')
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
if (-not ('SteamNite.ArtworkHttp' -as [type])) {
    if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -Path (Join-Path $PSScriptRoot 'ArtworkHttp.cs') }
    else { Add-Type -Path (Join-Path $PSScriptRoot 'ArtworkHttp.cs') -ReferencedAssemblies 'System.Net.Http.dll' }
}

function Set-ArtworkApiKey([string]$DataDirectory, [string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { throw 'Enter a SteamGridDB API key first.' }
    [void](New-Item -ItemType Directory -Path $DataDirectory -Force)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Key.Trim())
    try {
        $protected = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $path=Join-Path $DataDirectory 'steamgriddb.key';$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            [IO.File]::WriteAllBytes($temp, $protected)
            if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temp,$path) }
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}
function Get-ArtworkApiKey([string]$DataDirectory) {
    $path = Join-Path $DataDirectory 'steamgriddb.key'
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    try { $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser) }
    catch [Security.Cryptography.CryptographicException] { return '' }
    catch [IO.IOException] { return '' }
    catch [UnauthorizedAccessException] { return '' }
    try { return [Text.Encoding]::UTF8.GetString($plain) } finally { [Array]::Clear($plain, 0, $plain.Length) }
}
function Remove-ArtworkApiKey([string]$DataDirectory) {
    $path = Join-Path $DataDirectory 'steamgriddb.key'
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
function Invoke-Sgdb([string]$Path, [string]$ApiKey) {
    try { $result = [SteamNite.ArtworkHttp]::Api($Path, $ApiKey.Trim()) | ConvertFrom-Json }
    catch {
        # Never include request headers or user credentials in diagnostic text.
        $message = $_.Exception.GetBaseException().Message
        if ($message -match 'SteamGridDB|size limit|API request') { throw $message }
        throw 'SteamGridDB could not be reached. Check your connection and try again.'
    }
    if (-not $result.success) { throw 'SteamGridDB could not complete the request.' }
    return $result.data
}
function Search-ArtworkGames([string]$Query, [string]$ApiKey) {
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'Enter a game title to search.' }
    if ($Query.Length -gt 150) { throw 'Search titles must be 150 characters or less.' }
    @(Invoke-Sgdb ('/search/autocomplete/' + [uri]::EscapeDataString($Query.Trim())) $ApiKey)
}
function Get-ArtworkCandidates([long]$GameId, [string]$ApiKey, [string]$Kind = '') {
    if ($GameId -le 0) { throw 'Choose a SteamGridDB game match first.' }
    $sets = @{}
    $kinds=if ($Kind) { if ($Kind -notin @('Cover','Wide','Hero','Logo','Icon')) { throw 'Unknown artwork type.' }; @($Kind) } else { @('Cover','Wide','Hero','Logo','Icon') }
    foreach ($kind in $kinds) {
        $endpoint = switch ($kind) { 'Cover' {'grids'} 'Wide' {'grids'} 'Hero' {'heroes'} 'Logo' {'logos'} 'Icon' {'icons'} }
        # Logos and icons reject JPEG as a filter even though grids/heroes accept it.
        $mimes = if ($kind -in @('Logo','Icon')) { 'image%2Fpng' } else { 'image%2Fpng,image%2Fjpeg' }
        $filters = '?types=static&mimes=' + $mimes + '&nsfw=false&humor=false&epilepsy=false'
        if ($kind -eq 'Cover') { $filters += '&dimensions=600x900' }
        if ($kind -eq 'Wide') { $filters += '&dimensions=920x430,460x215' }
        $items = @(Invoke-Sgdb ('/' + $endpoint + '/game/' + $GameId + $filters) $ApiKey)
        # Keep the provider's ranked order. Vote/score values may be hidden (all zero);
        # locally sorting those values can scramble SteamGridDB's recommendations.
        $sets[$kind] = @($items | Where-Object { [SteamNite.ArtworkHttp]::AllowedImageUrl([string]$_.url) } | Select-Object -First 20)
    }
    return $sets
}
function Get-ArtworkThumbnails([object[]]$Assets, [string]$CacheDirectory, $Cancellation = $null) {
    foreach ($asset in $Assets) {
        if ($Cancellation -and $Cancellation.IsCancellationRequested) { return }
        try {
            $url=if ([SteamNite.ArtworkHttp]::AllowedImageUrl([string]$asset.thumb)) { $asset.thumb } else { $asset.url }
            $path=Get-CachedArtwork ([pscustomobject]@{url=$url}) $CacheDirectory
            [pscustomobject]@{Id=$asset.id;Path=$path;Error=''}
        } catch { [pscustomobject]@{Id=$asset.id;Path='';Error='Thumbnail unavailable'} }
    }
}
function Get-LikelyArtworkMatchIndex {
    param([string]$Title,[object[]]$Matches,[long]$SavedId=0)
    if (-not $Matches.Count) { return -1 }
    $normalized=[regex]::Replace($Title.Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant(),'[^\p{L}\p{Nd}]','')
    $tokens=@([regex]::Matches($Title.ToLowerInvariant(),'[\p{L}\p{Nd}]+') | ForEach-Object {$_.Value} | Select-Object -Unique)
    $bestIndex=0; $bestScore=[double]::NegativeInfinity
    for($i=0;$i -lt $Matches.Count;$i++) {
        if ($SavedId -gt 0 -and [long]$Matches[$i].id -eq $SavedId) { return $i }
        $name=[string]$Matches[$i].name
        $key=[regex]::Replace($name.Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant(),'[^\p{L}\p{Nd}]','')
        if ($key -eq $normalized) { $score=1000.0 }
        else {
            $words=@([regex]::Matches($name.ToLowerInvariant(),'[\p{L}\p{Nd}]+') | ForEach-Object {$_.Value} | Select-Object -Unique)
            $overlap=@($tokens | Where-Object {$_ -in $words}).Count
            $score=if (($tokens.Count+$words.Count) -gt 0) { 200.0*$overlap/($tokens.Count+$words.Count) } else { 0.0 }
            foreach($special in @('server','soundtrack','demo','trailer')) { if ($special -in $words -and $special -notin $tokens) { $score-=50 } }
        }
        if ($score -gt $bestScore) { $bestScore=$score;$bestIndex=$i }
    }
    return $bestIndex
}
function Get-RecommendedArtwork {
    param([hashtable]$Sets, $Context, [string]$CacheDirectory,[switch]$ReplaceExisting)
    $selections=@{}; $unavailable=New-Object 'System.Collections.Generic.List[string]'
    $preserved=New-Object 'System.Collections.Generic.List[string]'
    foreach ($kind in @('Cover','Wide','Hero','Logo','Icon')) {
        if (-not $ReplaceExisting -and (@(Get-ExistingArtwork $Context $kind).Count -gt 0 -or ($kind -eq 'Icon' -and $Context.Icon))) { $preserved.Add($kind); continue }
        $found=$false
        foreach ($asset in @($Sets[$kind])) {
            if ($null -eq $asset) { continue }
            try {
                $path=Get-CachedArtwork $asset $CacheDirectory
                $selections[$kind]=[pscustomobject]@{Path=$path;AssetId=$asset.id;Url=$asset.url;Author=$asset.author.name}
                $found=$true; break
            } catch { continue }
        }
        if (-not $found) { $unavailable.Add($kind) }
    }
    [pscustomobject]@{Selections=$selections;Unavailable=$unavailable.ToArray();Preserved=$preserved.ToArray()}
}
function Get-CachedArtwork([object]$Asset, [string]$CacheDirectory) {
    if (-not [SteamNite.ArtworkHttp]::AllowedImageUrl([string]$Asset.url)) { throw 'Invalid artwork URL.' }
    [void](New-Item -ItemType Directory -Path $CacheDirectory -Force)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $name = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$Asset.url))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $path = Join-Path $CacheDirectory ($name + '.png')
    if (-not (Test-Path -LiteralPath $path)) {
        $raw = Join-Path $CacheDirectory ($name + '.' + [guid]::NewGuid().ToString('N') + '.download')
        $png = $raw + '.png'
        try {
            [SteamNite.ArtworkHttp]::Download([string]$Asset.url, $raw)
            ConvertTo-ArtworkPng $raw $png
            # Only the validated PNG is promoted into the reusable cache.
            if (-not (Test-Path -LiteralPath $path)) { [IO.File]::Move($png,$path) }
        } finally { foreach ($p in @($raw,$png)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } }
    }
    return $path
}
function ConvertTo-ArtworkPng([string]$Source, [string]$Destination) {
    if ((Get-Item -LiteralPath $Source).Length -gt 20MB) { throw 'Artwork exceeds the 20 MB size limit.' }
    $image = [Drawing.Image]::FromFile($Source)
    try {
        if ($image.Width -le 0 -or $image.Height -le 0 -or ([long]$image.Width * $image.Height) -gt 40000000) { throw 'Artwork dimensions exceed the supported limit.' }
        if ($image.RawFormat.Guid -notin @([Drawing.Imaging.ImageFormat]::Png.Guid,[Drawing.Imaging.ImageFormat]::Jpeg.Guid)) { throw 'This version supports static PNG and JPEG artwork.' }
        $image.Save($Destination,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $image.Dispose() }
}
function Get-SteamArtworkContext($Profile, $Game) {
    $plan = New-SteamSyncPlan -Profile $Profile -Games @($Game)
    $draft = $plan.Rows[0].Draft
    if (-not $draft) { throw 'This game has no usable launch recipe.' }
    $snapshot = Get-ShortcutSnapshot $Profile.ShortcutPath
    $matches = @(Find-SteamGameShortcuts -Items $snapshot.File.Items.ToArray() -GameId $Game.Id -Draft $draft)
    if ($matches.Count -ne 1) { throw 'Sync this game to Steam first. Artwork requires one unambiguous matching Steam shortcut.' }
    [pscustomobject]@{ Profile=$Profile; Game=$Game; AppId=$matches[0].AppId; ShortcutHash=$snapshot.Hash; Icon=$matches[0].Icon; GridDirectory=(Join-Path (Split-Path $Profile.ShortcutPath) 'grid') }
}
function Get-ArtworkStem([uint32]$AppId, [string]$Kind) {
    switch ($Kind) {
        'Cover' { return "${AppId}p" }
        'Wide' { return "$AppId" }
        'Hero' { return "${AppId}_hero" }
        'Logo' { return "${AppId}_logo" }
        'Icon' { return "${AppId}_icon" }
        default { throw 'Unknown artwork type.' }
    }
}
function Get-ExistingArtwork($Context, [string]$Kind) {
    $stem = Get-ArtworkStem $Context.AppId $Kind
    if (Test-Path -LiteralPath $Context.GridDirectory) {
        Get-ChildItem -LiteralPath $Context.GridDirectory -File | Where-Object { $_.BaseName -eq $stem -and $_.Extension -in @('.png','.jpg','.jpeg','.webp','.tga','.gif','.ico') } | ForEach-Object { $_.FullName }
    }
}
function Save-SteamArtwork {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][hashtable]$Selections,[switch]$Replace)
    if($Replace){return Save-SteamArtworkReplacement $Context $Selections}
    if($Context.Game.Id -in @(Get-IgnoredGameIds)){throw 'This game is ignored. Unignore it before changing artwork.'}
    # This first version fills missing slots only. Existing images and icon overrides are always preserved.
    if (Test-SteamRunning) { throw 'Exit Steam completely with Steam > Exit before applying artwork.' }
    if ((Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash) { throw 'Steam shortcuts changed. Close and reopen the artwork window before applying.' }
    $added = New-Object 'System.Collections.Generic.List[string]'
    $skipped = New-Object 'System.Collections.Generic.List[string]'
    $pending = New-Object 'System.Collections.Generic.List[object]'
    foreach ($kind in $Selections.Keys) {
        $stem = Get-ArtworkStem $Context.AppId $kind
        $existing = @(Get-ExistingArtwork $Context $kind)
        if ($existing.Count -gt 0 -or ($kind -eq 'Icon' -and $Context.Icon)) { $skipped.Add($kind); continue }
        $source = [string]$Selections[$kind].Path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ('Selected '+$kind+' artwork is no longer cached. Choose it again.') }
        $pending.Add([pscustomobject]@{Kind=$kind; Source=$source; Destination=(Join-Path $Context.GridDirectory ($stem+'.png'))})
    }
    if ($pending.Count -eq 0) { return [pscustomobject]@{Added=@();Skipped=$skipped.ToArray();BackupPath=''} }
    [void](New-Item -ItemType Directory -Path $Context.GridDirectory -Force)
    $staged = New-Object 'System.Collections.Generic.List[object]'
    $committed = New-Object 'System.Collections.Generic.List[string]'
    $backup = ''; $iconOutput=$null
    try {
        foreach ($item in $pending) {
            $temp=$item.Destination+'.steamnite-'+[guid]::NewGuid().ToString('N')+'.tmp'
            $staged.Add([pscustomobject]@{Item=$item;Temp=$temp})
            ConvertTo-ArtworkPng $item.Source $temp
            if ($item.Kind -eq 'Icon') { $iconOutput=(Get-ShortcutSnapshot $Context.Profile.ShortcutPath).File.WithIcon($Context.AppId,$item.Destination) }
        }
        if (Test-SteamRunning) { throw 'Steam started during artwork preparation. No artwork was applied.' }
        if ((Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash) { throw 'Steam shortcuts changed. Reopen the artwork window.' }
        foreach ($entry in $staged) {
            if (@(Get-ExistingArtwork $Context $entry.Item.Kind).Count -gt 0) { throw 'Artwork changed while applying. Existing artwork has been preserved.' }
            [IO.File]::Move($entry.Temp,$entry.Item.Destination)
            $committed.Add($entry.Item.Destination); $added.Add($entry.Item.Kind)
        }
        if ($null -ne $iconOutput) {
            $shortcutPath=$Context.Profile.ShortcutPath
            $temp=$shortcutPath+'.steamnite-art-'+[guid]::NewGuid().ToString('N')+'.tmp'
            $staged.Add([pscustomobject]@{Item=$null;Temp=$temp})
            [IO.File]::WriteAllBytes($temp,$iconOutput)
            if ((Test-SteamRunning) -or (Get-ShortcutSnapshot $shortcutPath).Hash -ne $Context.ShortcutHash) { throw 'Steam state changed during icon update. Artwork changes have been rolled back.' }
            $backup=$shortcutPath+'.steamnite-art-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.bak'
            [IO.File]::Replace($temp,$shortcutPath,$backup)
        }
        [pscustomobject]@{Added=$added.ToArray();Skipped=$skipped.ToArray();BackupPath=$backup}
    } catch {
        # Roll back only the new files created by this operation; never remove pre-existing art.
        foreach ($path in $committed) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
        throw
    } finally { foreach ($entry in $staged) { if (Test-Path -LiteralPath $entry.Temp) { Remove-Item -LiteralPath $entry.Temp -Force } } }
}
function Get-ArtworkFileSignature([string[]]$Paths) {
    return (@($Paths|Sort-Object|ForEach-Object {$_+'|'+(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}) -join "`n")
}
function Save-SteamArtworkReplacement {
    param($Context,[hashtable]$Selections)
    if($Context.Game.Id -in @(Get-IgnoredGameIds)){throw 'This game is ignored. Unignore it before changing artwork.'}
    if(Test-SteamRunning){throw 'Exit Steam before replacing artwork.'}
    if((Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash){throw 'Steam shortcuts changed. Refresh the artwork context.'}
    if(-not $Selections.Count){return [pscustomobject]@{Added=@();Replaced=@();Skipped=@();BackupPath='';ArtworkBackupPath=''}}
    [void][IO.Directory]::CreateDirectory($Context.GridDirectory)
    $staged=New-Object 'System.Collections.Generic.List[object]';$moved=New-Object 'System.Collections.Generic.List[object]';$committed=New-Object 'System.Collections.Generic.List[object]'
    $added=@();$replaced=@();$backup='';$backupDirectory=Join-Path $Context.GridDirectory ('.steamnite-backups\'+[guid]::NewGuid().ToString('N'));$iconOutput=$null
    try{
        foreach($kind in $Selections.Keys){
            $stem=Get-ArtworkStem $Context.AppId $kind
            $existing=@(Get-ExistingArtwork $Context $kind)
            $destination=Join-Path $Context.GridDirectory ($stem+'.png')
            $temp=$destination+'.steamnite-'+[guid]::NewGuid().ToString('N')+'.tmp'
            $entry=[pscustomobject]@{Kind=$kind;Existing=$existing;Signature=(Get-ArtworkFileSignature $existing);Destination=$destination;Temp=$temp}
            $staged.Add($entry)
            ConvertTo-ArtworkPng ([string]$Selections[$kind].Path) $temp
            if($existing.Count -or ($kind -eq 'Icon' -and $Context.Icon)){$replaced+=$kind}else{$added+=$kind}
            if($kind -eq 'Icon'){$iconOutput=(Get-ShortcutSnapshot $Context.Profile.ShortcutPath).File.WithIcon($Context.AppId,$destination)}
        }
        if((Test-SteamRunning) -or (Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash){throw 'Steam state changed. No artwork was replaced.'}
        [void][IO.Directory]::CreateDirectory($backupDirectory)
        @{AppId=$Context.AppId;PreviousIcon=$Context.Icon;CreatedAt=[datetime]::UtcNow.ToString('o');Files=@($staged|ForEach-Object {$_.Existing})}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $backupDirectory 'backup.json') -Encoding UTF8
        foreach($entry in $staged){
            $now=@(Get-ExistingArtwork $Context $entry.Kind)
            if((Get-ArtworkFileSignature $now) -cne $entry.Signature){throw 'Artwork changed since replacement was prepared. Refresh and try again.'}
            if(Test-SteamRunning){throw 'Steam started during replacement. Artwork changes are being rolled back.'}
            foreach($path in $entry.Existing){
                $target=Join-Path $backupDirectory ([IO.Path]::GetFileName($path))
                [IO.File]::Move($path,$target);$moved.Add([pscustomobject]@{Original=$path;Backup=$target})
            }
            $hash=(Get-FileHash -LiteralPath $entry.Temp -Algorithm SHA256).Hash
            [IO.File]::Move($entry.Temp,$entry.Destination);$committed.Add([pscustomobject]@{Path=$entry.Destination;Hash=$hash})
        }
        if((Test-SteamRunning) -or (Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash){throw 'Steam state changed during replacement. Artwork changes are being rolled back.'}
        if($null -ne $iconOutput){
            $temp=$Context.Profile.ShortcutPath+'.steamnite-art-'+[guid]::NewGuid().ToString('N')+'.tmp'
            $staged.Add([pscustomobject]@{Temp=$temp})
            [IO.File]::WriteAllBytes($temp,$iconOutput)
            if((Test-SteamRunning) -or (Get-ShortcutSnapshot $Context.Profile.ShortcutPath).Hash -ne $Context.ShortcutHash){throw 'Steam state changed during icon replacement.'}
            $backup=$Context.Profile.ShortcutPath+'.steamnite-art-'+[guid]::NewGuid().ToString('N')+'.bak'
            [IO.File]::Replace($temp,$Context.Profile.ShortcutPath,$backup)
        }
        return [pscustomobject]@{Added=$added;Replaced=$replaced;Skipped=@();BackupPath=$backup;ArtworkBackupPath=$backupDirectory}
    }catch{
        $failure=$_
        foreach($file in $committed){if((Test-Path -LiteralPath $file.Path) -and (Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash -eq $file.Hash){Remove-Item -LiteralPath $file.Path -Force}}
        foreach($file in $moved){if(-not (Test-Path -LiteralPath $file.Original)){[IO.File]::Move($file.Backup,$file.Original)}}
        throw ('Artwork replacement failed: '+$failure.Exception.GetBaseException().Message+' Any retained originals are in '+$backupDirectory)
    }finally{foreach($entry in $staged){if(Test-Path -LiteralPath $entry.Temp){Remove-Item -LiteralPath $entry.Temp -Force}}}
}
Export-ModuleMember -Function Set-ArtworkApiKey, Get-ArtworkApiKey, Remove-ArtworkApiKey, Search-ArtworkGames, Get-ArtworkCandidates, Get-CachedArtwork, ConvertTo-ArtworkPng, Get-SteamArtworkContext, Get-ArtworkStem, Get-ExistingArtwork, Save-SteamArtwork, Get-ArtworkThumbnails, Get-RecommendedArtwork, Get-LikelyArtworkMatchIndex
