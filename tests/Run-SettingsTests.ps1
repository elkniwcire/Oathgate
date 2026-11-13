$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Settings.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\settings-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$path=Join-Path $root 'settings.json'
try{
    Save-AppSettings $path @{ExtraRoots=@('D:\Games');Unrelated='preserved'}
    Save-AppSettings $path @{SteamShortcutPath='C:\Steam\userdata\123\config\shortcuts.vdf'}
    $settings=Get-AppSettings $path
    Assert ($settings.ExtraRoots[0] -eq 'D:\Games' -and $settings.Unrelated -eq 'preserved') 'Saving an account preserves scan folders and other settings'
    Save-AppSettings $path @{ExtraRoots=@('C:\Custom')}
    Assert ((Get-AppSettings $path).SteamShortcutPath -like '*123*') 'Saving scan folders preserves the remembered Steam account'
    Save-AppSettings $path @{ExtraRoots=@()}
    Assert (@((Get-AppSettings $path).ExtraRoots).Count -eq 0) 'Removing the last added scan folder persists an empty list'
    $folders=@(Get-NormalizedScanFolders @('D:\Games\','d:\games','D:\','D:\Games\..\Games'))
    Assert ($folders.Count -eq 2 -and $folders -contains 'D:\') 'Folder normalization deduplicates paths while retaining drive-root separators'
    Assert (Throws {Get-NormalizedScanFolders @('relative\folder')}) 'Relative scan folders are rejected'
    '{'|Set-Content -Encoding UTF8 -LiteralPath $path
    Assert (Throws {Save-AppSettings $path @{ExtraRoots=@()}}) 'Unreadable settings are not silently overwritten'
    Assert ((Get-Content -LiteralPath $path -Raw).Trim() -eq '{') 'A failed settings update preserves the original file'
    $form=New-Object Windows.Forms.Form;$headingActions=New-Object Windows.Forms.FlowLayoutPanel;$toolbar=New-Object Windows.Forms.FlowLayoutPanel
    $form.Controls.Add($headingActions);$form.Controls.Add($toolbar)
    function Add-Button($Text,$Parent,$Width=110){$button=New-Object Windows.Forms.Button;$button.Text=$Text;$button.Width=$Width;$Parent.Controls.Add($button);return $button}
    function Update-GameList {}
    . (Join-Path $PSScriptRoot '..\src\Library.Filters.ps1')
    $installFilter.Add_SelectedIndexChanged({Update-FilterControls})
    $platform.Add_SelectedIndexChanged({Update-FilterControls})
    [void]$chips['Needs attention'].Handle
    $onClick=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$onClick.Invoke($chips['Needs attention'],@([EventArgs]::Empty))
    Assert ($installFilter.SelectedItem -eq 'Needs attention' -and $chips['Needs attention'].Checked) 'A filter chip selects the corresponding library state'
    $filterItems['Ignored'].PerformClick()
    Assert ($installFilter.SelectedItem -eq 'Ignored' -and @($chips.Values|Where-Object Checked).Count -eq 0) 'An overflow state clears common-chip selection'
    $platformItems['GOG'].PerformClick()
    Assert ($platform.SelectedItem -eq 'GOG' -and $filterMenu.Text -like '*Ignored*GOG*') 'Active overflow state and platform remain visible in the menu label'
    $search.Text='fixture';$resetFilters.PerformClick()
    Assert ($search.Text -eq '' -and $platform.SelectedIndex -eq 0 -and $installFilter.SelectedIndex -eq 0 -and $chips['All games'].Checked) 'Clear filters resets search, state and platform together'
    Assert ($null -eq $steamProfile.Parent -and $null -eq $platform.Parent) 'Account and overflow selectors are absent from the always-visible toolbar'
    Assert ($history.OwnerItem -eq $toolsMenu -and $addRoot.OwnerItem -eq $toolsMenu -and $logs.OwnerItem -eq $toolsMenu) 'Occasional actions are grouped under More'
    $form.Dispose();$steamProfile.Dispose();$platform.Dispose();$installFilter.Dispose();$searchCue.Dispose()
    "`nAll $script:passed settings and filter checks passed. No personal settings changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
