# Local, read-only launcher adapters. Dot-sourced by SteamNite.Core.psm1.
function Get-LauncherUninstallIdentity($Platform,[string]$Key,[string]$Publisher,[string]$DisplayName) {
    switch($Platform){
        'GOG'{if($Publisher -eq 'GOG.com' -and $Key -match '^(\d+)_is1$'){return $matches[1]};return $null}
        'Ubisoft'{if($Key -match '^Uplay Install (\d+)$'){return $matches[1]};return $null}
        'EA'{if($Publisher -match '^(Electronic Arts|EA Games|EA Swiss)' -and $DisplayName -notmatch '^(EA app|EA Desktop|Origin)(\s|$)'){return $Key};return $null}
    }
    return $null
}
function Get-LauncherRegistrySnapshot {
    param([ValidateSet('GOG','Ubisoft','EA')]$Platform)
    $paths=switch($Platform){
        'GOG'{@('SOFTWARE\GOG.com\Games')}
        'Ubisoft'{@('SOFTWARE\Ubisoft\Launcher\Installs')}
        'EA'{@('SOFTWARE\Origin Games','SOFTWARE\EA Games','SOFTWARE\Electronic Arts\EA Games')}
    }
    $uninstall='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $paths=@($paths)+@($uninstall)
    $records=New-Object 'System.Collections.Generic.List[object]';$found=$false;$failed=$false;$roots=@()
    foreach($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)){
        foreach($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)){
            $base=$null
            try{
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                foreach($path in $paths){
                    $key=$null
                    try{
                        $key=$base.OpenSubKey($path,$false);if(-not $key){continue}
                        if($path -ne $uninstall){$found=$true;$roots+=$path}
                        foreach($name in $key.GetSubKeyNames()){
                            $child=$null
                            try{
                                $child=$key.OpenSubKey($name,$false);if(-not $child){throw 'Registry record disappeared.'}
                                $identity=$name
                                if($path -eq $uninstall){
                                    $publisher=[string]$child.GetValue('Publisher','');$display=[string]$child.GetValue('DisplayName','')
                                    $identity=Get-LauncherUninstallIdentity $Platform $name $publisher $display
                                    if(-not $identity){continue}
                                    $found=$true
                                }
                                $values=@{}
                                # Deliberately read only installation metadata, never keys or account data.
                                foreach($field in @('path','gameName','InstallDir','Install Dir','InstallLocation','InstallPath','DisplayName','Display Icon','DisplayIcon','ContentId','ProductName')){$values[$field]=[string]$child.GetValue($field,'')}
                                $records.Add([pscustomobject]@{Key=$identity;Values=$values;Evidence=('{0}/{1}/{2}/{3}' -f $hive,$view,$path,$name)})
                            }finally{if($child){$child.Dispose()}}
                        }
                    }catch{$failed=$true}finally{if($key){$key.Dispose()}}
                }
            }catch{$failed=$true}finally{if($base){$base.Dispose()}}
        }
    }
    [pscustomobject]@{Records=$records.ToArray();Complete=($found -and -not $failed);Failed=$failed;Roots=@($roots|Select-Object -Unique)}
}
function Test-NativeSteamInstall([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if($full -notmatch '^(.*\\steamapps)\\common\\([^\\]+)(?:\\.*)?$'){return $false}
    $steamapps=$matches[1];$folder=$matches[2]
    foreach($manifest in @(Get-ChildItem -LiteralPath $steamapps -Filter 'appmanifest_*.acf' -File -ErrorAction Stop)){
        $text=Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8
        if($text -match '"installdir"\s+"([^"\r\n]+)"' -and $matches[1] -eq $folder){return $true}
    }
    return $false
}
function Get-LauncherRecordPath($Record) {
    foreach($field in @('path','InstallDir','Install Dir','InstallLocation','InstallPath')){
        $value=[string]$Record.Values[$field]
        if($value){$value=$value.Replace('/','\').Trim('"');if(-not [IO.Path]::IsPathRooted($value)){throw 'Installation path must be absolute.'};return [IO.Path]::GetFullPath($value)}
    }
    return ''
}
function Get-ContainedGamePath([string]$Root,[string]$Relative) {
    if(-not $Relative){return [IO.Path]::GetFullPath($Root)}
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $candidate=if([IO.Path]::IsPathRooted($Relative)){[IO.Path]::GetFullPath($Relative)}else{[IO.Path]::GetFullPath((Join-Path $rootPath $Relative))}
    if($candidate -ne $rootPath -and -not $candidate.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Launch task points outside the game installation.'}
    return $candidate
}
function Get-GogManifestGame {
    param([string]$Path,[string]$GalaxyExecutable='')
    $m=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$m.gameId -notmatch '^\d+$'){throw 'Invalid GOG game identity.'}
    if($m.rootGameId -and [string]$m.rootGameId -ne [string]$m.gameId){return} # DLC
    $tasks=@($m.playTasks|Where-Object {$_.isPrimary -eq $true -and $_.type -eq 'FileTask'})
    if(-not $tasks.Count){return} # extras / content-only products
    $root=Split-Path ([IO.Path]::GetFullPath($Path));$title=if($m.name){$m.name}else{Split-Path $root -Leaf}
    if($GalaxyExecutable -and (Test-Path -LiteralPath $GalaxyExecutable -PathType Leaf)){
        $game=New-GameRecord ('gog:'+$m.gameId) $title 'GOG' $root 'GOG Galaxy' $GalaxyExecutable ('/launchViaAutostart /gameId='+$m.gameId+' /command=runGame /path="'+$root+'"') $Path 'Galaxy chooses the game launch task and retains client features. A saved executable override takes precedence.'
        $game|Add-Member NoteProperty LaunchWorkingDirectory (Split-Path $GalaxyExecutable)
        return $game
    }
    $choices=@($tasks|Group-Object path,arguments,workingDir|ForEach-Object {$_.Group[0]})
    if($choices.Count -ne 1){return New-GameRecord ('gog:'+$m.gameId) $title 'GOG' $root '' '' '' $Path 'Multiple primary launch tasks. Install Galaxy or select an executable with Edit launch.'}
    $task=$choices[0]
    $target=Get-ContainedGamePath $root ([string]$task.path)
    $working=Get-ContainedGamePath $root ([string]$task.workingDir)
    $game=New-GameRecord ('gog:'+$m.gameId) $title 'GOG' $root 'GOG executable' $target ([string]$task.arguments) $Path 'Uses the primary GOG manifest task. Galaxy cloud sync and overlay are not started by direct launch.'
    $game|Add-Member NoteProperty LaunchWorkingDirectory $working
    if([IO.Path]::GetExtension($target) -ne '.exe' -or -not (Test-Path -LiteralPath $target -PathType Leaf) -or -not (Test-Path -LiteralPath $working -PathType Container)){$game.Status='Unresolved';$game.Note='The primary GOG launch task is unavailable. Use Edit launch or repair the installation.'}
    return $game
}
function Get-UbisoftRegistryGame($Record) {
    if($Record.Key -notmatch '^\d+$'){return}
    $root=Get-LauncherRecordPath $Record
    if(-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)){return}
    $title=if($Record.Values['DisplayName']){$Record.Values['DisplayName']}else{Split-Path $root.TrimEnd('\') -Leaf}
    New-GameRecord ('ubisoft:'+$Record.Key) $title 'Ubisoft' $root 'Ubisoft launcher' ('uplay://launch/'+$Record.Key+'/0') '' $Record.Evidence 'Ubisoft Connect resolves edition, renderer, anti-cheat and launch options using the installed product ID; no game EXE is guessed.'
}
function Get-EaManifestGame([string]$Path) {
    $doc=Read-GameXml $Path
    $ids=@($doc.SelectNodes('//*[local-name()="contentIDs"]/*[local-name()="contentID"]')|ForEach-Object {$_.InnerText.Trim()}|Where-Object {$_}|Select-Object -Unique)
    if(-not $ids.Count){throw 'EA installer manifest has no content IDs.'}
    foreach($id in $ids){if($id -notmatch '^[a-zA-Z0-9_.:-]+$'){throw 'Invalid EA content identity.'}}
    $root=Split-Path (Split-Path ([IO.Path]::GetFullPath($Path)))
    $titleNode=$doc.SelectSingleNode('//*[local-name()="gameTitle"]')
    $title=if($titleNode -and $titleNode.InnerText.Trim()){$titleNode.InnerText.Trim()}else{Split-Path $root -Leaf}
    # One product can have regional/edition aliases. Preserve launch order, but
    # select the canonical identity independently of manifest ordering.
    $uri='origin2://game/launch/?offerIds='+(@($ids|ForEach-Object {[uri]::EscapeDataString($_)}) -join ',')
    [string[]]$canonical=$ids;[Array]::Sort($canonical,[StringComparer]::OrdinalIgnoreCase)
    $game=New-GameRecord ('ea:'+$canonical[0]) $title 'EA' $root 'EA launcher' $uri '' $Path 'Uses installer content IDs, not store offer IDs or a guessed game executable. EA handles entitlement, edition and launch setup.'
    $game|Add-Member NoteProperty ContentIds $ids
    return $game
}
function Get-GalaxyExecutable {
    foreach($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)){
        $base=$null;$key=$null
        try{
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
            $key=$base.OpenSubKey('SOFTWARE\GOG.com\GalaxyClient\paths',$false)
            if($key){$path=[string]$key.GetValue('client','');if($path){$exe=Join-Path $path 'GalaxyClient.exe';if(Test-Path -LiteralPath $exe -PathType Leaf){return $exe}}}
        }finally{if($key){$key.Dispose()};if($base){$base.Dispose()}}
    }
    return ''
}
function Get-AdditionalLauncherScan {
    param([string[]]$ExtraRoots=@(),$RegistrySnapshots=$null,[string[]]$LibraryRoots=@(),[string]$GalaxyExecutable='')
    $games=New-Object 'System.Collections.Generic.List[object]';$notices=New-Object 'System.Collections.Generic.List[string]'
    $snapshots=@{};$folders=@{};$gogFolders=@{};$eaFolders=@{}
    foreach($platform in @('GOG','Ubisoft','EA')){
        $snapshot=if($RegistrySnapshots){$RegistrySnapshots[$platform]}else{Get-LauncherRegistrySnapshot $platform};$snapshots[$platform]=$snapshot
        if($snapshot.Failed){$notices.Add($platform+': some installation registry records could not be read. Uninstall removal remains protected.')}
        foreach($record in $snapshot.Records){
            try{
                $path=Get-LauncherRecordPath $record
                if($platform -eq 'Ubisoft'){$game=Get-UbisoftRegistryGame $record;if($game){$games.Add($game)}}
                elseif($path -and (Test-Path -LiteralPath $path -PathType Container)){
                    if($platform -eq 'GOG'){$gogFolders[$path]=$record}else{$eaFolders[$path]=$record}
                }
            }catch{$notices.Add($platform+': '+$record.Key+': '+$_.Exception.Message)}
        }
    }
    $roots=New-Object 'System.Collections.Generic.List[string]'
    if($PSBoundParameters.ContainsKey('LibraryRoots')){foreach($root in $LibraryRoots){$roots.Add($root)}}else{foreach($root in @(Get-AutomaticLauncherFolders)){$roots.Add($root)}}
    foreach($root in $ExtraRoots){if($root){$roots.Add($root)}}
    foreach($root in @($roots|Select-Object -Unique)){
        if(-not (Test-Path -LiteralPath $root -PathType Container)){continue}
        try{
            foreach($folder in @((Get-Item -LiteralPath $root))+@(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop)){$folders[$folder.FullName]=$true}
        }catch{$notices.Add('Launcher folder: '+$root+': '+$_.Exception.Message)}
    }
    foreach($path in @($folders.Keys)){
        if(@(Get-ChildItem -LiteralPath $path -Filter 'goggame-*.info' -File -ErrorAction SilentlyContinue).Count){if(-not $gogFolders.ContainsKey($path)){$gogFolders[$path]=$null}}
        if(Test-Path -LiteralPath (Join-Path $path '__Installer\installerdata.xml') -PathType Leaf){if(-not $eaFolders.ContainsKey($path)){$eaFolders[$path]=$null}}
    }
    $galaxy=$GalaxyExecutable
    if(-not $PSBoundParameters.ContainsKey('GalaxyExecutable')){try{$galaxy=Get-GalaxyExecutable}catch{$notices.Add('GOG: Galaxy installation could not be checked; using manifest launch tasks.')}}
    foreach($path in @($gogFolders.Keys)){
        $manifests=@(Get-ChildItem -LiteralPath $path -Filter 'goggame-*.info' -File -ErrorAction SilentlyContinue)
        if(-not $manifests.Count){$notices.Add('GOG: no launch manifest in '+$path);continue}
        foreach($manifest in $manifests){try{$game=Get-GogManifestGame $manifest.FullName $galaxy;if($game){$games.Add($game)}}catch{$notices.Add('GOG: '+$manifest.FullName+': '+$_.Exception.Message)}}
    }
    foreach($path in @($eaFolders.Keys)){
        $manifest=Join-Path $path '__Installer\installerdata.xml'
        if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)){$notices.Add('EA: no installer manifest in '+$path+'; no executable was guessed.');continue}
        try{
            $game=Get-EaManifestGame $manifest
            if($game){
                $registryIds=@($snapshots.EA.Records|Where-Object {$_.Evidence -like '*SOFTWARE\Origin Games/*' -and $_.Key -in $game.ContentIds}|ForEach-Object {$_.Key}|Select-Object -Unique)
                $game|Add-Member NoteProperty RemovalRegistryIds $registryIds
                $games.Add($game)
            }
        }catch{$notices.Add('EA: '+$manifest+': '+$_.Exception.Message)}
    }
    $eligible=@(foreach($game in $games){
        try{if(Test-NativeSteamInstall $game.InstallPath){$notices.Add($game.Platform+': '+$game.Title+' is already a native Steam installation; skipped.');continue}}
        catch{$game.Status='Unresolved';$game.Target='';$game.Note='Could not verify whether this installation is already native to Steam. '+$_.Exception.Message}
        $game
    })
    # Merge registry views and identical records after excluding native Steam
    # installations; a second, standalone installation remains discoverable.
    $merged=@(foreach($group in @($eligible|Group-Object Id)){
        $unique=@($group.Group|Sort-Object InstallPath -Unique)
        $game=$unique[0]
        if($unique.Count -gt 1){$game.Target='';$game.Method='';$game.Status='Unresolved';$game.Note='Multiple installation paths share this product ID. Review the installation or set a launch override.'}
        $game
    })
    [pscustomobject]@{Games=$merged;Diagnostics=$notices.ToArray();Snapshots=$snapshots}
}

function Get-AutomaticLauncherFolders {
    foreach($drive in [IO.DriveInfo]::GetDrives()){
        if($drive.IsReady -and $drive.DriveType -eq 'Fixed'){
            foreach($name in @('GOG Games','GOG Galaxy','GOG Galaxy\Games','EA Games','Origin Games','Program Files\EA Games','Program Files\GOG Galaxy\Games','Program Files (x86)\GOG Galaxy\Games','Program Files (x86)\Origin Games')){Join-Path $drive.RootDirectory.FullName $name}
        }
    }
}
function Get-AutomaticScanFolders {
    foreach($drive in [IO.DriveInfo]::GetDrives()){if($drive.IsReady -and $drive.DriveType -eq 'Fixed'){Join-Path $drive.RootDirectory.FullName 'XboxGames'}}
    Get-AutomaticLauncherFolders
}
