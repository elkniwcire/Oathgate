$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Storage.psm1')

function Read-GameXml([string]$Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try { $doc = New-Object System.Xml.XmlDocument; $doc.XmlResolver = $null; $doc.Load($reader); return ,$doc }
    finally { $reader.Dispose() }
}

function New-GameRecord {
    param($Id, $Title, $Platform, $InstallPath, $Method, $Target, $Arguments = '', $Evidence = '', $Note = '')
    [pscustomobject]@{
        Id = [string]$Id; Title = [string]$Title; Platform = [string]$Platform
        InstallPath = [string]$InstallPath; Method = [string]$Method
        Target = [string]$Target; Arguments = [string]$Arguments
        Status = $(if ($Target) { 'Ready to test' } else { 'Unresolved' })
        Evidence = [string]$Evidence; Note = [string]$Note
    }
}

function Get-XboxFolderGame {
    param([string]$Folder, [object[]]$Packages = @())
    $content = Join-Path $Folder 'Content'
    if (-not (Test-Path -LiteralPath (Join-Path $content 'MicrosoftGame.config'))) { $content = $Folder }
    $configPath = Join-Path $content 'MicrosoftGame.config'
    if (-not (Test-Path -LiteralPath $configPath)) { return }
    $doc = Read-GameXml $configPath
    $identity = $doc.SelectSingleNode('/*[local-name()="Game"]/*[local-name()="Identity"]')
    $visuals = $doc.SelectSingleNode('/*[local-name()="Game"]/*[local-name()="ShellVisuals"]')
    $executables = @($doc.SelectNodes('//*[local-name()="ExecutableList"]/*[local-name()="Executable"]') | Where-Object {
        $_.GetAttribute('IsDevOnly') -ne 'true' -and $_.GetAttribute('TargetDeviceFamily') -ne 'XboxOne' -and $_.GetAttribute('TargetDeviceFamily') -ne 'Scarlett'
    })
    # Content packages and preloads are not launchable games just because a folder exists.
    if ($executables.Count -eq 0) { return }
    $name = $identity.GetAttribute('Name')
    $title = $visuals.GetAttribute('DefaultDisplayName')
    if (-not $title -or $title -like 'ms-resource:*') { $title = Split-Path $Folder -Leaf }
    $exe = $executables[0]
    if ($executables.Count -gt 1) {
        return New-GameRecord "xbox:$name" $title 'Xbox' $content '' '' '' $configPath 'Multiple game entry points; automatic choice needs validation.'
    }
    $helper = Join-Path $content 'gamelaunchhelper.exe'
    $manifestPath = Join-Path $content 'appxmanifest.xml'
    $manifestExe = ''; $applicationId = $exe.GetAttribute('Id')
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Read-GameXml $manifestPath
        $allApps = @($manifest.SelectNodes('//*[local-name()="Applications"]/*[local-name()="Application"]'))
        $app = @($allApps | Where-Object { $_.GetAttribute('Id') -eq $applicationId })
        if (-not $applicationId -and $allApps.Count -eq 1) { $app = $allApps }
        if ($app.Count -eq 1) { $manifestExe = $app[0].GetAttribute('Executable'); $applicationId = $app[0].GetAttribute('Id') }
    }
    if ((Test-Path -LiteralPath $helper -PathType Leaf) -and $manifestExe -match '(^|[\\/])gamelaunchhelper\.exe$') {
        return New-GameRecord "xbox:$name" $title 'Xbox' $content 'Xbox launch helper' $helper '' $manifestPath 'Launch helper selected from the application manifest; game EXE is intentionally bypassed.'
    }
    $package = @($Packages | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
    if ($package -and $applicationId) {
        $aumid = $package.PackageFamilyName + '!' + $applicationId
        return New-GameRecord "xbox:$name" $title 'Xbox' $content 'Windows activation' $aumid '' $configPath 'Launch through the registered Windows application identity.'
    }
    return New-GameRecord "xbox:$name" $title 'Xbox' $content '' '' '' $configPath 'No confirmed helper mapping or registered package. Could be a leftover installation or preload.'
}

