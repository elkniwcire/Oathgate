# Dot-sourced after the header/filter panels are constructed.
$scan=Add-Button 'Rescan' $headingActions 110
$tools=New-Object Windows.Forms.ToolStrip;$tools.GripStyle='Hidden';$tools.BackColor=$form.BackColor;$tools.Padding=New-Object Windows.Forms.Padding(0,5,0,0)
$toolsMenu=New-Object Windows.Forms.ToolStripDropDownButton('More');$toolsMenu.Font=$form.Font;[void]$tools.Items.Add($toolsMenu);$headingActions.Controls.Add($tools)
function Add-MoreItem([string]$Text){$item=New-Object Windows.Forms.ToolStripMenuItem($Text);[void]$toolsMenu.DropDownItems.Add($item);return $item}
$addRoot=Add-MoreItem 'Manage folders...'
$settings=Add-MoreItem 'Settings...'
$logs=Add-MoreItem 'Scan details...'
$history=Add-MoreItem 'Activity history...'
[void]$toolsMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
$allArtwork=Add-MoreItem 'Recommended artwork for entire library...';$allArtwork.Enabled=$false
$searchLabel=New-Object Windows.Forms.Label;$searchLabel.Text='Search';$searchLabel.AutoSize=$true;$searchLabel.Margin=New-Object Windows.Forms.Padding(3,9,3,3);$toolbar.Controls.Add($searchLabel)
$search=New-Object Windows.Forms.TextBox;$search.AccessibleName='Search games';$search.Width=190;$search.Margin=New-Object Windows.Forms.Padding(3,6,12,3);$toolbar.Controls.Add($search)
$searchCue=New-Object Windows.Forms.ToolTip;$searchCue.SetToolTip($search,'Search game titles')
$platform=New-Object Windows.Forms.ComboBox;$platform.DropDownStyle='DropDownList'
[void]$platform.Items.AddRange([object[]]@('All platforms','Xbox','Epic','Amazon','GOG','Ubisoft','EA','Manual'));$platform.SelectedIndex=0
$steamProfile=New-Object Windows.Forms.ComboBox;$steamProfile.DropDownStyle='DropDownList'
$installFilter=New-Object Windows.Forms.ComboBox;$installFilter.DropDownStyle='DropDownList'
[void]$installFilter.Items.AddRange([object[]]@('All games','Installed','Not installed','Steam only','Needs attention','Not in Steam','Needs repair','Missing artwork','Ignored'));$installFilter.SelectedIndex=0
$chips=@{}
foreach($entry in @(@('All','All games',58),@('Needs attention','Needs attention',140),@('Not in Steam','Not in Steam',125),@('Missing artwork','Missing artwork',140))){
    $chip=New-Object Windows.Forms.RadioButton;$chip.Appearance='Button';$chip.Text=$entry[0];$chip.Tag=$entry[1];$chip.Width=$entry[2];$chip.Height=34;$chip.TextAlign='MiddleCenter';$chip.FlatStyle='Flat';$chip.AccessibleName='Filter '+$entry[0];$toolbar.Controls.Add($chip);$chips[$entry[1]]=$chip
    $chip.Add_Click({param($sender,$eventArgs) $installFilter.SelectedItem=[string]$sender.Tag})
}
$chips['All games'].Checked=$true
$filterStrip=New-Object Windows.Forms.ToolStrip;$filterStrip.GripStyle='Hidden';$filterStrip.Padding=New-Object Windows.Forms.Padding(0,5,0,0);$filterStrip.BackColor=$form.BackColor
$filterMenu=New-Object Windows.Forms.ToolStripDropDownButton('More filters');$filterMenu.Font=$form.Font;[void]$filterStrip.Items.Add($filterMenu);$toolbar.Controls.Add($filterStrip)
$filterItems=@{};$platformItems=@{}
$stateMenu=New-Object Windows.Forms.ToolStripMenuItem('Library state');[void]$filterMenu.DropDownItems.Add($stateMenu)
foreach($value in $installFilter.Items){$item=New-Object Windows.Forms.ToolStripMenuItem([string]$value);$item.Tag=[string]$value;[void]$stateMenu.DropDownItems.Add($item);$filterItems[[string]$value]=$item;$item.Add_Click({param($sender,$eventArgs) $installFilter.SelectedItem=[string]$sender.Tag})}
$platformMenu=New-Object Windows.Forms.ToolStripMenuItem('Platform');[void]$filterMenu.DropDownItems.Add($platformMenu)
foreach($value in $platform.Items){$item=New-Object Windows.Forms.ToolStripMenuItem([string]$value);$item.Tag=[string]$value;[void]$platformMenu.DropDownItems.Add($item);$platformItems[[string]$value]=$item;$item.Add_Click({param($sender,$eventArgs) $platform.SelectedItem=[string]$sender.Tag})}
$resetFilters=New-Object Windows.Forms.ToolStripMenuItem('Clear all filters');[void]$filterMenu.DropDownItems.Add($resetFilters)
function Update-FilterControls {
    foreach($value in @($chips.Keys)){$chips[$value].Checked=$value -eq [string]$installFilter.SelectedItem}
    foreach($value in @($filterItems.Keys)){$filterItems[$value].Checked=$value -eq [string]$installFilter.SelectedItem}
    foreach($value in @($platformItems.Keys)){$platformItems[$value].Checked=$value -eq [string]$platform.SelectedItem}
    $active=@();if($installFilter.SelectedIndex -gt 0 -and -not $chips.ContainsKey([string]$installFilter.SelectedItem)){$active+=[string]$installFilter.SelectedItem};if($platform.SelectedIndex -gt 0){$active+=[string]$platform.SelectedItem}
    $filterMenu.Text=if($active.Count){'More filters ('+($active -join ', ')+')'}else{'More filters'}
}
$resetFilters.Add_Click({$search.Clear();$platform.SelectedIndex=0;$installFilter.SelectedIndex=0;Update-FilterControls;Update-GameList})
Update-FilterControls
