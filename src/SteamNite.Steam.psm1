$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Storage.psm1')
Import-Module (Join-Path $PSScriptRoot 'SteamNite.Core.psm1')
if (-not ('SteamNite.SteamShortcuts' -as [type])) {
    if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -Path (Join-Path $PSScriptRoot 'SteamShortcuts.cs') }
    else { Add-Type -Path (Join-Path $PSScriptRoot 'SteamShortcuts.cs') -ReferencedAssemblies 'System.Core.dll' }
}

function Get-GamePreferencesPath { Join-Path (Get-OathgateDataDirectory) 'game-preferences.json' }
function Get-IgnoredGameIds([string]$Path=(Get-GamePreferencesPath)) {
    if(Test-Path -LiteralPath $Path){
        $saved=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($saved.IgnoredGameIds | Where-Object {$_})
    }
    return @()
}
function Set-GameIgnored {
    param([string[]]$GameIds,[bool]$Ignored,[string]$Path=(Get-GamePreferencesPath))
    $ids=@(Get-IgnoredGameIds $Path)
    if($Ignored){$ids=@(@($ids)+@($GameIds)|Where-Object {$_}|Sort-Object -Unique)}
    else{$ids=@($ids|Where-Object {$_ -notin $GameIds})}
    [void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($Path))))
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        @{IgnoredGameIds=$ids}|ConvertTo-Json -Depth 3|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Test-SteamLaunchMatches($Existing,$Draft) {
    return $Existing.Exe.Trim('"') -eq $Draft.Exe.Trim('"') -and $Existing.StartDir.Trim('"') -eq $Draft.StartDir.Trim('"') -and $Existing.LaunchOptions -ceq $Draft.LaunchOptions
}
function Test-SteamRunning { return @((Get-Process -Name steam -ErrorAction SilentlyContinue)).Count -gt 0 }
function Get-SteamClientCommand {
    param($Profile,[switch]$Shutdown)
    $path=Join-Path $Profile.SteamRoot 'steam.exe'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Steam executable was not found for this account.'}
    $info=New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName=[IO.Path]::GetFullPath($path);$info.UseShellExecute=$true
    if($Shutdown){$info.Arguments='-shutdown';$info.WindowStyle='Hidden'}
    return $info
}
function Request-SteamShutdown($Profile) {
    [void][Diagnostics.Process]::Start((Get-SteamClientCommand $Profile -Shutdown))
}
function Open-SteamClient($Profile) {
    [void][Diagnostics.Process]::Start((Get-SteamClientCommand $Profile))
}
function Get-SteamPlanChangeSignature($Plan) {
    @($Plan.Rows | ForEach-Object {
        [pscustomobject]@{GameId=$_.GameId;Title=$_.Title;Action=$_.Action;Reason=$_.Reason;Exe=$_.Draft.Exe;StartDir=$_.Draft.StartDir;Options=$_.Draft.LaunchOptions;AppId=$_.Draft.AppId;Existing=$_.Existing}
    }) | ConvertTo-Json -Depth 4 -Compress
}

function Get-SteamProfiles {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $v = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($path in @($v.SteamPath, $v.InstallPath)) { if ($path) { $roots.Add($path.Replace('/', '\')) } }
        } catch { }
    }
    $roots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
    $seenRoots = @{}
    foreach ($candidate in $roots) {
        $root = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\')
        if ($seenRoots.ContainsKey($root)) { continue }; $seenRoots[$root] = $true
        $userdata = Join-Path $root 'userdata'
        if (-not (Test-Path -LiteralPath $userdata)) { continue }
        foreach ($folder in @(Get-ChildItem -LiteralPath $userdata -Directory)) {
            if ($folder.Name -notmatch '^\d+$' -or $folder.Name -eq '0') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $folder.FullName 'config'))) { continue }
            [pscustomobject]@{
                Label = 'Steam account ' + $folder.Name + ' | ' + $root
                AccountId = $folder.Name; SteamRoot = $root
                ShortcutPath = Join-Path $folder.FullName 'config\shortcuts.vdf'
            }
        }
    }
}

