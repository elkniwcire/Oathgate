param([Parameter(Mandatory)][string]$Workspace,[switch]$Fixture)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try{
    if($Fixture){
        @{Games=@(@{Id='fixture:one';Title='Fixture game';Platform='GOG';InstallState='Installed';SteamSyncStatus='Not synced';ArtworkStatus='Not linked';NeedsAttention=$true;CoverPath='';HeroPath='';AttentionDetail='Not in Steam';Method='Fixture';InstallPath='C:\Fixture';Ignored=$false});Profiles=@();ProfileLabel='No account';Notices=@('Fixture data');ScannedAt=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8 -Compress;exit 0
    }
    Import-Module (Join-Path $Workspace 'src\SteamNite.Core.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Steam.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Artwork.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Removal.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Library.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Settings.psm1') -Force
    Import-Module (Join-Path $Workspace 'src\SteamNite.Storage.psm1')
    $data=Initialize-OathgateStorage -LegacyDirectory (Join-Path $Workspace 'data');$settings=Get-AppSettings (Join-Path $data 'settings.json') -Recover
    $scan=Get-GameScan -ExtraRoots @($settings.ExtraRoots)
    $profiles=@(Get-SteamProfiles);$profile=$null
    $matches=@($profiles|Where-Object ShortcutPath -eq $settings.SteamShortcutPath)
    if($matches.Count -eq 1){$profile=$matches[0]}elseif(-not $settings.SteamShortcutPath -and $profiles.Count -eq 1){$profile=$profiles[0]}
    $removal=if($profile){New-SteamRemovalPlan $profile (Join-Path $data 'install-history.json')}else{$null}
    $library=@(Get-UnifiedGameLibrary -InstalledGames $scan.Games -Profile $profile -RemovalPlan $removal -HistoryPath (Join-Path $data 'install-history.json'))
    foreach($game in $library){
        $cover='';$hero=''
        if($profile -and $null -ne $game.SteamAppId){
            $context=[pscustomobject]@{AppId=$game.SteamAppId;GridDirectory=(Join-Path (Split-Path $profile.ShortcutPath) 'grid')}
            $cover=@(Get-ExistingArtwork $context 'Cover'|Where-Object {[IO.Path]::GetExtension($_) -in @('.png','.jpg','.jpeg')})|Select-Object -First 1
            $hero=@(Get-ExistingArtwork $context 'Hero'|Where-Object {[IO.Path]::GetExtension($_) -in @('.png','.jpg','.jpeg')})|Select-Object -First 1
        }
        $game|Add-Member -Force NoteProperty CoverPath ([string]$cover);$game|Add-Member -Force NoteProperty HeroPath ([string]$hero)
    }
    # Read-only bridge: no history/settings writes, API keys, process launches or Steam writes.
    @{Games=$library;Profiles=$profiles;ProfileShortcutPath=$(if($profile){$profile.ShortcutPath}else{''});ProfileLabel=$(if($profile){$profile.Label}else{'Choose an account in settings'});Notices=@($scan.Diagnostics);ScannedAt=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10 -Compress
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
