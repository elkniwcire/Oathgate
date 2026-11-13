function Initialize-RemovalSelection {
    param($Rows,$RemoveButton,$Context)
    $handler={
        param($eventSender,$eventArgs)
        # $args is a PowerShell automatic variable; never use it as an event parameter.
        if($null -eq $eventArgs -or $null -eq $eventArgs.Index -or $eventArgs.Index -lt 0 -or $eventArgs.Index -ge $eventSender.Items.Count){$RemoveButton.Enabled=$false;return}
        $index=$eventArgs.Index
        $item=$eventSender.Items[$index]
        if($null -eq $item.Tag -or $item.Tag.Status -ne 'Removal candidate' -or $Context.Worker){$eventArgs.NewValue=[Windows.Forms.CheckState]::Unchecked}
        # ItemCheck fires before the new value takes effect. Count the other items
        # and then include this event's proposed value rather than double-counting it.
        $count=0
        for($i=0;$i -lt $eventSender.Items.Count;$i++){
            if($i -ne $index -and $eventSender.Items[$i].Checked -and $eventSender.Items[$i].Tag.Status -eq 'Removal candidate'){$count++}
        }
        if($eventArgs.NewValue -eq [Windows.Forms.CheckState]::Checked){$count++}
        $RemoveButton.Enabled=$count -gt 0 -and -not $Context.Worker
    }.GetNewClosure()
    $Rows.Add_ItemCheck($handler)
}
function Remove-ReviewedSteamShortcuts {
    param($Owner,$Plan,[object[]]$Selected)
    if(-not $Selected.Count){return $null}
    $names=($Selected|ForEach-Object {$_.Title}) -join "`r`n"
    $choice=[SteamNite.DialogTheme]::ShowMessageBox($Owner,('Remove these '+$Selected.Count+' uninstalled-game shortcut(s) from Steam?'+"`r`n`r`n"+$names+"`r`n`r`nA backup will be saved. Game files and artwork stay intact."),'Remove selected shortcuts?',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
    if($choice -ne [Windows.Forms.DialogResult]::Yes){return $null}
    if(-not (Confirm-SteamClosed -Owner $Owner -Profile $Plan.Profile -Action 'remove these selected shortcuts')){return $null}
    $fresh=New-SteamRemovalPlan $Plan.Profile $Plan.HistoryPath
    foreach($row in $Selected){if(@($fresh.Rows|Where-Object {$_.AppId -eq $row.AppId -and $_.GameId -eq $row.GameId -and $_.Status -eq 'Removal candidate'}).Count -ne 1){throw 'The uninstall evidence changed. Rescan the library before removing shortcuts; nothing was removed.'}}
    return Save-SteamRemovalPlan -Plan $fresh -SelectedAppIds ([uint32[]]@($Selected|ForEach-Object {$_.AppId}))
}
function Show-SteamRemovalDialog {
    param($PreferredProfile=$null,[switch]$SmokeTest)
    $profiles=@(Get-SteamProfiles)
    if(-not $profiles.Count -and -not $SmokeTest){throw 'No Steam profiles found.'}
    $window=New-Object Windows.Forms.Form;$window.Text='Review uninstalled-game shortcuts';$window.Size=New-Object Drawing.Size(1060,700);$window.MinimumSize=New-Object Drawing.Size(900,580);$window.Font=$form.Font;$window.StartPosition='CenterParent'
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=5
    foreach($height in @(65,40)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    [void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
    foreach($height in @(90,45)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))};$window.Controls.Add($panel)
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill';$intro.Text='Manual test: review and check the uninstalled-game shortcuts you want removed from Steam. Only SteamNite-created entries are eligible. Game files, artwork and manually added shortcuts are preserved. A backup is saved before removal.';$panel.Controls.Add($intro,0,0)
    $picker=New-Object SteamNite.ThemeComboBox;$picker.Dock='Fill';$picker.DropDownStyle='DropDownList';$picker.AccessibleName='Removal Steam profile';foreach($p in $profiles){[void]$picker.Items.Add($p.Label)};$panel.Controls.Add($picker,0,1)
    $rows=New-Object Windows.Forms.ListView;$rows.View='Details';$rows.Dock='Fill';$rows.FullRowSelect=$true;$rows.CheckBoxes=$true;$rows.ShowItemToolTips=$true
    foreach($c in @(@('Game',260),@('Decision',150),@('Evidence / reason',590))){[void]$rows.Columns.Add($c[0],$c[1])};$panel.Controls.Add($rows,0,2)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$panel.Controls.Add($message,0,3)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,4)
    $refresh=Add-Button 'Refresh preview' $buttons 155
    $remove=Add-Button 'Remove checked shortcuts' $buttons 240;$remove.Enabled=$false
    $open=Add-Button 'Open Steam' $buttons 120
    $close=Add-Button 'Close' $buttons 100
    $ctx=@{Plan=$null;Worker=$null;Handle=$null;Busy=$false}
    function Start-RemovalPreview {
        if($ctx.Worker -or $picker.SelectedIndex -lt 0){return}
        $ctx.Plan=$null;$rows.Items.Clear();$remove.Enabled=$false;$refresh.Enabled=$false;$picker.Enabled=$false;$message.Text='Checking platform installation records and previous install locations...'
        $ctx.Worker=[PowerShell]::Create()
        [void]$ctx.Worker.AddScript({param($module,$profile,$history) $ErrorActionPreference='Stop';Import-Module $module -Force;New-SteamRemovalPlan $profile $history}).AddArgument((Join-Path $PSScriptRoot 'SteamNite.Removal.psm1')).AddArgument($profiles[$picker.SelectedIndex]).AddArgument((Join-Path $script:dataDir 'install-history.json'))
        $ctx.Handle=$ctx.Worker.BeginInvoke()
    }
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=200
    $timer.Add_Tick({
        if(-not $ctx.Handle -or -not $ctx.Handle.IsCompleted){return}
        try{
            $result=@($ctx.Worker.EndInvoke($ctx.Handle))
            if($ctx.Worker.HadErrors -or -not $result.Count){throw 'Removal preview could not be completed. Nothing was removed.'}
            $ctx.Plan=$result[-1]
            foreach($row in $ctx.Plan.Rows){
                $item=New-Object Windows.Forms.ListViewItem($row.Title);[void]$item.SubItems.Add($row.Status);[void]$item.SubItems.Add($row.Reason);$item.Tag=$row;$item.ToolTipText=$row.Reason
                if($row.Status -eq 'Removal candidate'){$item.ForeColor=[Drawing.Color]::FromArgb(150,80,20)}elseif($row.Status -eq 'Cannot verify'){$item.ForeColor=[Drawing.Color]::Gray}
                [void]$rows.Items.Add($item)
            }
            $count=@($ctx.Plan.Rows|Where-Object Status -eq 'Removal candidate').Count
            $message.Text="$count removal candidate(s). Nothing is selected automatically. Check entries to remove; unavailable or unreadable sources are preserved."
            if($ctx.Plan.Notices.Count){$message.Text+="`r`n"+($ctx.Plan.Notices -join ' ')}
        }catch{$message.Text=$_.Exception.GetBaseException().Message}
        finally{$ctx.Worker.Dispose();$ctx.Worker=$null;$ctx.Handle=$null;$refresh.Enabled=$true;$picker.Enabled=$true}
    })
    Initialize-RemovalSelection -Rows $rows -RemoveButton $remove -Context $ctx
    $picker.Add_SelectedIndexChanged({Start-RemovalPreview})
    $refresh.Add_Click({Start-RemovalPreview})
    $remove.Add_Click({
        try{
            $selected=@($rows.CheckedItems|ForEach-Object {$_.Tag})
            if(-not $selected.Count){return}
            $choice=[SteamNite.DialogTheme]::ShowMessageBox($window,('Remove '+$selected.Count+' checked shortcut(s) from Steam? A backup will be saved. Game files and artwork will stay intact.'),'Remove checked shortcuts?',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
            if($choice -ne [Windows.Forms.DialogResult]::Yes){return}
            if(-not (Confirm-SteamClosed -Owner $window -Profile $ctx.Plan.Profile -Action 'remove these checked shortcuts')){$message.Text='Cancelled. Nothing was removed.';return}
            $fresh=New-SteamRemovalPlan $ctx.Plan.Profile $ctx.Plan.HistoryPath
            foreach($row in $selected){if(@($fresh.Rows|Where-Object {$_.AppId -eq $row.AppId -and $_.GameId -eq $row.GameId -and $_.Status -eq 'Removal candidate'}).Count -ne 1){Start-RemovalPreview;throw 'The uninstall evidence changed. Review the refreshed preview; nothing was removed.'}}
            $result=Save-SteamRemovalPlan -Plan $fresh -SelectedAppIds ([uint32[]]@($selected|ForEach-Object {$_.AppId}))
            $remove.Enabled=$false;$message.Text='Removed '+$result.Removed+' shortcut(s). Reopen Steam to load the changes.'+"`r`nBackup: "+$result.BackupPath
            $rows.Items.Clear();$ctx.Plan=$null;Refresh-SteamIndicators -Force
        }catch{$message.Text=$_.Exception.GetBaseException().Message}
    })
    $open.Add_Click({try{if($picker.SelectedIndex -lt 0){throw 'Choose a Steam account.'};Open-SteamClient $profiles[$picker.SelectedIndex]}catch{$message.Text=$_.Exception.Message}})
    $close.Add_Click({$window.Close()})
    if($PreferredProfile){for($i=0;$i -lt $profiles.Count;$i++){if($profiles[$i].ShortcutPath -eq $PreferredProfile.ShortcutPath){$picker.SelectedIndex=$i;break}}}
    if($picker.SelectedIndex -lt 0 -and $profiles.Count -eq 1 -and -not $SmokeTest){$picker.SelectedIndex=0}
    $timer.Start()
    Set-SteamNiteTheme $window
    try{if($SmokeTest){'Removal UI construction passed.'}else{[void]$window.ShowDialog($form)}}
    finally{$timer.Stop();$timer.Dispose();if($ctx.Worker){$ctx.Worker.Stop();$ctx.Worker.Dispose()};$window.Dispose()}
}