function Get-ShortcutSnapshot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Hash = 'MISSING'; File = [SteamNite.SteamShortcuts]::new([byte[]]$null) }
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') } finally { $sha.Dispose() }
    [pscustomobject]@{ Hash = $hash; File = (New-Object SteamNite.SteamShortcuts -ArgumentList (,$bytes)) }
}
function Find-SteamGameShortcuts {
    param([object[]]$Items,[string]$GameId,$Draft)
    $matches=@($Items | Where-Object {$_.ManagedId -eq ('steamnite:'+$GameId)})
    if (-not $matches.Count -and $Draft) {
        $matches=@($Items | Where-Object {$_.Exe.Trim('"') -eq $Draft.Exe.Trim('"') -and $_.LaunchOptions -eq $Draft.LaunchOptions})
    }
    return $matches
}
function Get-GameSteamStatuses {
    param([object[]]$Games,$Profile=$null)
    if (-not $Profile) {
        foreach($game in $Games){[pscustomobject]@{GameId=$game.Id;Status='No profile';Detail='Choose a Steam account to check sync status.';AppId=$null}}
        return
    }
    try {
        $snapshot=Get-ShortcutSnapshot $Profile.ShortcutPath
        $plan=New-SteamSyncPlan -Profile $Profile -Games $Games
        foreach($game in $Games){
            $row=@($plan.Rows | Where-Object {$_.GameId -eq $game.Id})[0]
            $matches=@(Find-SteamGameShortcuts -Items $snapshot.File.Items.ToArray() -GameId $game.Id -Draft $row.Draft)
            $status='Not synced';$detail='No matching shortcut in this Steam account. Use Sync to Steam.';$appId=$null
            if($matches.Count -eq 1 -and $row.Draft -and $row.Action -ne 'Blocked') {
                $status=if($row.Action -eq 'Repair'){'Needs repair'}elseif($row.Action -eq 'Ignored'){'Ignored'}else{'Synced'}
                $detail=if($row.Action -in @('Repair','Ignored')){$row.Reason}else{'Matching Steam shortcut: '+$matches[0].Title};$appId=$matches[0].AppId
            } elseif($matches.Count -gt 1) {
                $status='Needs attention';$detail='Multiple matching Steam shortcuts. Resolve duplicates before applying artwork.'
            } elseif($row.Action -eq 'Ignored') {$status='Ignored';$detail=$row.Reason
            } elseif($row.Action -eq 'Blocked') {
                $status='Needs attention';$detail=$row.Reason
            } elseif($row.Action -eq 'Keep existing') {
                $status='Needs attention';$detail='A shortcut has the same title but a different launch target. It has been preserved; artwork is not linked.'
            }
            [pscustomobject]@{GameId=$game.Id;Status=$status;Detail=$detail;AppId=$appId}
        }
    } catch {
        foreach($game in $Games){[pscustomobject]@{GameId=$game.Id;Status='Unknown';Detail=('Could not read Steam shortcuts: '+$_.Exception.Message);AppId=$null}}
    }
}

function New-SteamSyncPlan {
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][object[]]$Games,[string]$PreferencesPath=(Get-GamePreferencesPath))
    $snapshot = Get-ShortcutSnapshot $Profile.ShortcutPath
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $drafts = New-Object 'System.Collections.Generic.List[SteamNite.ShortcutDraft]'
    $seen = @{};$ignored=@(Get-IgnoredGameIds $PreferencesPath);$repairs=New-Object 'System.Collections.Generic.List[object]'
    foreach ($game in $Games) {
        if ($seen.ContainsKey($game.Id)) { continue }; $seen[$game.Id] = $true
        $action = 'Add'; $reason = ''; $draft = $null;$existingMatch=$null
        try {
            $launch = Start-DetectedGame $game -DryRun
            $draft = New-Object SteamNite.ShortcutDraft
            $draft.Title = $game.Title; $draft.ManagedId = 'steamnite:' + $game.Id
            $effective=Get-EffectiveGameLaunch $game
            if ($effective.Method -in @('Xbox launch helper','Custom executable','GOG Galaxy','GOG executable')) {
                $draft.Exe = '"' + $launch.FileName + '"'; $draft.StartDir = '"' + $launch.WorkingDirectory + '"'; $draft.LaunchOptions = $launch.Arguments
            } elseif ($effective.Method -eq 'Windows activation') {
                $draft.Exe = '"' + (Join-Path $env:WINDIR 'explorer.exe') + '"'
                $draft.StartDir = '"' + $env:WINDIR + '"'; $draft.LaunchOptions = $launch.Arguments
            } else {
                $draft.Exe = '"' + (Join-Path $env:WINDIR 'explorer.exe') + '"'
                $draft.StartDir = '"' + $env:WINDIR + '"'; $draft.LaunchOptions = '"' + $launch.FileName + '"'
            }
            $draft.AppId = [SteamNite.SteamShortcuts]::AppId($draft.Exe, $draft.Title)
            $managed=@($snapshot.File.Items|Where-Object {$_.ManagedId -eq $draft.ManagedId})
            $targets=@(Find-SteamGameShortcuts $snapshot.File.Items.ToArray() $game.Id $draft)
            if($managed.Count -gt 1 -or $targets.Count -gt 1){throw 'Multiple matching shortcuts. Resolve duplicates before syncing.'}
            if($managed.Count -eq 1){
                $existingMatch=$managed[0]
                if(@($snapshot.File.Items|Where-Object {$_.AppId -eq $existingMatch.AppId}).Count -ne 1){throw 'Duplicate Steam shortcut IDs. Repair is unsafe.'}
                if(Test-SteamLaunchMatches $existingMatch $draft){$action='Keep existing';$reason='Managed launch fields are current.'}
                else{$action='Repair';$reason='Launch target, working directory or launch options changed. Repair preserves the Steam ID, title, artwork and other settings.'}
            }elseif($targets.Count -eq 1){$action='Keep existing';$reason='A matching manual shortcut is preserved.'}
            elseif(@($snapshot.File.Items|Where-Object {$_.Title -eq $draft.Title}).Count){$action='Keep existing';$reason='A same-title shortcut has a different launch target and is preserved.'}
            elseif(@($snapshot.File.Items|Where-Object {$_.AppId -eq $draft.AppId}).Count){throw 'Steam shortcut ID collides with an existing entry.'}
            if($game.Id -in $ignored){$action='Ignored';$reason='Excluded from SteamNite changes. Existing Steam entries and artwork are preserved.'}
            if($action -eq 'Repair'){$repairs.Add([pscustomobject]@{AppId=$existingMatch.AppId;ManagedId=$draft.ManagedId;Draft=$draft})}
            if ($action -eq 'Add') { $drafts.Add($draft) }
        } catch { $action = 'Blocked'; $reason = $_.Exception.Message;if($game.Id -in $ignored){$action='Ignored';$reason='Excluded from SteamNite changes.'} }
        $rows.Add([pscustomobject]@{ Title=$game.Title; GameId=$game.Id; Action=$action; Reason=$reason; Draft=$draft;Existing=$existingMatch })
    }
    $output = $snapshot.File.Append($drafts.ToArray())
    foreach($repair in $repairs){$file=New-Object SteamNite.SteamShortcuts -ArgumentList (,$output);$output=$file.RepairLaunch($repair.AppId,$repair.ManagedId,$repair.Draft)}
    [pscustomobject]@{
        Profile=$Profile; OriginalHash=$snapshot.Hash; ExistingCount=$snapshot.File.Items.Count
        Rows=$rows.ToArray(); Games=$Games; AddCount=$drafts.Count;RepairCount=$repairs.Count;PreferencesPath=$PreferencesPath; OutputBytes=$output
    }
}

