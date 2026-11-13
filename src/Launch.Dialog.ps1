function Show-LaunchOverrideDialog {
    param($Game,[switch]$SmokeTest)
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Launch settings - '+$Game.Title;$dialog.Size=New-Object Drawing.Size(760,400)
    $dialog.MinimumSize=$dialog.Size;$dialog.StartPosition='CenterParent';$dialog.Font=$form.Font
    $panel=New-Object Windows.Forms.TableLayoutPanel
    $panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=3;$panel.RowCount=6
    [void]$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',120)))
    [void]$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    [void]$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',100)))
    foreach($height in @(85,40,40,40,55,45)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    $dialog.Controls.Add($panel)
    $detected=if($Game.DetectedGame){$Game.DetectedGame}else{$Game}
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill'
    $intro.Text="Detected: $($detected.Method)`r`n$($detected.Target)`r`nSave an executable override, then test it or use Sync to Steam to review the shortcut change."
    $panel.Controls.Add($intro,0,0);$panel.SetColumnSpan($intro,3)
    $fields=@{}
    foreach($entry in @(@('Executable',1),@('Working folder',2),@('Arguments',3))){
        $label=New-Object Windows.Forms.Label;$label.Text=$entry[0];$label.Dock='Fill';$panel.Controls.Add($label,0,$entry[1])
        $box=New-Object Windows.Forms.TextBox;$box.Dock='Fill';$box.AccessibleName='Launch '+$entry[0];$panel.Controls.Add($box,1,$entry[1]);$fields[$entry[0]]=$box
    }
    if($Game.HasLaunchOverride){$fields.Executable.Text=$Game.Target;$fields['Working folder'].Text=$Game.LaunchWorkingDirectory;$fields.Arguments.Text=$Game.Arguments}
    elseif($Game.Method -eq 'Xbox launch helper'){$fields.Executable.Text=$Game.Target;$fields['Working folder'].Text=$Game.InstallPath}
    else{$fields['Working folder'].Text=$Game.InstallPath}
    $browse=New-Object Windows.Forms.Button;$browse.Text='Browse...';$browse.Dock='Fill';$panel.Controls.Add($browse,2,1)
    $folder=New-Object Windows.Forms.Button;$folder.Text='Browse...';$folder.Dock='Fill';$panel.Controls.Add($folder,2,2)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$panel.Controls.Add($message,0,4);$panel.SetColumnSpan($message,3)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,5);$panel.SetColumnSpan($buttons,3)
    $save=Add-Button 'Save override' $buttons 140
    $reset=Add-Button 'Use detected launch' $buttons 180
    $close=Add-Button 'Cancel' $buttons 100
    $browse.Add_Click({
        $picker=New-Object Windows.Forms.OpenFileDialog;$picker.Filter='Executable (*.exe)|*.exe';$picker.CheckFileExists=$true
        try{if($picker.ShowDialog($dialog) -eq 'OK'){$fields.Executable.Text=$picker.FileName;$fields['Working folder'].Text=Split-Path $picker.FileName}}finally{$picker.Dispose()}
    })
    $folder.Add_Click({
        $picker=New-Object Windows.Forms.FolderBrowserDialog
        try{if($picker.ShowDialog($dialog) -eq 'OK'){$fields['Working folder'].Text=$picker.SelectedPath}}finally{$picker.Dispose()}
    })
    $save.Add_Click({
        try{Set-GameLaunchOverride -GameId $Game.Id -Executable $fields.Executable.Text.Trim().Trim('"') -WorkingDirectory $fields['Working folder'].Text.Trim().Trim('"') -Arguments $fields.Arguments.Text;$dialog.Close()}
        catch{$message.Text=$_.Exception.Message}
    })
    $reset.Add_Click({try{Set-GameLaunchOverride -GameId $Game.Id -Reset;$dialog.Close()}catch{$message.Text=$_.Exception.Message}})
    $close.Add_Click({$dialog.Close()})
    Set-SteamNiteTheme $dialog
    try{if(-not $SmokeTest){[void]$dialog.ShowDialog($form)}}finally{$dialog.Dispose()}
}