function Get-EpicManifestGame([string]$Path) {
    $m = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $m.AppName -or -not $m.InstallLocation) { return }
    if ($m.bIsIncompleteInstall -eq $true) { return }
    if ($m.MainGameAppName -and $m.MainGameAppName -ne $m.AppName) { return }
    if (-not (Test-Path -LiteralPath $m.InstallLocation -PathType Container)) { return }
    if (-not $m.LaunchExecutable) { return }
    $title = $m.DisplayName
    if (-not $title) { $title = $m.AppName }
    # Launcher activation preserves authentication, DRM and launcher-supplied arguments.
    $identifier = [string]$m.AppName
    if ($m.CatalogNamespace -and $m.CatalogItemId) { $identifier = '{0}:{1}:{2}' -f $m.CatalogNamespace, $m.CatalogItemId, $m.AppName }
    $uri = 'com.epicgames.launcher://apps/' + [uri]::EscapeDataString($identifier) + '?action=launch&silent=true'
    New-GameRecord ("epic:" + $m.AppName) $title 'Epic' $m.InstallLocation 'Epic launcher' $uri '' $Path 'Uses Epic for authentication and launch arguments.'
}

function Get-AmazonGames([string]$DatabasePath) {
    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) { return }
    if (-not ('SteamNite.NativeSqlite' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'NativeSqlite.cs') }
    $rows = [SteamNite.NativeSqlite]::Read($DatabasePath, 'SELECT Id, ProductTitle, InstallDirectory FROM DbSet WHERE Installed = 1;')
    foreach ($row in $rows) {
        if (-not $row['Id'] -or -not $row['InstallDirectory']) { continue }
        if (-not (Test-Path -LiteralPath $row['InstallDirectory'] -PathType Container)) { continue }
        New-GameRecord ('amazon:' + $row['Id']) $row['ProductTitle'] 'Amazon' $row['InstallDirectory'] 'Amazon launcher' ('amazon-games://play/' + [uri]::EscapeDataString($row['Id'])) '' $DatabasePath 'Uses Amazon Games to preserve client requirements and game configuration.'
    }
}

