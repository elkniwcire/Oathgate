param([switch]$SmokeTest,[string]$WorkflowRequest='')
$ErrorActionPreference = 'Stop'
$instance=$null;$ownsInstance=$false
if (-not $SmokeTest) {
    $instance=New-Object Threading.Mutex($false,('Local\Oathgate-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    try { $ownsInstance=$instance.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsInstance=$true }
    if (-not $ownsInstance) { $instance.Dispose();throw 'Oathgate is already running. Use the existing window.' }
}
try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'src\Theme.ps1')
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Steam.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Artwork.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Removal.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Library.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Preparation.psm1') -Force
. (Join-Path $PSScriptRoot 'src\Artwork.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\BulkArtwork.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\Steam.Session.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\Removal.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\Launch.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\Preparation.Dialog.ps1')
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Settings.psm1') -Force
. (Join-Path $PSScriptRoot 'src\Settings.Dialog.ps1')
. (Join-Path $PSScriptRoot 'src\Library.Menu.ps1')
. (Join-Path $PSScriptRoot 'src\Workflow.Host.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:catalog = @()
$script:library=@();$script:libraryWorker=$null;$script:libraryHandle=$null;$script:libraryGeneration=0;$script:libraryJobGeneration=0;$script:libraryPending=$false;$script:libraryProfile=$null;$script:removalPlan=$null
$script:scanWorker = $null
$script:scanHandle = $null
$script:extraRoots = @();$script:preferredSteamPath=''
$script:diagnostics = @()
$script:steamProfiles=@();$script:steamStatuses=@{};$script:steamFingerprint='';$script:refreshingSteam=$false
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Storage.psm1')
$script:dataDir = Initialize-OathgateStorage -LegacyDirectory (Join-Path $PSScriptRoot 'data')
$script:settingsFile = Join-Path $script:dataDir 'settings.json'
# Seed history before last-scan is replaced, so an uninstall between app versions can be reviewed.
try{if(Test-Path -LiteralPath (Join-Path $script:dataDir 'last-scan.json')){Update-GameInstallHistory (Join-Path $script:dataDir 'install-history.json') @((Get-Content -LiteralPath (Join-Path $script:dataDir 'last-scan.json') -Raw|ConvertFrom-Json).Games)}}catch{$script:diagnostics+=('Install history: '+$_.Exception.Message)}
if (Test-Path -LiteralPath $script:settingsFile) {
    try { $savedSettings=Get-AppSettings $script:settingsFile -Recover;$script:extraRoots=@($savedSettings.ExtraRoots);$script:preferredSteamPath=[string]$savedSettings.SteamShortcutPath }
    catch { $script:diagnostics = @('Settings could not be read: ' + $_.Exception.Message) }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SteamNite | Game discovery POC'
$form.Size = New-Object System.Drawing.Size(1160, 780)
$form.MinimumSize = New-Object System.Drawing.Size(880, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'; $layout.Padding = New-Object System.Windows.Forms.Padding(20)
$layout.ColumnCount = 1; $layout.RowCount = 6
foreach ($height in @(52, 30, 78)) { [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', $height))) }
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 190)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 44)))
$form.Controls.Add($layout)

$heading = New-Object System.Windows.Forms.Label
$heading.Text = 'SteamNite   /   Game library'
$heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 21)
$heading.AutoSize = $true
$header=New-Object System.Windows.Forms.Panel;$header.Dock='Fill';$layout.Controls.Add($header,0,0)
$heading.Dock='Left';$header.Controls.Add($heading)
$headingActions=New-Object System.Windows.Forms.FlowLayoutPanel;$headingActions.Dock='Right';$headingActions.Width=260;$headingActions.WrapContents=$false;$header.Controls.Add($headingActions)
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Fill'; $toolbar.WrapContents = $true
$layout.Controls.Add($toolbar, 0, 2)
function Add-Button($Text, $Parent, $Width = 110) {
    $button = New-Object SteamNite.ActionButton
    $button.Text = $Text; $button.Width = $Width; $button.Height = 34
    $button.FlatStyle = 'Flat'; $button.BackColor = [SteamNite.DialogTheme]::Background
    $Parent.Controls.Add($button); return $button
}
. (Join-Path $PSScriptRoot 'src\Library.Filters.ps1')
$status = New-Object System.Windows.Forms.LinkLabel
$status.Dock = 'Fill'; $status.Text = 'Search by game title. Scans launcher records and XboxGames folders on every fixed drive.'
$status.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 100)
$layout.Controls.Add($status, 0, 1)
$status.LinkArea=New-Object Windows.Forms.LinkArea(0,0)
$status.Add_TextChanged({
    $notice=[regex]::Match($status.Text,'\d+ scan notices')
    $status.LinkArea=if($notice.Success -and $script:diagnostics.Count -gt 0){New-Object Windows.Forms.LinkArea($notice.Index,$notice.Length)}else{New-Object Windows.Forms.LinkArea(0,0)}
})

