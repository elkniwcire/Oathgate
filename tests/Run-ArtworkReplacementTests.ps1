$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Artwork.psm1') -Force
Add-Type -AssemblyName System.Drawing
$module=Get-Module SteamNite.Artwork
& $module {function script:Test-SteamRunning {$false}}
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\replace-art-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
try{
    $exe=Join-Path $root 'gamelaunchhelper.exe';[IO.File]::WriteAllBytes($exe,[byte[]]@())
    $draft=New-Object SteamNite.ShortcutDraft;$draft.Title='Replacement fixture';$draft.Exe='"'+$exe+'"';$draft.StartDir='"'+$root+'"';$draft.LaunchOptions='';$draft.ManagedId='steamnite:xbox:replace-art';$draft.AppId=[SteamNite.SteamShortcuts]::AppId($draft.Exe,$draft.Title)
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');SteamRoot=$root;AccountId='fixture'}
    $external=Join-Path $root 'external-icon.ico';[IO.File]::WriteAllBytes($external,[byte[]]@(1,2,3))
    $file=[SteamNite.SteamShortcuts]::new(([SteamNite.SteamShortcuts]::new([byte[]]$null)).Append([SteamNite.ShortcutDraft[]]@($draft)))
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$file.WithIcon($draft.AppId,$external))
    $game=[pscustomobject]@{Id='xbox:replace-art';Title=$draft.Title;Method='Xbox launch helper';Target=$exe;InstallPath=$root;Status='Ready to test'}
    $context=Get-SteamArtworkContext $profile $game
    [void][IO.Directory]::CreateDirectory($context.GridDirectory)
    $source=Join-Path $root 'new.png';$bitmap=New-Object Drawing.Bitmap(8,8)
    try{$bitmap.SetPixel(0,0,[Drawing.Color]::Red);$bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $cover=Join-Path $context.GridDirectory ((Get-ArtworkStem $context.AppId 'Cover')+'.jpg');[IO.File]::WriteAllBytes($cover,[byte[]]@(4,5,6))
    $alternative=[IO.Path]::ChangeExtension($cover,'.webp');[IO.File]::WriteAllBytes($alternative,[byte[]]@(7,8,9))
    $hero=Join-Path $context.GridDirectory ((Get-ArtworkStem $context.AppId 'Hero')+'.png');[IO.File]::WriteAllBytes($hero,[byte[]]@(10,11))
    $selection=@{Cover=[pscustomobject]@{Path=$source}}
    $preserved=Save-SteamArtwork $context $selection
    Assert ($preserved.Skipped -contains 'Cover' -and (Test-Path $cover)) 'Default fill-missing application still preserves existing artwork'
    $result=Save-SteamArtwork $context $selection -Replace
    Assert ($result.Replaced -contains 'Cover' -and $result.Added.Count -eq 0) 'Explicit replacement reports replaced categories separately'
    $newCover=Join-Path $context.GridDirectory ((Get-ArtworkStem $context.AppId 'Cover')+'.png')
    Assert ((Test-Path $newCover) -and -not (Test-Path $cover) -and -not (Test-Path $alternative)) 'Replacement leaves one normalized PNG instead of competing old formats'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $result.ArtworkBackupPath ([IO.Path]::GetFileName($cover))))) -eq 'BAUG') 'Original artwork bytes are retained exactly in the backup'
    Assert (Test-Path (Join-Path $result.ArtworkBackupPath ([IO.Path]::GetFileName($alternative)))) 'All existing formats for the replaced slot are backed up'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($hero)) -eq 'Cgs=') 'Unselected artwork categories remain untouched'
    $again=Save-SteamArtwork $context $selection -Replace
    Assert ($again.Replaced -contains 'Cover' -and (Test-Path $again.ArtworkBackupPath)) 'Artwork can be replaced repeatedly without reopening the editor'
    $before=(Get-FileHash $newCover).Hash
    $invalid=Join-Path $root 'invalid.png';[IO.File]::WriteAllText($invalid,'not an image')
    Assert (Throws {Save-SteamArtwork $context @{Cover=[pscustomobject]@{Path=$source};Hero=[pscustomobject]@{Path=$invalid}} -Replace}) 'Every selected new image must validate before replacement begins'
    Assert ((Get-FileHash $newCover).Hash -eq $before -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($hero)) -eq 'Cgs=') 'Validation failure preserves all original slots'
    & $module {$script:checks=0;function script:Test-SteamRunning {$script:checks++;return $script:checks -ge 4}}
    Assert (Throws {Save-SteamArtwork $context $selection -Replace}) 'Steam restarting during replacement aborts the operation'
    Assert ((Get-FileHash $newCover).Hash -eq $before) 'An interrupted replacement restores the prior artwork exactly'
    & $module {function script:Test-SteamRunning {$false}}
    $shortcutBefore=[IO.File]::ReadAllBytes($profile.ShortcutPath)
    $iconResult=Save-SteamArtwork $context @{Icon=[pscustomobject]@{Path=$source}} -Replace
    Assert ($iconResult.Replaced -contains 'Icon' -and (Test-Path $iconResult.BackupPath)) 'Replacing a custom icon backs up its shortcut registration'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($external)) -eq 'AQID') 'An external custom icon file is never moved or deleted'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($iconResult.BackupPath)) -eq [Convert]::ToBase64String($shortcutBefore)) 'The icon shortcut backup retains the original pointer and all other fields'
    $updated=Get-SteamArtworkContext $profile $game
    Assert ($updated.Icon -eq (Join-Path $context.GridDirectory ((Get-ArtworkStem $context.AppId 'Icon')+'.png'))) 'The shortcut now references the newly selected icon'
    Assert (Throws {Save-SteamArtwork $context $selection -Replace}) 'A stale shortcut context cannot replace artwork'
    $added=Save-SteamArtwork $updated @{Logo=[pscustomobject]@{Path=$source}} -Replace
    Assert ($added.Added -contains 'Logo' -and $added.Replaced.Count -eq 0) 'Manual apply also adds missing categories without treating them as replacements'
    Assert (@(Get-ChildItem $context.GridDirectory -Filter '*.tmp' -File).Count -eq 0) 'Successful and failed replacements leave no staging files'
    "`nAll $script:passed artwork replacement checks passed. No real artwork or Steam files changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