function Get-GameScan {
    param([string[]]$ExtraRoots = @())
    $games = New-Object 'System.Collections.Generic.List[object]'
    $diagnostics = New-Object 'System.Collections.Generic.List[string]'
    $packages = @(); $startApps = @()
    try { $packages = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage }) }
    catch { $diagnostics.Add('Windows package scan failed: ' + $_.Exception.Message) }
    try { $startApps = @(Get-StartApps -ErrorAction Stop) } catch { $diagnostics.Add('Windows title lookup unavailable: ' + $_.Exception.Message) }
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.IsReady -and $drive.DriveType -eq 'Fixed') {
            $roots.Add((Join-Path $drive.RootDirectory.FullName 'XboxGames'))
        }
    }
    foreach ($root in $ExtraRoots) { if ($root) { $roots.Add($root) } }
    $seenFolders = @{}
    foreach ($root in @($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        try {
            $folders = @((Get-Item -LiteralPath $root)) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop)
            foreach ($folder in $folders) {
                if ($seenFolders.ContainsKey($folder.FullName)) { continue }; $seenFolders[$folder.FullName] = $true
                try { $g = Get-XboxFolderGame $folder.FullName $packages; if ($g) { $games.Add($g) } }
                catch { $diagnostics.Add('Xbox: ' + $folder.FullName + ': ' + $_.Exception.Message) }
            }
        } catch { $diagnostics.Add('Cannot read ' + $root + ': ' + $_.Exception.Message) }
    }
    # Registered Store/UWP games outside XboxGames. Gaming-specific evidence prevents importing ordinary apps.
    foreach ($package in $packages) {
        if (@($games | Where-Object { $_.Id -eq ('xbox:' + $package.Name) }).Count -gt 0) { continue }
        try {
            $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
            $config = Join-Path $package.InstallLocation 'MicrosoftGame.config'
            $isGame = (Test-Path -LiteralPath $config) -or ($manifest.OuterXml -match 'windows\.xboxLive|ms-xbl-|GameExplorer')
            if (-not $isGame) { continue }
            $apps = @($manifest.SelectNodes('//*[local-name()="Applications"]/*[local-name()="Application"]'))
            foreach ($app in $apps) {
                if (-not $app.GetAttribute('Id')) { continue }
                $aumid = $package.PackageFamilyName + '!' + $app.GetAttribute('Id')
                $start = @($startApps | Where-Object { $_.AppID -eq $aumid }) | Select-Object -First 1
                $title = if ($start) { $start.Name } else { $package.Name }
                $games.Add((New-GameRecord ('xbox:' + $package.Name + ':' + $app.GetAttribute('Id')) $title 'Xbox' $package.InstallLocation 'Windows activation' $aumid '' 'Registered Windows package' 'Package activation; Windows manages the protected installation path.'))
            }
        } catch { $diagnostics.Add('Package ' + $package.Name + ': ' + $_.Exception.Message) }
    }
    $epicRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Epic\EpicGamesLauncher\Data\Manifests'
    try {
        $manifests = @(Get-ChildItem -LiteralPath $epicRoot -Filter '*.item' -ErrorAction Stop)
        if ($manifests.Count -eq 0) { $diagnostics.Add('Epic: no installed-game manifests found.') }
        foreach ($file in $manifests) {
            try { $g = Get-EpicManifestGame $file.FullName; if ($g) { $games.Add($g) } }
            catch { $diagnostics.Add('Epic: ' + $file.Name + ': ' + $_.Exception.Message) }
        }
    } catch { $diagnostics.Add('Epic manifest scan: ' + $_.Exception.Message) }
    $amazonDb = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Amazon Games\Data\Games\Sql\GameInstallInfo.sqlite'
    try {
        if (Test-Path -LiteralPath $amazonDb) { foreach ($g in @(Get-AmazonGames $amazonDb)) { $games.Add($g) } }
        else { $diagnostics.Add('Amazon: installed-game database not found.') }
    } catch { $diagnostics.Add('Amazon database scan failed: ' + $_.Exception.Message) }
    $additional=Get-AdditionalLauncherScan -ExtraRoots $ExtraRoots
    foreach($game in $additional.Games){$games.Add($game)}
    foreach($notice in $additional.Diagnostics){$diagnostics.Add($notice)}
    # Query local protocol registrations, without starting a launcher.
    foreach ($g in $games) {
        if ($g.Method -in @('Epic launcher', 'Amazon launcher','Ubisoft launcher','EA launcher')) {
            $scheme = ([uri]$g.Target).Scheme
            if (-not (Test-Path -LiteralPath ('Registry::HKEY_CLASSES_ROOT\' + $scheme + '\shell\open\command'))) {
                $g.Status = 'Launcher missing'; $g.Note += ' Windows protocol handler is not registered.'
            }
        }
    }
    [pscustomobject]@{
        ScannedAt = (Get-Date).ToString('o'); Roots = @($roots | Select-Object -Unique)
        Games = @($games | Sort-Object Platform, Title, Id -Unique)
        Diagnostics = @($diagnostics)
    }
}

function Get-LaunchOverridesPath { Join-Path (Get-OathgateDataDirectory) 'launch-overrides.json' }
function Get-LaunchOverrides([string]$Path=(Get-LaunchOverridesPath)) {
    if(Test-Path -LiteralPath $Path){return @((Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json).Overrides)}
    return @()
}
function Set-GameLaunchOverride {
    param([string]$GameId,[string]$Executable,[string]$WorkingDirectory,[string]$Arguments='', [switch]$Reset,[string]$Path=(Get-LaunchOverridesPath))
    $overrides=@(Get-LaunchOverrides $Path|Where-Object {$_.GameId -ne $GameId})
    if(-not $Reset){
        if(-not [IO.Path]::IsPathRooted($Executable) -or [IO.Path]::GetExtension($Executable) -ne '.exe' -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)){throw 'Choose an existing executable (.exe).'}
        if(-not $WorkingDirectory){$WorkingDirectory=Split-Path $Executable}
        if(-not [IO.Path]::IsPathRooted($WorkingDirectory) -or -not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)){throw 'Choose an existing working folder.'}
        $overrides+= [pscustomobject]@{GameId=$GameId;Executable=[IO.Path]::GetFullPath($Executable);WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory);Arguments=$Arguments}
    }
    [void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($Path))))
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        @{Overrides=$overrides}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Get-EffectiveGameLaunch {
    param($Game,[string]$Path=(Get-LaunchOverridesPath))
    $original=if($Game.DetectedGame){$Game.DetectedGame}else{$Game}
    $copy=$original.PSObject.Copy()
    $override=@(Get-LaunchOverrides $Path|Where-Object {$_.GameId -eq $original.Id})
    if($override.Count -gt 1){throw 'Multiple launch overrides found for this game.'}
    if($override.Count -eq 1){
        $copy.Method='Custom executable';$copy.Target=$override[0].Executable;$copy.Arguments=$override[0].Arguments
        $copy.Status=if((Test-Path -LiteralPath $copy.Target -PathType Leaf) -and (Test-Path -LiteralPath $override[0].WorkingDirectory -PathType Container)){'Ready to test'}else{'Override missing'}
        $copy|Add-Member -Force NoteProperty LaunchWorkingDirectory $override[0].WorkingDirectory
        $copy|Add-Member -Force NoteProperty DetectedGame $original
        $copy|Add-Member -Force NoteProperty HasLaunchOverride $true
    }
    return $copy
}
function Start-DetectedGame {
    param([Parameter(Mandatory)]$Game, [switch]$DryRun)
    $Game=Get-EffectiveGameLaunch $Game
    if (-not $Game.Target -or $Game.Status -ne 'Ready to test') { throw 'This game does not have a usable launch recipe. See its details.' }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.UseShellExecute = $true
    switch ($Game.Method) {
        {$_ -in @('GOG Galaxy','GOG executable')} {
            if(-not (Test-Path -LiteralPath $Game.Target -PathType Leaf) -or [IO.Path]::GetExtension($Game.Target) -ne '.exe'){throw 'GOG launch executable is missing or invalid. Rescan or edit launch settings.'}
            if(-not (Test-Path -LiteralPath $Game.LaunchWorkingDirectory -PathType Container)){throw 'GOG working directory is missing.'}
            $info.FileName=$Game.Target;$info.Arguments=$Game.Arguments;$info.WorkingDirectory=$Game.LaunchWorkingDirectory
        }
        'Ubisoft launcher' {
            if($Game.Target -notmatch '^uplay://launch/\d+/0$'){throw 'Invalid Ubisoft launch URI.'}
            $info.FileName=$Game.Target
        }
        'EA launcher' {
            if($Game.Target -notmatch '^origin2://game/launch/\?offerIds=[a-zA-Z0-9_.:%,-]+$'){throw 'Invalid EA launch URI.'}
            $info.FileName=$Game.Target
        }
        'Custom executable' {
            if([IO.Path]::GetExtension($Game.Target) -ne '.exe' -or -not [IO.Path]::IsPathRooted($Game.Target)){throw 'Invalid launch override executable.'}
            $info.FileName=$Game.Target;$info.WorkingDirectory=$Game.LaunchWorkingDirectory;$info.Arguments=$Game.Arguments
        }
        'Xbox launch helper' {
            if (-not (Test-Path -LiteralPath $Game.Target -PathType Leaf)) { throw 'Launch helper is missing. Rescan the library.' }
            $info.FileName = $Game.Target; $info.WorkingDirectory = $Game.InstallPath
        }
        'Windows activation' {
            if ($Game.Target -notmatch '^[\w.\-]+_[\w]+![\w.\-]+$') { throw 'Invalid Windows application identity.' }
            $info.FileName = 'explorer.exe'; $info.Arguments = 'shell:AppsFolder\' + $Game.Target
        }
        'Epic launcher' {
            if ($Game.Target -notlike 'com.epicgames.launcher://apps/*') { throw 'Invalid Epic launch URI.' }
            $info.FileName = $Game.Target
        }
        'Amazon launcher' {
            if ($Game.Target -notlike 'amazon-games://play/*') { throw 'Invalid Amazon launch URI.' }
            $info.FileName = $Game.Target
        }
        default { throw ('Unsupported launch method: ' + $Game.Method) }
    }
    if ($DryRun) { return $info }
    [void][System.Diagnostics.Process]::Start($info)
}

. (Join-Path $PSScriptRoot 'Launcher.Adapters.ps1')
Export-ModuleMember -Function Get-AutomaticScanFolders, Get-AdditionalLauncherScan, Get-LauncherRegistrySnapshot, Get-GogManifestGame, Get-UbisoftRegistryGame, Get-EaManifestGame, Get-LaunchOverridesPath, Get-LaunchOverrides, Set-GameLaunchOverride, Get-EffectiveGameLaunch, Get-GameScan, Get-XboxFolderGame, Get-EpicManifestGame, Get-AmazonGames, Start-DetectedGame
