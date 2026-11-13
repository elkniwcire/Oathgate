function Show-ScanFoldersDialog {
    param([string[]]$Folders,[switch]$SmokeTest)
    $window=New-Object Windows.Forms.Form;$window.Text='Manage scan folders';$window.Size=New-Object Drawing.Size(950,620);$window.MinimumSize=New-Object Drawing.Size(800,500);$window.Font=$form.Font;$window.StartPosition='CenterParent'
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=4
    [void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',65)));[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',50)));[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',45)));$window.Controls.Add($panel)
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill';$intro.Text='Added folders supplement automatic discovery for Xbox, GOG and EA games. Removing an added folder only stops this extra scan; game files stay intact. Games may still be found through launcher records or automatic locations.';$panel.Controls.Add($intro,0,0)
    $rows=New-Object Windows.Forms.ListView;$rows.Dock='Fill';$rows.View='Details';$rows.FullRowSelect=$true;$rows.MultiSelect=$false
    foreach($c in @(@('Location / source',550),@('Scan type',150),@('Availability',140))){[void]$rows.Columns.Add($c[0],$c[1])};$panel.Controls.Add($rows,0,1)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$panel.Controls.Add($message,0,2)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,3)
    $add=Add-Button 'Add folder...' $buttons 140;$remove=Add-Button 'Remove added folder' $buttons 185;$remove.Enabled=$false
    $save=Add-Button 'Save and rescan' $buttons 165;$cancel=Add-Button 'Cancel' $buttons 100
    $state=@{Folders=@(Get-NormalizedScanFolders $Folders);Saved=$false}
    $automatic=@(Get-AutomaticScanFolders)
    $refresh={
        $rows.Items.Clear()
        foreach($path in $state.Folders){$item=New-Object Windows.Forms.ListViewItem($path);[void]$item.SubItems.Add('Added by you');[void]$item.SubItems.Add($(if(Test-Path -LiteralPath $path -PathType Container){'Available'}else{'Unavailable'}));$item.Tag=$path;[void]$rows.Items.Add($item)}
        foreach($path in $automatic){$item=New-Object Windows.Forms.ListViewItem($path);[void]$item.SubItems.Add('Automatic');[void]$item.SubItems.Add($(if(Test-Path -LiteralPath $path -PathType Container){'Available'}else{'Not present'}));[void]$rows.Items.Add($item)}
        foreach($source in @('Xbox / Microsoft Store package registrations','Epic installed-game manifests','Amazon installed-game database','GOG game and offline-installer registrations','Ubisoft Connect installed product registrations','EA / Origin game and uninstall registrations')){
            $item=New-Object Windows.Forms.ListViewItem($source);[void]$item.SubItems.Add('Launcher records');[void]$item.SubItems.Add('See scan details');[void]$rows.Items.Add($item)
        }
        $remove.Enabled=$false;$message.Text=$state.Folders.Count.ToString()+' added folder(s). Automatic locations are checked on each scan and cannot be removed here.'
    }
    $rows.Add_SelectedIndexChanged({$remove.Enabled=$rows.SelectedItems.Count -eq 1 -and [bool]$rows.SelectedItems[0].Tag})
    $add.Add_Click({
        $picker=New-Object Windows.Forms.FolderBrowserDialog;$picker.Description='Choose an Xbox, GOG or EA library folder, or an individual game folder.'
        try{if($picker.ShowDialog($window) -eq 'OK'){
            $path=@(Get-NormalizedScanFolders @($picker.SelectedPath))[0]
            if($path -in $state.Folders -or $path -in $automatic){$message.Text='This folder is already listed; it does not need to be added again.'}
            else{$state.Folders=@(Get-NormalizedScanFolders (@($state.Folders)+@($path)));& $refresh}
        }}finally{$picker.Dispose()}
    })
    $remove.Add_Click({if($remove.Enabled){$path=$rows.SelectedItems[0].Tag;$state.Folders=@($state.Folders|Where-Object {$_ -ne $path});& $refresh}})
    $save.Add_Click({$state.Saved=$true;$window.Close()});$cancel.Add_Click({$window.Close()});& $refresh
    Set-SteamNiteTheme $window
    try{if(-not $SmokeTest){[void]$window.ShowDialog($form)}}finally{$window.Dispose()}
    return [pscustomobject]@{Saved=$state.Saved;Folders=$state.Folders}
}
function Show-SteamAccountSettings {
    param([object[]]$Profiles,[string]$SelectedPath,[switch]$SmokeTest)
    $window=New-Object Windows.Forms.Form;$window.Text='Settings';$window.Size=New-Object Drawing.Size(750,250);$window.Font=$form.Font;$window.StartPosition='CenterParent'
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=3
    foreach($height in @(65,40,45)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill';$intro.Text='Steam account for library status and Steam actions. The choice is remembered. Each apply preview still shows its destination account.';$panel.Controls.Add($intro,0,0)
    $picker=New-Object SteamNite.ThemeComboBox;$picker.DropDownStyle='DropDownList';$picker.Dock='Fill';$picker.AccessibleName='Preferred Steam account'
    foreach($profile in $Profiles){[void]$picker.Items.Add($profile.Label)}
    for($i=0;$i -lt $Profiles.Count;$i++){if($Profiles[$i].ShortcutPath -eq $SelectedPath){$picker.SelectedIndex=$i}}
    if($picker.SelectedIndex -lt 0 -and $Profiles.Count -eq 1){$picker.SelectedIndex=0};$panel.Controls.Add($picker,0,1)
    if(-not $Profiles.Count){$intro.Text='No Steam accounts were found. Sign into Steam once, then rescan.'}
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,2)
    $save=Add-Button 'Save' $buttons 110;$save.Enabled=$picker.SelectedIndex -ge 0;$cancel=Add-Button 'Cancel' $buttons 110
    $state=@{Path=''};$picker.Add_SelectedIndexChanged({$save.Enabled=$picker.SelectedIndex -ge 0})
    $save.Add_Click({$state.Path=$Profiles[$picker.SelectedIndex].ShortcutPath;$window.Close()});$cancel.Add_Click({$window.Close()})
    Set-SteamNiteTheme $window
    try{if(-not $SmokeTest){[void]$window.ShowDialog($form)}}finally{$window.Dispose()}
    return $state.Path
}
