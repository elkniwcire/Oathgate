$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Removal.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Library.psm1') -Force
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\launchers-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Write-Gog($Folder,$Manifest){[void][IO.Directory]::CreateDirectory($Folder);$path=Join-Path $Folder ('goggame-'+$Manifest.gameId+'.info');$Manifest|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $path -Encoding UTF8;return $path}
function Write-Ea($Folder,[string]$Xml){$dir=Join-Path $Folder '__Installer';[void][IO.Directory]::CreateDirectory($dir);$path=Join-Path $dir 'installerdata.xml';$Xml|Set-Content -LiteralPath $path -Encoding UTF8;return $path}
function Record($Id,$Folder,$Title=''){[pscustomobject]@{Key=$Id;Values=@{InstallDir=$Folder;DisplayName=$Title};Evidence=('LocalMachine/Registry32/SOFTWARE\Origin Games/'+$Id)}}
function Snapshot($Records=@(),$Complete=$true){[pscustomobject]@{Records=@($Records);Complete=$Complete;Failed=(-not $Complete);Roots=@('SOFTWARE\Origin Games')}}
try{
    $core=Get-Module SteamNite.Core
    Assert ($null -eq (& $core {Get-LauncherUninstallIdentity 'GOG' 'Git_is1' 'The Git Development Community' 'Git'})) 'GOG uninstall discovery excludes unrelated desktop applications'
    Assert ((& $core {Get-LauncherUninstallIdentity 'GOG' '12345_is1' 'GOG.com' 'Game'}) -eq '12345') 'Offline GOG uninstall registrations map to numeric game identities'
    Assert ((& $core {Get-LauncherUninstallIdentity 'Ubisoft' 'Uplay Install 5678' 'Ubisoft' 'Game'}) -eq '5678') 'Ubisoft uninstall registrations retain the actual installed product ID'
    Assert ($null -eq (& $core {Get-LauncherUninstallIdentity 'EA' 'Client' 'Electronic Arts' 'EA app'})) 'The EA app itself is not imported as a game'
    Assert ($null -eq (& $core {Get-LauncherUninstallIdentity 'EA' 'Other' 'Other Publisher' 'Other Game'})) 'EA uninstall discovery excludes other publishers'
    $gogRoot=Join-Path $root 'GOG Games';$gogFolder=Join-Path $gogRoot 'Fixture';[void][IO.Directory]::CreateDirectory($gogFolder)
    $exe=Join-Path $gogFolder 'Game.exe';[IO.File]::WriteAllBytes($exe,[byte[]]@())
    $manifest=@{gameId='12345';rootGameId='12345';name='GOG Fixture';playTasks=@(@{isPrimary=$true;type='FileTask';path='Game.exe';arguments='--edition "deluxe edition"'})}
    $gogPath=Write-Gog $gogFolder $manifest
    $game=Get-GogManifestGame $gogPath
    Assert ($game.Id -eq 'gog:12345' -and $game.Title -eq 'GOG Fixture' -and $game.Method -eq 'GOG executable') 'GOG identity and title come from the manifest'
    $launch=Start-DetectedGame $game -DryRun
    Assert ($launch.FileName -eq $exe -and $launch.WorkingDirectory -eq $gogFolder -and $launch.Arguments -eq '--edition "deluxe edition"') 'Offline GOG launch preserves primary task arguments and working folder'
    $client=Join-Path $root 'GalaxyClient.exe';[IO.File]::WriteAllBytes($client,[byte[]]@())
    $galaxy=Get-GogManifestGame $gogPath $client
    $launch=Start-DetectedGame $galaxy -DryRun
    Assert ($galaxy.Method -eq 'GOG Galaxy' -and $launch.FileName -eq $client -and $launch.Arguments.Contains('/gameId=12345')) 'Installed Galaxy is preferred for client features and launch-task dispatch'
    $manifest.playTasks+=@{isPrimary=$false;type='FileTask';path='uninstall.exe'}
    $gogPath=Write-Gog $gogFolder $manifest
    Assert ((Get-GogManifestGame $gogPath).Target -eq $exe) 'GOG ignores secondary support and uninstall tasks'
    $manifest.playTasks+=@{isPrimary=$true;type='FileTask';path='Other.exe'}
    $gogPath=Write-Gog $gogFolder $manifest
    Assert ((Get-GogManifestGame $gogPath).Status -eq 'Unresolved') 'Multiple distinct primary EXEs require a decision without Galaxy'
    Assert ((Get-GogManifestGame $gogPath $client).Method -eq 'GOG Galaxy') 'Galaxy can resolve multiple primary tasks itself'
    $manifest.rootGameId='999';$gogPath=Write-Gog $gogFolder $manifest
    Assert ($null -eq (Get-GogManifestGame $gogPath)) 'GOG DLC manifests do not create separate game shortcuts'
    $manifest.rootGameId='12345';$manifest.playTasks=@(@{isPrimary=$true;type='FileTask';path='..\Outside.exe'})
    $gogPath=Write-Gog $gogFolder $manifest
    Assert (Throws {Get-GogManifestGame $gogPath}) 'GOG manifest launch paths cannot escape the install directory'
    $manifest.playTasks=@(@{isPrimary=$true;type='FileTask';path='Game.exe';workingDir='..\outside'})
    $gogPath=Write-Gog $gogFolder $manifest
    Assert (Throws {Get-GogManifestGame $gogPath}) 'GOG working folders cannot escape the installation'
    $manifest.playTasks=@(@{isPrimary=$true;type='FileTask';path='missing.exe'})
    $gogPath=Write-Gog $gogFolder $manifest
    Assert ((Get-GogManifestGame $gogPath).Status -eq 'Unresolved') 'A missing GOG primary EXE cannot be labeled ready'
    $manifest.playTasks=@();$gogPath=Write-Gog $gogFolder $manifest
    Assert ($null -eq (Get-GogManifestGame $gogPath)) 'GOG content-only manifests are skipped'
    $manifest.playTasks=@(@{isPrimary=$true;type='FileTask';path='Game.exe'});$gogPath=Write-Gog $gogFolder $manifest
    $ubiFolder=Join-Path $root 'Ubisoft Edition';[void][IO.Directory]::CreateDirectory($ubiFolder)
    $ubi=Get-UbisoftRegistryGame (Record '5678' $ubiFolder 'Ubisoft Fixture Deluxe')
    Assert ($ubi.Id -eq 'ubisoft:5678' -and $ubi.Target -eq 'uplay://launch/5678/0') 'Ubisoft dispatches the installed product ID instead of guessing an executable'
    Assert ((Start-DetectedGame $ubi -DryRun).FileName -eq $ubi.Target) 'Ubisoft launch hands edition and renderer selection to Connect'
    Assert ($null -eq (Get-UbisoftRegistryGame (Record 'invalid/id' $ubiFolder))) 'Malformed Ubisoft product IDs cannot become launch commands'
    Assert ($null -eq (Get-UbisoftRegistryGame (Record '5679' (Join-Path $root 'missing')))) 'Stale Ubisoft registrations without installation folders are skipped'
    Assert (Throws {Get-UbisoftRegistryGame (Record '5680' 'relative\folder')}) 'Relative registry installation paths are rejected'
    $eaRoot=Join-Path $root 'EA Games';$eaFolder=Join-Path $eaRoot 'EA Fixture'
    $eaPath=Write-Ea $eaFolder '<DiPManifest><gameTitle>EA Fixture Deluxe</gameTitle><contentIDs><contentID>123456</contentID><contentID>fixture_eu</contentID><contentID>123456</contentID></contentIDs></DiPManifest>'
    $ea=Get-EaManifestGame $eaPath
    Assert ($ea.Id -eq 'ea:123456' -and $ea.Title -eq 'EA Fixture Deluxe' -and $ea.InstallPath -eq $eaFolder) 'EA installed identity and title come from the local installer manifest'
    Assert ($ea.Target -eq 'origin2://game/launch/?offerIds=123456,fixture_eu') 'EA keeps regional content IDs in order and removes duplicate aliases'
    $reorderedPath=Write-Ea (Join-Path $root 'Reordered EA') '<DiPManifest><contentIDs><contentID>fixture_eu</contentID><contentID>123456</contentID></contentIDs></DiPManifest>'
    $reordered=Get-EaManifestGame $reorderedPath
    Assert ($reordered.Id -eq $ea.Id -and $reordered.Target -eq 'origin2://game/launch/?offerIds=fixture_eu,123456') 'Reordering EA aliases preserves game identity without changing launcher argument order'
    Assert ((Start-DetectedGame $ea -DryRun).FileName -eq $ea.Target) 'EA launch goes through the registered EA handler'
    $badPath=Write-Ea (Join-Path $root 'Bad EA') '<DiPManifest><contentIDs><contentID>bad&amp;command=other</contentID></contentIDs></DiPManifest>'
    Assert (Throws {Get-EaManifestGame $badPath}) 'EA content IDs cannot inject additional URI parameters'
    $badPath=Write-Ea (Join-Path $root 'Bad EA') '<!DOCTYPE x [<!ENTITY xxe SYSTEM "file:///C:/secret">]><DiPManifest>&xxe;</DiPManifest>'
    Assert (Throws {Get-EaManifestGame $badPath}) 'EA XML forbids external entities'
    $badPath=Write-Ea (Join-Path $root 'Bad EA') '<DiPManifest><contentIDs /></DiPManifest>'
    Assert (Throws {Get-EaManifestGame $badPath}) 'EA products without content IDs cannot be guessed from EXEs'
    $snapshots=@{GOG=(Snapshot @((Record '12345' $gogFolder)));Ubisoft=(Snapshot @((Record '5678' $ubiFolder),(Record '5678' $ubiFolder)));EA=(Snapshot @((Record '123456' $eaFolder)))}
    $scan=Get-AdditionalLauncherScan -RegistrySnapshots $snapshots -LibraryRoots @($gogRoot,$eaRoot) -GalaxyExecutable ''
    Assert ($scan.Games.Count -eq 3) 'Registry views and folder discovery merge into one game per source identity'
    $eaScanned=@($scan.Games|Where-Object Platform -eq 'EA')[0]
    Assert ($eaScanned.RemovalRegistryIds -contains '123456') 'EA removal evidence records only content IDs corroborated by registration'
    $other=Join-Path $root 'Other Ubisoft';[void][IO.Directory]::CreateDirectory($other)
    $snapshots.Ubisoft=Snapshot @((Record '5678' $ubiFolder),(Record '5678' $other))
    $scan=Get-AdditionalLauncherScan -RegistrySnapshots $snapshots -LibraryRoots @() -GalaxyExecutable ''
    Assert (@($scan.Games|Where-Object Platform -eq 'Ubisoft')[0].Status -eq 'Unresolved') 'Conflicting installation paths never silently choose a ready launch'
    $nativeRoot=Join-Path $root 'SteamLibrary\steamapps';$nativeFolder=Join-Path $nativeRoot 'common\Native EA'
    [void](Write-Ea $nativeFolder '<DiPManifest><contentIDs><contentID>777</contentID></contentIDs></DiPManifest>')
    '"AppState" { "appid" "42" "installdir" "Native EA" }'|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $nativeRoot 'appmanifest_42.acf')
    $snapshots.EA=Snapshot @((Record '777' $nativeFolder))
    $scan=Get-AdditionalLauncherScan -RegistrySnapshots $snapshots -LibraryRoots @() -GalaxyExecutable ''
    Assert (@($scan.Games|Where-Object Id -eq 'ea:777').Count -eq 0) 'Native Steam installations are not added again as non-Steam games'
    Assert (@($scan.Diagnostics|Where-Object {$_ -like '*native Steam*'}).Count -eq 1) 'Native Steam exclusions have an explanation in scan details'
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');AccountId='fixture';SteamRoot=$root}
    $gog=Get-GogManifestGame $gogPath
    $plan=New-SteamSyncPlan $profile @($gog,$ubi,$ea)
    Assert ($plan.AddCount -eq 3) 'All three new launch methods participate in normal Steam sync planning'
    $file=[SteamNite.SteamShortcuts]::new($plan.OutputBytes)
    $gogShortcut=@($file.Items|Where-Object ManagedId -eq $gog.Id.Insert(0,'steamnite:'))[0]
    Assert ($gogShortcut.Exe -eq ('"'+$exe+'"') -and $gogShortcut.StartDir -eq ('"'+$gogFolder+'"')) 'Steam GOG shortcuts use the actual manifest executable and working directory'
    $ubiShortcut=@($file.Items|Where-Object ManagedId -eq 'steamnite:ubisoft:5678')[0]
    Assert ($ubiShortcut.Exe -like '*explorer.exe*' -and $ubiShortcut.LaunchOptions -eq ('"'+$ubi.Target+'"')) 'Steam Ubisoft shortcuts preserve the product-ID protocol handoff'
    $galaxyPlan=New-SteamSyncPlan $profile @($galaxy)
    Assert ($galaxyPlan.Rows[0].Draft.Exe -eq ('"'+$client+'"') -and $galaxyPlan.Rows[0].Draft.LaunchOptions.Contains('/command=runGame')) 'Steam Galaxy shortcuts retain the launcher command arguments'
    $inventory=[pscustomobject]@{GOGComplete=$true;GOGIds=@();UbisoftComplete=$true;UbisoftIds=@();EAComplete=$true;EAIds=@()}
    $missing=Join-Path $root 'Uninstalled'
    foreach($source in @('gog','ubisoft','ea')){
        $shortcut=[pscustomobject]@{AppId=123;Title='Removed fixture';ManagedId=('steamnite:'+ $source+':123')}
        $history=@([pscustomobject]@{Id=($source+':123');InstallPath=$missing;RemovalRegistryIds=@('123')})
        Assert ((Get-ShortcutUninstallState $shortcut $history $inventory).Status -eq 'Removal candidate') ($source+' removal requires a missing path and complete source evidence')
    }
    $shortcut=[pscustomobject]@{AppId=123;Title='EA offline evidence';ManagedId='steamnite:ea:123'}
    $history=@([pscustomobject]@{Id='ea:123';InstallPath=$missing})
    Assert ((Get-ShortcutUninstallState $shortcut $history $inventory).Status -eq 'Cannot verify') 'EA manifest-only installs cannot be removed on uncorroborated registry absence'
    $inventory.UbisoftComplete=$false
    $shortcut.ManagedId='steamnite:ubisoft:123';$history=@([pscustomobject]@{Id='ubisoft:123';InstallPath=$missing})
    Assert ((Get-ShortcutUninstallState $shortcut $history $inventory).Status -eq 'Cannot verify') 'Unreadable or missing new-source records preserve Steam shortcuts'
    $removed=[SteamNite.SteamShortcuts]::new($file.RemoveManaged([uint32[]]@($gogShortcut.AppId,$ubiShortcut.AppId)))
    Assert ($removed.Items.Count -eq 1 -and $removed.Items[0].ManagedId -eq 'steamnite:ea:123456') 'Managed removal supports new source markers and preserves unselected entries'
    [IO.File]::WriteAllBytes($profile.ShortcutPath,$plan.OutputBytes)
    $library=@(Get-UnifiedGameLibrary @($gog,$ubi,$ea) $profile)
    Assert ($library.Count -eq 3 -and @($library|Where-Object SteamSyncStatus -eq 'Synced').Count -eq 3) 'New sources use unified sync and artwork status without duplicate rows'
    "`nAll $script:passed launcher checks passed. No real games launched or Steam files changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
