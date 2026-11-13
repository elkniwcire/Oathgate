function Show-SteamPreparationDialog {
    param([object[]]$Games,$PreferredProfile=$null,[bool]$IncludeArtwork=$true,[switch]$SmokeTest)
    $profiles=@(Get-SteamProfiles)
    if(-not $profiles.Count -and -not $SmokeTest){throw 'No Steam accounts found.'}
    $window=New-Object Windows.Forms.Form;$window.Text='Prepare selected games in Steam'
    $window.Size=New-Object Drawing.Size(1060,760);$window.MinimumSize=New-Object Drawing.Size(900,650);$window.Font=$form.Font;$window.StartPosition='CenterParent'
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=7
    foreach($height in @(55,36,38,36)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    [void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
    foreach($height in @(70,80)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    $window.Controls.Add($panel)
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill';$intro.Text='Only the games listed below will be prepared. Add missing shortcuts, repair outdated launch fields and fill missing recommended artwork. Existing images are preserved; uncertain matches need a manual choice. No games are removed.';$panel.Controls.Add($intro,0,0)
    $picker=New-Object SteamNite.ThemeComboBox;$picker.Dock='Fill';$picker.DropDownStyle='DropDownList';$picker.AccessibleName='Preparation Steam account'
    foreach($p in $profiles){[void]$picker.Items.Add($p.Label)};$panel.Controls.Add($picker,0,1)
    $credentials=New-Object Windows.Forms.FlowLayoutPanel;$credentials.Dock='Fill';$panel.Controls.Add($credentials,0,2)
    $art=New-Object Windows.Forms.CheckBox;$art.Text='Fill recommended artwork';$art.AutoSize=$true;$art.Checked=$IncludeArtwork;$credentials.Controls.Add($art)
    $keyLabel=New-Object Windows.Forms.Label;$keyLabel.Text='SteamGridDB key:';$keyLabel.AutoSize=$true;$credentials.Controls.Add($keyLabel)
    $key=New-Object Windows.Forms.TextBox;$key.UseSystemPasswordChar=$true;$key.Width=270;$key.AccessibleName='Preparation SteamGridDB API key';$credentials.Controls.Add($key)
    $remember=New-Object Windows.Forms.CheckBox;$remember.Text='Remember key';$remember.AutoSize=$true;$credentials.Controls.Add($remember)
    try{$saved=Get-ArtworkApiKey $script:dataDir;if($saved){$key.Text=$saved;$remember.Checked=$true};$saved=$null}catch{}
    $reopen=New-Object Windows.Forms.CheckBox;$reopen.Text='Reopen Steam when finished';$reopen.Checked=$true;$reopen.AutoSize=$true;$panel.Controls.Add($reopen,0,3)
    $rows=New-Object Windows.Forms.ListView;$rows.Dock='Fill';$rows.View='Details';$rows.FullRowSelect=$true;$rows.ShowItemToolTips=$true;$rows.MultiSelect=$false
    foreach($c in @(@('Game',225),@('Shortcut',120),@('Artwork',145),@('Result / details',510))){[void]$rows.Columns.Add($c[0],$c[1])};$panel.Controls.Add($rows,0,4)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$message.Text='Choose a Steam account to preview.';$panel.Controls.Add($message,0,5)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,6)
    $apply=Add-Button 'Prepare in Steam' $buttons 170;$apply.Enabled=$false
    $refresh=Add-Button 'Refresh preview' $buttons 150
    $stop=Add-Button 'Stop after current step' $buttons 190;$stop.Enabled=$false
    $retry=Add-Button 'Retry unfinished' $buttons 155;$retry.Enabled=$false
    $resolve=Add-Button 'Choose artwork...' $buttons 160;$resolve.Enabled=$false
    $openSteam=Add-Button 'Open Steam' $buttons 125
    $close=Add-Button 'Close' $buttons 100
    $context=@{Plan=$null;Worker=$null;Handle=$null;Running=$false;Activity=$null;Games=$Games;Profile=$null;Cancellation=$null;Progress=$null}
    $paintActivity={param($activity)
        $rows.Items.Clear()
        foreach($row in $activity.Rows){$item=New-Object Windows.Forms.ListViewItem($row.Title);[void]$item.SubItems.Add($row.Shortcut);[void]$item.SubItems.Add($row.Artwork);[void]$item.SubItems.Add($row.Status+': '+$row.Detail);$item.Tag=$row;$item.ToolTipText=$row.Detail;[void]$rows.Items.Add($item)}
        $message.Text=$activity.Status+': '+$activity.Detail
        if($activity.BackupPath){$message.Text+="`r`nShortcut backup: "+$activity.BackupPath}
    }
    $refreshPreview={
        $context.Activity=$null;$retry.Enabled=$false;$resolve.Enabled=$false
        $context.Plan=$null;$apply.Enabled=$false;$rows.Items.Clear();$key.Enabled=$art.Checked;$remember.Enabled=$art.Checked
        if($picker.SelectedIndex -lt 0){return}
        try{
            $context.Profile=$profiles[$picker.SelectedIndex]
            $context.Plan=New-SteamPreparationPlan -Profile $context.Profile -Games $context.Games -IncludeArtwork $art.Checked
            foreach($row in $context.Plan.Rows){
                $item=New-Object Windows.Forms.ListViewItem($row.Title);[void]$item.SubItems.Add($row.Action);[void]$item.SubItems.Add($row.Artwork);[void]$item.SubItems.Add($row.Detail)
                $tip=$row.Detail
                if($row.Action -eq 'Repair'){$tip+="`r`nCurrent: "+$row.Existing.Exe+' | '+$row.Existing.StartDir+' | '+$row.Existing.LaunchOptions+"`r`nProposed: "+$row.Draft.Exe+' | '+$row.Draft.StartDir+' | '+$row.Draft.LaunchOptions}
                $item.ToolTipText=$tip;$item.Tag=$row;[void]$rows.Items.Add($item)
            }
            $apply.Enabled=@($context.Plan.Rows|Where-Object Eligible).Count -gt 0
            $message.Text=('{0} selected | {1} additions | {2} repairs | {3} games need artwork. Apply offers to close Steam once. Select a repair row to inspect its changes.' -f $context.Games.Count,$context.Plan.AddCount,$context.Plan.RepairCount,$context.Plan.ArtworkCount)
        }catch{$message.Text=$_.Exception.GetBaseException().Message}
    }
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=150
    $timer.Add_Tick({
        if($null -ne $context.Progress){$update=$null;while($context.Progress.TryDequeue([ref]$update)){& $paintActivity ($update|ConvertFrom-Json)}}
        if(-not $context.Handle -or -not $context.Handle.IsCompleted){return}
        try{
            $output=@($context.Worker.EndInvoke($context.Handle))
            if($context.Worker.HadErrors -or -not $output.Count){throw ('Preparation worker stopped. Check Activity history before retrying. '+($context.Worker.Streams.Error -join '; '))}
            $context.Activity=$output[-1];& $paintActivity $context.Activity
        }catch{$message.Text=$_.Exception.GetBaseException().Message}
        finally{
            $context.Worker.Dispose();$context.Worker=$null;$context.Handle=$null;$context.Running=$false;$stop.Enabled=$false;$close.Enabled=$true;$openSteam.Enabled=$true
            $refresh.Enabled=$true;$picker.Enabled=$true;$art.Enabled=$true;$reopen.Enabled=$true;$key.Enabled=$art.Checked;$remember.Enabled=$art.Checked
            $retry.Enabled=$null -ne $context.Activity -and @(Get-PreparationRetryGames $context.Activity $script:catalog $context.Profile).Count -gt 0
            Refresh-SteamIndicators -Force
        }
        if($reopen.Checked){try{if(-not (Test-SteamRunning)){Open-SteamClient $context.Profile}}catch{$message.Text+="`r`nCould not reopen Steam: "+$_.Exception.Message}}
    })
    $apply.Add_Click({
        try{
            if(-not $context.Plan){throw 'Refresh the preview first.'}
            Remember-SteamAccount $context.Profile
            if($art.Checked -and $context.Plan.ArtworkCount -gt 0 -and [string]::IsNullOrWhiteSpace($key.Text)){throw 'Enter a SteamGridDB API key or turn off recommended artwork.'}
            if(-not (Confirm-SteamClosed -Owner $window -Profile $context.Profile -Action 'prepare these selected games')){$message.Text='Cancelled. No changes applied.';return}
            $fresh=New-SteamPreparationPlan -Profile $context.Profile -Games $context.Games -IncludeArtwork $art.Checked
            if((Get-PreparationSignature $fresh) -ne (Get-PreparationSignature $context.Plan)){& $refreshPreview;$message.Text='The proposed changes changed while Steam was closing. Review the refreshed preview and apply again.';return}
            $context.Plan=$fresh
            if($art.Checked -and $remember.Checked -and $key.Text){Set-ArtworkApiKey $script:dataDir $key.Text.Trim()}
            $context.Cancellation=[hashtable]::Synchronized(@{Stop=$false});$context.Progress=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
            $context.Activity=$null;$context.Running=$true
            foreach($control in @($apply,$refresh,$picker,$art,$key,$remember,$retry,$resolve,$close,$openSteam,$reopen)){$control.Enabled=$false};$stop.Enabled=$true
            $context.Worker=[PowerShell]::Create()
            [void]$context.Worker.AddScript({param($module,$plan,$data,$key,$cancel,$progress) $ErrorActionPreference='Stop';Import-Module $module -Force;Invoke-SteamPreparation -Plan $plan -DataDirectory $data -ApiKey $key -Cancellation $cancel -Progress $progress}).AddArgument((Join-Path $PSScriptRoot 'SteamNite.Preparation.psm1')).AddArgument($fresh).AddArgument($script:dataDir).AddArgument($key.Text.Trim()).AddArgument($context.Cancellation).AddArgument($context.Progress)
            $context.Handle=$context.Worker.BeginInvoke();$message.Text='Preparing shortcuts...'
        }catch{
            $message.Text=$_.Exception.GetBaseException().Message
            if(-not $context.Handle){
                if($context.Worker){$context.Worker.Dispose();$context.Worker=$null}
                $context.Running=$false
                foreach($control in @($refresh,$picker,$art,$remember,$key,$close,$openSteam,$reopen)){$control.Enabled=$true}
                $stop.Enabled=$false;$apply.Enabled=$null -ne $context.Plan
            }
        }
    })
    $refresh.Add_Click($refreshPreview);$picker.Add_SelectedIndexChanged($refreshPreview);$art.Add_CheckedChanged($refreshPreview)
    $stop.Add_Click({$context.Cancellation.Stop=$true;$stop.Enabled=$false;$message.Text='Stopping after the current step finishes safely...'})
    $retry.Add_Click({
        try{
            $retryGames=@(Get-PreparationRetryGames $context.Activity $script:catalog $context.Profile)
            if(-not $retryGames.Count){throw 'No unfinished games are currently installed.'}
            $context.Games=$retryGames;$retry.Enabled=$false;$context.Activity=$null;& $refreshPreview
        }catch{$message.Text=$_.Exception.Message}
    })
    $rows.Add_SelectedIndexChanged({
        $resolve.Enabled=$false
        if($context.Running -or -not $rows.SelectedItems.Count){return}
        $row=$rows.SelectedItems[0].Tag
        if($row.Action -eq 'Repair' -and $row.Existing){$message.Text=$rows.SelectedItems[0].ToolTipText}
        if($context.Activity -and $row.Artwork -in @('Needs match','Partial','Failed')){$resolve.Enabled=$true}
    })
    $resolve.Add_Click({
        try{$id=$rows.SelectedItems[0].Tag.GameId;$game=@($script:catalog|Where-Object Id -eq $id)[0];if($game){Show-ArtworkDialog -Game $game -PreferredProfile $context.Profile;Refresh-SteamIndicators -Force;$message.Text='Artwork choices saved. Retry unfinished to check current completeness.'}}
        catch{$message.Text=$_.Exception.Message}
    })
    $openSteam.Add_Click({try{if($picker.SelectedIndex -lt 0){throw 'Choose a Steam account.'};if(-not (Test-SteamRunning)){Open-SteamClient $profiles[$picker.SelectedIndex]}}catch{$message.Text=$_.Exception.Message}})
    $close.Add_Click({$window.Close()})
    $window.Add_FormClosing({param($sender,$eventArgs) if($context.Running){$eventArgs.Cancel=$true;$context.Cancellation.Stop=$true;$stop.Enabled=$false;$message.Text='Stopping safely. Close again after the current step finishes.'}})
    $index=if($profiles.Count -eq 1){0}else{-1}
    if($PreferredProfile){for($i=0;$i -lt $profiles.Count;$i++){if($profiles[$i].ShortcutPath -eq $PreferredProfile.ShortcutPath){$index=$i}}}
    if($index -ge 0){$picker.SelectedIndex=$index}
    $timer.Start()
    Set-SteamNiteTheme $window
    try{if($SmokeTest){'Preparation UI construction passed.'}else{[void]$window.ShowDialog($form)}}finally{$timer.Stop();$timer.Dispose();$key.Clear();$window.Dispose()}
}

function Show-PreparationHistoryDialog {
    param([switch]$SmokeTest)
    $window=New-Object Windows.Forms.Form;$window.Text='SteamNite activity history';$window.Size=New-Object Drawing.Size(1000,660);$window.StartPosition='CenterParent';$window.Font=$form.Font
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=4
    foreach($height in @(45,70)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    [void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',45)));$window.Controls.Add($panel)
    $picker=New-Object SteamNite.ThemeComboBox;$picker.Dock='Fill';$picker.DropDownStyle='DropDownList';$picker.AccessibleName='Preparation activity';$panel.Controls.Add($picker,0,0)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$message.Text='No preparation operations recorded yet. History records this workflow; it does not provide undo.';$panel.Controls.Add($message,0,1)
    $details=New-Object Windows.Forms.TextBox;$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars='Both';$details.Dock='Fill';$panel.Controls.Add($details,0,2)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,3)
    $retry=Add-Button 'Review unfinished...' $buttons 190;$retry.Enabled=$false;$close=Add-Button 'Close' $buttons 100
    $activities=@(Get-PreparationActivities $script:dataDir);$history=@{Games=@();Profile=$null;IncludeArtwork=$true}
    foreach($activity in $activities){[void]$picker.Items.Add(($activity.StartedAt+' | '+$activity.Status+' | '+$activity.Rows.Count+' game(s) | Account '+$activity.Profile.AccountId))}
    $picker.Add_SelectedIndexChanged({
        $activity=$activities[$picker.SelectedIndex];$message.Text=$activity.Status+': '+$activity.Detail
        $lines=@('Shortcut backup: '+$activity.BackupPath,'')
        foreach($row in $activity.Rows){$lines+=($row.Title+' | '+$row.Status+' | Shortcut: '+$row.Shortcut+' | Artwork: '+$row.Artwork);$lines+=$row.Detail;$lines+=''}
        $details.Text=$lines -join "`r`n";$retry.Enabled=$activity.Status -ne 'Unreadable' -and @($activity.Rows|Where-Object {$_.Status -notin @('Complete','Ignored')}).Count -gt 0
    })
    $retry.Add_Click({
        try{
            $activity=$activities[$picker.SelectedIndex];$profiles=@(Get-SteamProfiles|Where-Object ShortcutPath -eq $activity.Profile.ShortcutPath)
            if($profiles.Count -ne 1){throw 'The original Steam account is unavailable.'}
            $games=@(Get-PreparationRetryGames $activity $script:catalog $profiles[0]);if(-not $games.Count){throw 'No unfinished games are currently installed. Rescan to refresh installations.'}
            $history.Games=$games;$history.Profile=$profiles[0];$history.IncludeArtwork=[bool]$activity.IncludeArtwork;$window.Close()
        }catch{$message.Text=$_.Exception.Message}
    })
    $close.Add_Click({$window.Close()});if($activities.Count){$picker.SelectedIndex=0}
    Set-SteamNiteTheme $window
    try{if($SmokeTest){'Activity history UI construction passed.'}else{[void]$window.ShowDialog($form)}}finally{$window.Dispose()}
    if($history.Games.Count){Show-SteamPreparationDialog -Games $history.Games -PreferredProfile $history.Profile -IncludeArtwork $history.IncludeArtwork}
}