$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $true
$list.HideSelection = $false; $list.Dock = 'Fill'; $list.BorderStyle = 'FixedSingle'
$list.ShowItemToolTips=$true
foreach ($col in @(@('Game', 250), @('Platform', 75), @('Install state',125), @('Steam sync', 135), @('Artwork',75), @('Launch method', 160), @('Installation', 300))) {
    [void]$list.Columns.Add($col[0], [int]$col[1])
}
$layout.Controls.Add($list, 0, 3)
$details = New-Object System.Windows.Forms.TextBox
$details.Multiline = $true; $details.ReadOnly = $true; $details.ScrollBars = 'Vertical'
$details.Dock = 'Fill'; $details.BackColor = [System.Drawing.Color]::White
$details.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 10)
$details.Text = 'Select a game to inspect its installation and Steam status. Uninstalled SteamNite games can be removed directly from this list.'
$layout.Controls.Add($details, 0, 4)
$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'; $layout.Controls.Add($actions, 0, 5)
$prepare=Add-Button 'Prepare in Steam...' $actions 185;$prepare.Enabled=$false
$prepare.BackColor = [System.Drawing.Color]::FromArgb(30,85,170);$prepare.ForeColor=[System.Drawing.Color]::White
$launch = Add-Button 'Launch game' $actions 140
$launch.Enabled = $false
$artwork = Add-Button 'Artwork...' $actions 115; $artwork.Enabled = $false
$gameMenu=New-Object System.Windows.Forms.ContextMenuStrip;$gameMenu.Font=$form.Font
function Add-GameMenuItem([string]$Text){$item=New-Object System.Windows.Forms.ToolStripMenuItem($Text);$item.Enabled=$false;[void]$gameMenu.Items.Add($item);return $item}
$editLaunch=Add-GameMenuItem 'Edit launch...'
$open=Add-GameMenuItem 'Open installation folder'
$copy=Add-GameMenuItem 'Copy details'
$sync=Add-GameMenuItem 'Shortcuts only...'
$ignore=Add-GameMenuItem 'Ignore selected'
[void]$gameMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$removals=Add-GameMenuItem 'Remove from Steam...'
$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Right-click for more actions.'
$footer.AutoSize = $true; $footer.Margin = New-Object System.Windows.Forms.Padding(18, 8, 0, 0)
$actions.Controls.Add($footer)