function Save-SteamSyncPlan {
    param([Parameter(Mandatory)]$Plan)
    if (Test-SteamRunning) { throw 'Exit Steam completely using Steam > Exit, then apply this preview again. No files were changed.' }
    $path = [System.IO.Path]::GetFullPath($Plan.Profile.ShortcutPath)
    if ([System.IO.Path]::GetFileName($path) -ne 'shortcuts.vdf') { throw 'Invalid Steam shortcut destination.' }
    $snapshot = Get-ShortcutSnapshot $path
    if ($snapshot.Hash -ne $Plan.OriginalHash) { throw 'Steam shortcuts changed since the preview. Create a new preview before syncing.' }
    $repairCount=if($Plan.PSObject.Properties['RepairCount']){[int]$Plan.RepairCount}else{0}
    $ignored=@(Get-IgnoredGameIds $(if($Plan.PreferencesPath){$Plan.PreferencesPath}else{Get-GamePreferencesPath}))
    if(@($Plan.Rows|Where-Object {$_.Action -in @('Add','Repair') -and $_.GameId -in $ignored}).Count){throw 'Exclusions changed since this preview. Refresh before applying.'}
    if($Plan.Games){
        $fresh=New-SteamSyncPlan -Profile $Plan.Profile -Games $Plan.Games -PreferencesPath $Plan.PreferencesPath
        if((Get-SteamPlanChangeSignature $fresh) -ne (Get-SteamPlanChangeSignature $Plan)){throw 'Launch settings or game files changed since this preview. Refresh before applying.'}
    }
    if ($Plan.AddCount -eq 0 -and $repairCount -eq 0) { return [pscustomobject]@{ Added=0;Repaired=0; BackupPath=''; ShortcutPath=$path } }
    $validated = New-Object SteamNite.SteamShortcuts -ArgumentList (,$Plan.OutputBytes)
    if ($validated.Items.Count -ne $snapshot.File.Items.Count + $Plan.AddCount) { throw 'Preview validation failed.' }
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $temporary = $path + '.steamnite-' + $suffix + '.tmp'
    $backup = $path + '.steamnite-' + $suffix + '.bak'
    try {
        [System.IO.File]::WriteAllBytes($temporary, $Plan.OutputBytes)
        if (Test-SteamRunning) { throw 'Steam started while preparing the sync. No changes were applied.' }
        if ((Get-ShortcutSnapshot $path).Hash -ne $Plan.OriginalHash) { throw 'Steam shortcuts changed. Create a new preview.' }
        if ($Plan.OriginalHash -eq 'MISSING') {
            # Move refuses to overwrite a file that appeared since the last check.
            [System.IO.File]::Move($temporary, $path); $backup = ''
        } else {
            # Same-volume atomic replacement produces an exact backup of the previous file.
            [System.IO.File]::Replace($temporary, $path, $backup)
        }
        [pscustomobject]@{ Added=$Plan.AddCount;Repaired=$repairCount; BackupPath=$backup; ShortcutPath=$path }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

Export-ModuleMember -Function Get-IgnoredGameIds, Set-GameIgnored, Get-GamePreferencesPath, Test-SteamLaunchMatches, Get-SteamProfiles, Test-SteamRunning, New-SteamSyncPlan, Save-SteamSyncPlan, Get-ShortcutSnapshot, Find-SteamGameShortcuts, Get-GameSteamStatuses, Get-SteamClientCommand, Request-SteamShutdown, Open-SteamClient, Get-SteamPlanChangeSignature