function Update-GameList {
    $selectedIds=@($list.SelectedItems | ForEach-Object {$_.Tag.Id})
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        foreach ($game in $script:library) {
            if ($search.Text -and $game.Title.IndexOf($search.Text, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($platform.SelectedIndex -gt 0 -and $game.Platform -ne [string]$platform.SelectedItem) { continue }
            $installState=if($game.InstallState){$game.InstallState}else{'Installed'}
            if($installFilter.SelectedItem -eq 'Installed' -and $installState -ne 'Installed'){continue}
            if($installFilter.SelectedItem -eq 'Not installed' -and $installState -ne 'Not installed'){continue}
            if($installFilter.SelectedItem -eq 'Steam only' -and $installState -eq 'Installed'){continue}
            if(-not (Test-LibraryAttentionFilter $game ([string]$installFilter.SelectedItem))){continue}
            $item = New-Object System.Windows.Forms.ListViewItem($game.Title)
            [void]$item.SubItems.Add($game.Platform)
            $installCell=$item.SubItems.Add($installState)
            $installCell.ForeColor=if($installState -eq 'Installed'){[Drawing.Color]::FromArgb(30,125,70)}elseif($installState -eq 'Not installed'){[Drawing.Color]::FromArgb(155,95,20)}else{[Drawing.Color]::Gray}
            $steamState=$script:steamStatuses[$game.Id]
            $syncText=if($game.SteamSyncStatus){$game.SteamSyncStatus}elseif($steamState){$steamState.Status}else{'Checking...'}
            $syncCell=$item.SubItems.Add($syncText);$item.UseItemStyleForSubItems=$false
            $syncCell.ForeColor=switch($syncText){'Synced'{[Drawing.Color]::FromArgb(30,125,70)}'Not synced'{[Drawing.Color]::FromArgb(95,105,120)}default{[Drawing.Color]::FromArgb(155,95,20)}}
            $item.ToolTipText=if($game.AttentionDetail){$game.AttentionDetail}elseif($game.SteamSyncDetail){$game.SteamSyncDetail}elseif($steamState){$steamState.Detail}else{''}
            [void]$item.SubItems.Add([string]$game.ArtworkStatus)
            [void]$item.SubItems.Add($game.Method)
            [void]$item.SubItems.Add([string]$game.InstallPath)
            $item.Tag = $game
            if ($game.Status -ne 'Ready to test') { $item.ForeColor = [System.Drawing.Color]::FromArgb(150, 95, 25) }
            [void]$list.Items.Add($item)
            if ($game.Id -in $selectedIds) { $item.Selected = $true }
        }
    } finally { $list.EndUpdate() }
    $launch.Enabled = $false; $open.Enabled = $false; $copy.Enabled = $false; $sync.Enabled = $false;$artwork.Enabled=$false;$removals.Enabled=$false
    if ($list.SelectedItems.Count) { Show-GameDetails }
}
function Begin-LibraryRefresh {
    if($script:libraryWorker){$script:libraryPending=$true;return}
    $script:libraryPending=$false;$script:libraryJobGeneration=$script:libraryGeneration
    $script:libraryWorker=[PowerShell]::Create()
    [void]$script:libraryWorker.AddScript({
        param($removalModule,$libraryModule,$games,$profile,$history)
        $ErrorActionPreference='Stop';Import-Module $removalModule -Force;Import-Module $libraryModule -Force
        $plan=if($profile){New-SteamRemovalPlan $profile $history}else{$null}
        $library=@(Get-UnifiedGameLibrary -InstalledGames $games -Profile $profile -RemovalPlan $plan -HistoryPath $history)
        [pscustomobject]@{Games=$library;RemovalPlan=$plan}
    }).AddArgument((Join-Path $PSScriptRoot 'src\SteamNite.Removal.psm1')).AddArgument((Join-Path $PSScriptRoot 'src\SteamNite.Library.psm1')).AddArgument($script:catalog).AddArgument($script:libraryProfile).AddArgument((Join-Path $script:dataDir 'install-history.json'))
    $script:libraryHandle=$script:libraryWorker.BeginInvoke()
}
function Complete-LibraryRefresh {
    if(-not $script:libraryHandle -or -not $script:libraryHandle.IsCompleted){return}
    try{
        $result=@($script:libraryWorker.EndInvoke($script:libraryHandle))
        if($script:libraryWorker.HadErrors -or -not $result.Count){throw 'Steam-only entries could not be checked. Rescan to retry; nothing was removed.'}
        if($script:libraryJobGeneration -eq $script:libraryGeneration){
            $script:library=@($result[-1].Games);$script:removalPlan=$result[-1].RemovalPlan;Update-GameList
            $notInstalled=@($script:library|Where-Object InstallState -eq 'Not installed').Count
            $attention=@($script:library|Where-Object NeedsAttention).Count
            $status.Text=('{0} installed | {1} uninstalled Steam shortcuts | {2} need attention | {3} scan notices' -f $script:catalog.Count,$notInstalled,$attention,$script:diagnostics.Count)
        }
    }catch{if($script:libraryJobGeneration -eq $script:libraryGeneration){$status.Text=$_.Exception.Message}}
    finally{$script:libraryWorker.Dispose();$script:libraryWorker=$null;$script:libraryHandle=$null}
    if($script:libraryPending){Begin-LibraryRefresh}
    Show-GameDetails
}
function Refresh-SteamIndicators([switch]$ReloadProfiles,[switch]$Force) {
    if($script:refreshingSteam){return}
    $script:refreshingSteam=$true
    try {
        if($ReloadProfiles){
            $old=if($steamProfile.SelectedIndex -ge 0){$script:steamProfiles[$steamProfile.SelectedIndex].ShortcutPath}else{$script:preferredSteamPath}
            $script:steamProfiles=@(Get-SteamProfiles);$steamProfile.Items.Clear()
            foreach($p in $script:steamProfiles){[void]$steamProfile.Items.Add($p.Label)}
            $index=-1;for($i=0;$i -lt $script:steamProfiles.Count;$i++){if($script:steamProfiles[$i].ShortcutPath -eq $old){$index=$i}}
            if($index -ge 0){$steamProfile.SelectedIndex=$index}elseif($script:steamProfiles.Count -eq 1 -and -not $script:preferredSteamPath){$steamProfile.SelectedIndex=0}
            $Force=$true
        }
        $profile=if($steamProfile.SelectedIndex -ge 0){$script:steamProfiles[$steamProfile.SelectedIndex]}else{$null}
        $fingerprint='NO_PROFILE'
        if($profile){try{$fingerprint=$profile.ShortcutPath+'|'+(Get-ShortcutSnapshot $profile.ShortcutPath).Hash}catch{$fingerprint=$profile.ShortcutPath+'|ERROR|'+$_.Exception.Message}}
        if(-not $Force -and $fingerprint -eq $script:steamFingerprint){return}
        $script:steamFingerprint=$fingerprint;$script:steamStatuses=@{}
        foreach($state in @(Get-GameSteamStatuses -Games $script:catalog -Profile $profile)){$script:steamStatuses[$state.GameId]=$state}
        $script:libraryGeneration++;$script:libraryProfile=$profile;$script:library=@($script:catalog);$script:removalPlan=$null
        Update-GameList
        Begin-LibraryRefresh
    } catch {
        foreach($game in $script:catalog){$script:steamStatuses[$game.Id]=[pscustomobject]@{Status='Unknown';Detail=$_.Exception.Message}}
        Update-GameList
    } finally {$script:refreshingSteam=$false}
}
function Remember-SteamAccount($Profile) {
    if(-not $Profile){return}
    Save-AppSettings $script:settingsFile @{SteamShortcutPath=$Profile.ShortcutPath}
    $script:preferredSteamPath=$Profile.ShortcutPath
    $wasRefreshing=$script:refreshingSteam;$script:refreshingSteam=$true
    try{for($i=0;$i -lt $script:steamProfiles.Count;$i++){if($script:steamProfiles[$i].ShortcutPath -eq $Profile.ShortcutPath){$steamProfile.SelectedIndex=$i;break}}}
    finally{$script:refreshingSteam=$wasRefreshing}
    $script:libraryProfile=$Profile
}
function Show-GameDetails {
    $selected=@($list.SelectedItems|ForEach-Object {$_.Tag})
    $installedOnly=$selected.Count -gt 0 -and @($selected|Where-Object {$_.InstallState -and $_.InstallState -ne 'Installed'}).Count -eq 0
    $managedSelection=$selected.Count -gt 0 -and @($selected|Where-Object {-not $_.NativeGameId}).Count -eq 0
    $ignore.Enabled=$managedSelection -and -not $script:scanWorker -and -not $script:libraryWorker
    $ignore.Text=if($managedSelection -and @($selected|Where-Object {-not $_.Ignored}).Count -eq 0){'Unignore selected'}else{'Ignore selected'}
    $editLaunch.Enabled=$selected.Count -eq 1 -and $installedOnly -and -not $script:scanWorker
    $eligible=$installedOnly -and @($selected|Where-Object Ignored).Count -eq 0
    $artwork.Enabled = $selected.Count -eq 1 -and $eligible -and -not $script:scanWorker
    $sync.Enabled = $eligible -and -not $script:scanWorker
    $prepare.Enabled=$installedOnly -and -not $script:scanWorker -and -not $script:libraryWorker
    $removals.Enabled=$selected.Count -gt 0 -and @($selected|Where-Object {-not $_.CanRemove}).Count -eq 0 -and $null -ne $script:removalPlan -and -not $script:scanWorker -and -not $script:libraryWorker
    if (-not $list.SelectedItems.Count) { $launch.Enabled = $false; $open.Enabled = $false; $copy.Enabled = $false; return }
    $g = $list.SelectedItems[0].Tag
    $details.Text = @"
$($g.Title)  |  $($g.Platform)  |  $($g.Status)
ID: $($g.Id)
Install state: $(if($g.InstallState){$g.InstallState}else{'Installed'})
Steam sync: $(if($g.SteamSyncStatus){$g.SteamSyncStatus}else{$script:steamStatuses[$g.Id].Status})
$(if($g.SteamSyncDetail){$g.SteamSyncDetail}else{$script:steamStatuses[$g.Id].Detail})
Artwork: $($g.ArtworkStatus)  $($g.ArtworkDetail)
Attention: $($g.AttentionDetail)
Launch override: $(if($g.HasLaunchOverride){'Custom executable (saved)'}else{'Using detected launch'})
Installation: $($g.InstallPath)
Launch method: $($g.Method)
Target: $($g.Target)
Arguments: $($g.Arguments)
Working folder: $(if($g.LaunchWorkingDirectory){$g.LaunchWorkingDirectory}else{$g.InstallPath})
Evidence: $($g.Evidence)
$($g.Note)
"@
    $details.Text = $details.Text.Replace("`r`n", "`n").Replace("`n", "`r`n")
    $launch.Enabled = $installedOnly -and $g.Status -eq 'Ready to test' -and $list.SelectedItems.Count -eq 1
    $open.Enabled = $selected.Count -eq 1 -and [bool]$g.InstallPath -and (Test-Path -LiteralPath $g.InstallPath -PathType Container)
    $copy.Enabled = $selected.Count -eq 1
}
function Begin-GameScan {
    if ($script:scanWorker) { return }
    $scan.Enabled = $false; $addRoot.Enabled = $false; $launch.Enabled = $false; $sync.Enabled = $false; $artwork.Enabled = $false
    $allArtwork.Enabled = $false
    $removals.Enabled=$false
    $prepare.Enabled=$false
    $status.Text = 'Scanning installed games across your drives...'
    $script:scanWorker = [PowerShell]::Create()
    [void]$script:scanWorker.AddScript({ param($module, $roots) Import-Module $module -Force; Get-GameScan -ExtraRoots $roots }).AddArgument((Join-Path $PSScriptRoot 'src\SteamNite.Core.psm1')).AddArgument($script:extraRoots)
    $script:scanHandle = $script:scanWorker.BeginInvoke()
}
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
    Complete-LibraryRefresh
    if (-not $script:scanHandle -or -not $script:scanHandle.IsCompleted) { return }
    try {
        $result = @($script:scanWorker.EndInvoke($script:scanHandle))
        if (-not $result.Count) { throw ('Scan failed: ' + ($script:scanWorker.Streams.Error -join '; ')) }
        $report = $result[-1]
        $script:catalog = @($report.Games); $script:diagnostics = @($report.Diagnostics)
        Update-GameInstallHistory (Join-Path $script:dataDir 'install-history.json') $script:catalog
        [void](New-Item -ItemType Directory -Path $script:dataDir -Force)
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:dataDir 'last-scan.json') -Encoding UTF8
        Refresh-SteamIndicators -ReloadProfiles -Force
        $ready = @($script:catalog | Where-Object { $_.Status -eq 'Ready to test' }).Count
        $status.Text = '{0} games found | {1} ready to test | {2} scan notices | Updated {3}' -f $script:catalog.Count, $ready, $script:diagnostics.Count, (Get-Date -Format 'h:mm tt')
    } catch { $status.Text = $_.Exception.Message; $script:diagnostics = @($_.Exception.ToString()) }
    finally {
        $script:scanWorker.Dispose(); $script:scanWorker = $null; $script:scanHandle = $null
        $scan.Enabled = $true; $addRoot.Enabled = $true; Show-GameDetails
        $allArtwork.Enabled = $script:catalog.Count -gt 0
    }
})
$timer.Start()
$scan.Add_Click({ Begin-GameScan })
$addRoot.Add_Click({
    try{
        $result=Show-ScanFoldersDialog -Folders $script:extraRoots
        if($result.Saved){Save-AppSettings $script:settingsFile @{ExtraRoots=@($result.Folders)};$script:extraRoots=@($result.Folders);Begin-GameScan}
    }catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Scan folders','OK','Error')}
})
$settings.Add_Click({
    try{
        $profiles=@(Get-SteamProfiles)
        $selected=if($script:libraryProfile){$script:libraryProfile.ShortcutPath}else{$script:preferredSteamPath}
        $path=Show-SteamAccountSettings -Profiles $profiles -SelectedPath $selected
        if($path){
            Save-AppSettings $script:settingsFile @{SteamShortcutPath=$path};$script:preferredSteamPath=$path
            $script:refreshingSteam=$true;$steamProfile.SelectedIndex=-1;$script:refreshingSteam=$false
            Refresh-SteamIndicators -ReloadProfiles -Force
        }
    }catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Settings','OK','Error')}
})
$status.Add_LinkClicked({$logs.PerformClick()})
$logs.Add_Click({
    $message = if ($script:diagnostics.Count) { $script:diagnostics -join "`r`n`r`n" } else { 'No scan errors or missing sources reported.' }
    [void][SteamNite.DialogTheme]::ShowMessageBox($form, $message, 'Scan details', 'OK', 'Information')
})
$search.Add_TextChanged({ Update-GameList })
$platform.Add_SelectedIndexChanged({Update-FilterControls;Update-GameList})
$installFilter.Add_SelectedIndexChanged({Update-FilterControls;Update-GameList})
$steamProfile.Add_SelectedIndexChanged({if(-not $script:refreshingSteam){Refresh-SteamIndicators -Force}})
$steamWatch=New-Object System.Windows.Forms.Timer;$steamWatch.Interval=3000
$steamWatch.Add_Tick({if($form.Enabled -and -not $script:scanWorker -and $script:steamProfiles.Count){Refresh-SteamIndicators}})
$steamWatch.Start()
$list.Add_SelectedIndexChanged({ Show-GameDetails })
Initialize-GameContextMenu -List $list -Menu $gameMenu -Refresh {Show-GameDetails}
$launchAction = {
    if (-not $list.SelectedItems.Count -or -not $launch.Enabled) { return }
    $game = $list.SelectedItems[0].Tag
    try {
        Start-DetectedGame -Game $game
        $status.Text = 'Launch request sent for ' + $game.Title + '. Check the game window; successful gameplay is not yet verified.'
    } catch { [void][SteamNite.DialogTheme]::ShowMessageBox($form, $_.Exception.Message, 'Launch failed', 'OK', 'Error') }
}
$launch.Add_Click($launchAction)
$list.Add_DoubleClick($launchAction)
$open.Add_Click({
    if ($list.SelectedItems.Count) {
        $p = New-Object System.Diagnostics.ProcessStartInfo
        $p.FileName = $list.SelectedItems[0].Tag.InstallPath; $p.UseShellExecute = $true
        [void][System.Diagnostics.Process]::Start($p)
    }
})
$copy.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($details.Text) })
$artwork.Add_Click({
    if ($list.SelectedItems.Count -ne 1) { return }
    try { Show-ArtworkDialog -Game $list.SelectedItems[0].Tag -PreferredProfile $script:libraryProfile;Refresh-SteamIndicators -Force }
    catch { [void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Artwork','OK','Error') }
})
$allArtwork.Add_Click({
    try { Show-BulkArtworkDialog -Games @($script:catalog|Where-Object {$_.Id -notin @(Get-IgnoredGameIds)}) -PreferredProfile $script:libraryProfile;Refresh-SteamIndicators -Force }
    catch { [void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Artwork for all games','OK','Error') }
})
$removals.Add_Click({
    try{
        $selected=@($list.SelectedItems|ForEach-Object {$_.Tag})
        if(-not $selected.Count -or @($selected|Where-Object {-not $_.CanRemove}).Count){return}
        $review=@(foreach($game in $selected){[pscustomobject]@{Title=$game.Title;AppId=$game.SteamAppId;GameId=$game.NativeGameId}})
        $result=Remove-ReviewedSteamShortcuts -Owner $form -Plan $script:removalPlan -Selected $review
        if($result){$status.Text='Removed '+$result.Removed+' shortcut(s). Backup: '+$result.BackupPath;Refresh-SteamIndicators -Force}
    }
    catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Removal preview','OK','Error')}
})
$ignore.Add_Click({
    try{
        $selected=@($list.SelectedItems|ForEach-Object {$_.Tag})
        if(-not $ignore.Enabled){return}
        $ignored=@($selected|Where-Object {-not $_.Ignored}).Count -gt 0
        Set-GameIgnored -GameIds @($selected|ForEach-Object {$_.NativeGameId}) -Ignored $ignored
        Refresh-SteamIndicators -Force
    }catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Game exclusions','OK','Error')}
})
$editLaunch.Add_Click({
    if($editLaunch.Enabled){
        try{Show-LaunchOverrideDialog $list.SelectedItems[0].Tag;Refresh-SteamIndicators -Force}
        catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Launch settings','OK','Error')}
    }
})
$sync.Add_Click({
    try {
        $selectedGames = @($list.SelectedItems | ForEach-Object { $_.Tag })
        Show-SteamSyncDialog -Games $selectedGames
    } catch { [void][SteamNite.DialogTheme]::ShowMessageBox($form, $_.Exception.Message, 'Steam sync', 'OK', 'Error') }
})
$prepare.Add_Click({
    if(-not $prepare.Enabled){return}
    try{Show-SteamPreparationDialog -Games @($list.SelectedItems|ForEach-Object {$_.Tag}) -PreferredProfile $script:libraryProfile;Refresh-SteamIndicators -Force}
    catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Prepare in Steam','OK','Error')}
})
$history.Add_Click({
    try{Show-PreparationHistoryDialog;Refresh-SteamIndicators -Force}
    catch{[void][SteamNite.DialogTheme]::ShowMessageBox($form,$_.Exception.Message,'Activity history','OK','Error')}
})

function Show-SteamSyncDialog {
    param([object[]]$Games)
    $profiles = @(Get-SteamProfiles)
    if (-not $profiles.Count) { throw 'No Steam user profiles found. Sign into Steam once, then try again.' }
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Steam sync preview'; $dialog.Size = New-Object System.Drawing.Size(900, 640)
    $dialog.MinimumSize = New-Object System.Drawing.Size(750, 520)
    $dialog.Font = $form.Font; $dialog.StartPosition = 'CenterParent'
    $panel = New-Object System.Windows.Forms.TableLayoutPanel
    $panel.Dock = 'Fill'; $panel.Padding = New-Object System.Windows.Forms.Padding(16)
    $panel.ColumnCount = 1; $panel.RowCount = 5
    [void]$panel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 35)))
    [void]$panel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 60)))
    [void]$panel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    [void]$panel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 80)))
    [void]$panel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 45)))
    $dialog.Controls.Add($panel)
    $profilePicker = New-Object SteamNite.ThemeComboBox
    $profilePicker.AccessibleName = 'Steam profile'; $profilePicker.DropDownStyle = 'DropDownList'; $profilePicker.Dock = 'Fill'
    foreach ($p in $profiles) { [void]$profilePicker.Items.Add($p.Label) }
    $panel.Controls.Add($profilePicker, 0, 0)
    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Add or repair selected games. Repairs change launch fields only and preserve the existing Steam ID, title and artwork. Review old and new launch fields below.'
    $intro.Dock = 'Fill'; $panel.Controls.Add($intro, 0, 1)
    $preview = New-Object System.Windows.Forms.TextBox
    $preview.Multiline = $true; $preview.ReadOnly = $true; $preview.ScrollBars = 'Both'; $preview.WordWrap = $false; $preview.Dock = 'Fill'
    $panel.Controls.Add($preview, 0, 2)
    $syncStatus = New-Object System.Windows.Forms.Label
    $syncStatus.Dock = 'Fill'; $panel.Controls.Add($syncStatus, 0, 3)
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Fill'; $panel.Controls.Add($buttons, 0, 4)
    $artAfter=New-Object System.Windows.Forms.CheckBox
    $artAfter.Text='Choose artwork after syncing';$artAfter.AutoSize=$true;$artAfter.Checked=$false;$artAfter.Margin=New-Object System.Windows.Forms.Padding(3,8,12,3)
    $buttons.Controls.Add($artAfter)
    $apply = Add-Button 'Apply to Steam' $buttons 150; $apply.Enabled = $false
    $restartSteam = Add-Button 'Open Steam' $buttons 130; $restartSteam.Enabled = $false
    $close = Add-Button 'Close' $buttons 100
    # Keep event state in an object shared by this modal's callbacks.
    $context = @{ Plan=$null;NextGames=@();Profile=$null }
    $refreshPreview = {
        $apply.Enabled = $false; $context.Plan = $null
        if ($profilePicker.SelectedIndex -lt 0) { $syncStatus.Text = 'Choose the Steam account to sync.'; return }
        try {
            $context.Plan = New-SteamSyncPlan -Profile $profiles[$profilePicker.SelectedIndex] -Games $Games
            $lines = New-Object 'System.Collections.Generic.List[string]'
            $lines.Add('Destination: ' + $context.Plan.Profile.ShortcutPath)
            $lines.Add(('Existing entries: {0} | Additions: {1} | Repairs: {2}' -f $context.Plan.ExistingCount, $context.Plan.AddCount,$context.Plan.RepairCount))
            foreach ($row in $context.Plan.Rows) {
                $lines.Add(''); $lines.Add($row.Action.ToUpper() + '  ' + $row.Title)
                if($row.Action -eq 'Repair'){
                    $lines.Add('  Current target: '+$row.Existing.Exe)
                    $lines.Add('  Current folder: '+$row.Existing.StartDir)
                    $lines.Add('  Current options: '+$row.Existing.LaunchOptions)
                    $lines.Add('  Preserved Steam ID: '+$row.Existing.AppId)
                }
                if ($row.Draft) {
                    $lines.Add('  Target: ' + $row.Draft.Exe)
                    $lines.Add('  Start in: ' + $row.Draft.StartDir)
                    $lines.Add('  Launch options: ' + $row.Draft.LaunchOptions)
                    if($row.Action -ne 'Repair'){$lines.Add('  Steam shortcut ID: ' + $row.Draft.AppId)}
                }
                if ($row.Reason) { $lines.Add('  ' + $row.Reason) }
            }
            $preview.Text = $lines -join "`r`n"
            $apply.Enabled = ($context.Plan.AddCount+$context.Plan.RepairCount) -gt 0
            $syncStatus.Text = if (($context.Plan.AddCount+$context.Plan.RepairCount) -eq 0) { 'No additions or repairs needed. Existing entries are preserved.' }
                elseif (Test-SteamRunning) { 'Steam is running. Apply to Steam will offer to close it and continue.' }
                else { 'Ready. An exact backup will be saved beside shortcuts.vdf before replacing it.' }
        } catch { $preview.Text = $_.Exception.Message; $syncStatus.Text = 'Preview failed. No files changed.' }
    }
    $profilePicker.Add_SelectedIndexChanged($refreshPreview)
    $preferredIndex=-1
    for($i=0;$i -lt $profiles.Count;$i++){if($script:libraryProfile -and $profiles[$i].ShortcutPath -eq $script:libraryProfile.ShortcutPath){$preferredIndex=$i}}
    if($preferredIndex -ge 0){$profilePicker.SelectedIndex=$preferredIndex}
    elseif ($profiles.Count -eq 1) { $profilePicker.SelectedIndex = 0 }
    else { $syncStatus.Text = 'Choose the Steam account to sync.' }
    $apply.Add_Click({
        try {
            Remember-SteamAccount $context.Plan.Profile
            if(-not (Confirm-SteamClosed -Owner $dialog -Profile $context.Plan.Profile -Action 'add or repair these games')){$syncStatus.Text='Cancelled. No shortcuts were changed.';return}
            # Steam may save its in-memory shortcuts on exit. Rebase onto that fresh file,
            # but require another review if the proposed selected-game actions changed.
            $fresh=New-SteamSyncPlan -Profile $context.Plan.Profile -Games $Games
            if((Get-SteamPlanChangeSignature $fresh) -ne (Get-SteamPlanChangeSignature $context.Plan)){
                & $refreshPreview
                $syncStatus.Text='Steam saved different shortcut data while exiting. Review the updated preview before applying again.'
                return
            }
            $context.Plan=$fresh
            $result = Save-SteamSyncPlan -Plan $context.Plan
            $apply.Enabled = $false; $restartSteam.Enabled = $true; $profilePicker.Enabled = $false
            $syncStatus.Text = 'Added '+$result.Added+'; repaired '+$result.Repaired+'. Reopen Steam to load changes.'
            if ($result.BackupPath) { $syncStatus.Text += "`r`nBackup: " + $result.BackupPath }
            $status.Text = 'Steam sync complete. Added '+$result.Added+'; repaired '+$result.Repaired+'.'
            Refresh-SteamIndicators -Force
            if($artAfter.Checked -and $result.Added -gt 0){
                $ids=@($context.Plan.Rows | Where-Object Action -eq 'Add' | ForEach-Object {$_.GameId})
                $context.NextGames=@($Games | Where-Object {$_.Id -in $ids});$context.Profile=$context.Plan.Profile;$dialog.Close()
            }
        } catch { $syncStatus.Text = $_.Exception.Message }
    })
    $restartSteam.Add_Click({
        try { Open-SteamClient $context.Plan.Profile; $restartSteam.Enabled = $false }
        catch { $syncStatus.Text = $_.Exception.Message }
    })
    $close.Add_Click({ $dialog.Close() })
    Set-SteamNiteTheme $dialog
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose() }
    if($context.NextGames.Count -eq 1){Show-ArtworkDialog -Game $context.NextGames[0] -PreferredProfile $context.Profile}
    elseif($context.NextGames.Count -gt 1){Show-BulkArtworkDialog -Games $context.NextGames -PreferredProfile $context.Profile}
}
Set-SteamNiteTheme $form
$form.Add_Shown({ Begin-GameScan })
$form.Add_FormClosed({
    $gameMenu.Dispose();$searchCue.Dispose();$steamProfile.Dispose();$platform.Dispose();$installFilter.Dispose()
    $timer.Stop(); $timer.Dispose()
    $steamWatch.Stop();$steamWatch.Dispose()
    if ($script:scanWorker) { $script:scanWorker.Stop(); $script:scanWorker.Dispose() }
    if($script:libraryWorker){$script:libraryWorker.Stop();$script:libraryWorker.Dispose()}
})
if($WorkflowRequest){
    try{Invoke-ClassicWorkflow $WorkflowRequest}
    finally{
        $timer.Stop();$steamWatch.Stop()
        if($script:scanWorker){$script:scanWorker.Stop();$script:scanWorker.Dispose()}
        if($script:libraryWorker){$script:libraryWorker.Stop();$script:libraryWorker.Dispose()}
        $form.Dispose()
    }
} elseif ($SmokeTest) {
    if($layout.GetRow($toolbar) -ne 2 -or $layout.GetRow($list) -ne 3 -or $null -ne $steamProfile.Parent){throw 'Search/filters must sit immediately above the list and the account selector must remain in settings.'}
    [void](Show-ScanFoldersDialog -Folders @() -SmokeTest)
    [void](Show-SteamAccountSettings -Profiles @() -SelectedPath '' -SmokeTest)
    if(@($actions.Controls|Where-Object {$_ -is [Windows.Forms.Button]}).Count -ne 3 -or $actions.Controls[0] -ne $prepare){throw 'The bottom action row must contain Prepare, Launch and Artwork only.'}
    if($editLaunch.Owner -ne $gameMenu -or $removals.Owner -ne $gameMenu -or $history.OwnerItem -ne $toolsMenu -or $allArtwork.OwnerItem -ne $toolsMenu){throw 'Secondary actions are not in their expected menus.'}
    Show-SteamPreparationDialog -Games @() -SmokeTest
    Show-PreparationHistoryDialog -SmokeTest
    Show-LaunchOverrideDialog -Game ([pscustomobject]@{Title='UI test';Id='fixture:ui';Method='Epic launcher';Target='fixture';InstallPath=''}) -SmokeTest
    Show-ArtworkDialog -Game ([pscustomobject]@{Title='UI test';Id='fixture:ui'}) -SmokeTest
    Show-BulkArtworkDialog -Games @() -SmokeTest
    Show-SteamRemovalDialog -SmokeTest
    # Exercise UI construction without opening a window or starting games.
    $form.Dispose()
    'UI construction passed.'
} else { [System.Windows.Forms.Application]::Run($form) }
} finally { if ($ownsInstance) { $instance.ReleaseMutex() };if ($instance) { $instance.Dispose() } }
