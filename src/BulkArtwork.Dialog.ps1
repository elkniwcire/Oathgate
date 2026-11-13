function Show-BulkArtworkDialog {
    param([object[]]$Games,$PreferredProfile=$null,[switch]$SmokeTest)
    $profiles=@(Get-SteamProfiles)
    if (-not $profiles.Count -and -not $SmokeTest) { throw 'No Steam profiles found.' }
    $window=New-Object Windows.Forms.Form
    $window.Text='Recommended artwork for '+$Games.Count+' games';$window.Size=New-Object Drawing.Size(1030,700)
    $window.MinimumSize=New-Object Drawing.Size(900,580);$window.Font=$form.Font;$window.StartPosition='CenterParent'
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(16);$panel.ColumnCount=1;$panel.RowCount=6
    foreach($height in @(55,40,40)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    [void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
    foreach($height in @(65,45)){[void]$panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
    $window.Controls.Add($panel)
    $intro=New-Object Windows.Forms.Label;$intro.Dock='Fill'
    $intro.Text='Fill missing covers, wide images, heroes, logos and icons for the listed games already synced to this Steam account. Existing artwork stays intact. Saved matches or unique exact titles are used; uncertain matches are skipped.'
    $panel.Controls.Add($intro,0,0)
    $profile=New-Object SteamNite.ThemeComboBox;$profile.Dock='Fill';$profile.DropDownStyle='DropDownList';$profile.AccessibleName='Batch artwork Steam profile'
    foreach($p in $profiles){[void]$profile.Items.Add($p.Label)};if($profiles.Count -eq 1){$profile.SelectedIndex=0};$panel.Controls.Add($profile,0,1)
    if($PreferredProfile){for($i=0;$i -lt $profiles.Count;$i++){if($profiles[$i].ShortcutPath -eq $PreferredProfile.ShortcutPath){$profile.SelectedIndex=$i;break}}}
    $credentials=New-Object Windows.Forms.FlowLayoutPanel;$credentials.Dock='Fill';$panel.Controls.Add($credentials,0,2)
    $label=New-Object Windows.Forms.Label;$label.Text='SteamGridDB key:';$label.AutoSize=$true;$credentials.Controls.Add($label)
    $key=New-Object Windows.Forms.TextBox;$key.UseSystemPasswordChar=$true;$key.Width=300;$key.AccessibleName='Batch SteamGridDB API key';$credentials.Controls.Add($key)
    $remember=New-Object Windows.Forms.CheckBox;$remember.Text='Remember key';$remember.AutoSize=$true;$credentials.Controls.Add($remember)
    try{$saved=Get-ArtworkApiKey $script:dataDir;if($saved){$key.Text=$saved;$remember.Checked=$true};$saved=$null}catch{}
    $rows=New-Object Windows.Forms.ListView;$rows.Dock='Fill';$rows.View='Details';$rows.FullRowSelect=$true
    foreach($c in @(@('Game',250),@('Result',120),@('Details',575))){[void]$rows.Columns.Add($c[0],$c[1])}
    foreach($game in $Games){$item=New-Object Windows.Forms.ListViewItem($game.Title);[void]$item.SubItems.Add('Pending');[void]$item.SubItems.Add('');$item.Tag=$game;[void]$rows.Items.Add($item)}
    $panel.Controls.Add($rows,0,3)
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$message.Text='Apply will offer to close Steam if needed. Games are processed one at a time; you can stop after the current game.';$panel.Controls.Add($message,0,4)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$panel.Controls.Add($buttons,0,5)
    $start=Add-Button 'Apply recommended to all' $buttons 240
    $stop=Add-Button 'Stop after current' $buttons 170;$stop.Enabled=$false
    $close=Add-Button 'Close' $buttons 100
    $openSteam=Add-Button 'Open Steam' $buttons 120
    $batch=@{Worker=$null;Handle=$null;Index=0;Stopped=$false;Running=$false;Added=0;Results=(New-Object 'System.Collections.Generic.List[object]');Profile=$null;Key=''}
    function Finish-ArtworkBatch {
        $batch.Running=$false;$stop.Enabled=$false;$close.Enabled=$true;$openSteam.Enabled=$true;$batch.Key=''
        $message.Text=('{0} {1}/{2} games processed; {3} images added. Reopen Steam to load artwork. See per-game results above.' -f $(if($batch.Stopped){'Stopped.'}else{'Finished.'}),$batch.Index,$Games.Count,$batch.Added)
        [void](New-Item -ItemType Directory -Path $script:dataDir -Force)
        @{FinishedAt=(Get-Date).ToString('o');Stopped=$batch.Stopped;Results=$batch.Results.ToArray()} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:dataDir 'last-artwork-batch.json') -Encoding UTF8
    }
    function Start-NextArtworkGame {
        if($batch.Stopped -or $batch.Index -ge $Games.Count){Finish-ArtworkBatch;return}
        $game=$Games[$batch.Index];$rows.Items[$batch.Index].SubItems[1].Text='Working'
        $rows.Items[$batch.Index].EnsureVisible();$message.Text=('Processing {0}/{1}: {2}...' -f ($batch.Index+1),$Games.Count,$game.Title)
        $batch.Worker=[PowerShell]::Create()
        [void]$batch.Worker.AddScript({param($module,$game,$profile,$data,$key) $ErrorActionPreference='Stop';Import-Module $module -Force;Invoke-BulkArtworkGame $game $profile $data $key}).AddArgument((Join-Path $PSScriptRoot 'SteamNite.BulkArtwork.psm1')).AddArgument($game).AddArgument($batch.Profile).AddArgument($script:dataDir).AddArgument($batch.Key)
        $batch.Handle=$batch.Worker.BeginInvoke()
    }
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=200
    $timer.Add_Tick({
        if(-not $batch.Handle -or -not $batch.Handle.IsCompleted){return}
        try{
            $output=@($batch.Worker.EndInvoke($batch.Handle))
            if($batch.Worker.HadErrors -or -not $output.Count){throw 'Batch worker failed; no further games will be processed.'}
            $result=$output[-1];$batch.Results.Add($result);$batch.Added+=$result.Added
            $rows.Items[$batch.Index].SubItems[1].Text=$result.Status;$rows.Items[$batch.Index].SubItems[2].Text=$result.Detail
            if($result.StopBatch){$batch.Stopped=$true}
        }catch{$rows.Items[$batch.Index].SubItems[1].Text='Failed';$rows.Items[$batch.Index].SubItems[2].Text=$_.Exception.Message;$batch.Stopped=$true}
        finally{$batch.Worker.Dispose();$batch.Worker=$null;$batch.Handle=$null;$batch.Index++}
        Start-NextArtworkGame
    })
    $start.Add_Click({
        try{
            if($profile.SelectedIndex -lt 0){throw 'Choose a Steam account.'}
            Remember-SteamAccount $profiles[$profile.SelectedIndex]
            if([string]::IsNullOrWhiteSpace($key.Text)){throw 'Enter your SteamGridDB API key.'}
            if(-not (Confirm-SteamClosed -Owner $window -Profile $profiles[$profile.SelectedIndex] -Action 'apply recommended artwork to these games')){$message.Text='Cancelled. No artwork was changed.';return}
            if($remember.Checked){Set-ArtworkApiKey $script:dataDir $key.Text}
            $batch.Profile=$profiles[$profile.SelectedIndex];$batch.Key=$key.Text.Trim();$batch.Running=$true
            $start.Enabled=$false;$profile.Enabled=$false;$key.Enabled=$false;$remember.Enabled=$false;$stop.Enabled=$true;$openSteam.Enabled=$false
            Start-NextArtworkGame
        }catch{$message.Text=$_.Exception.GetBaseException().Message}
    })
    $stop.Add_Click({$batch.Stopped=$true;$stop.Enabled=$false;$message.Text='Stopping after the current game finishes safely...'})
    $close.Add_Click({$window.Close()})
    $openSteam.Add_Click({try{if($profile.SelectedIndex -lt 0){throw 'Choose a Steam account.'};Open-SteamClient $profiles[$profile.SelectedIndex]}catch{$message.Text=$_.Exception.Message}})
    $window.Add_FormClosing({param($sender,$eventArgs) if($batch.Running){$eventArgs.Cancel=$true;$batch.Stopped=$true;$stop.Enabled=$false;$message.Text='Stopping after the current game; close again when it finishes.'}})
    $timer.Start()
    Set-SteamNiteTheme $window
    try{if($SmokeTest){'Bulk artwork UI construction passed.'}else{[void]$window.ShowDialog($form)}}
    finally{$timer.Stop();$timer.Dispose();$key.Clear();$batch.Key='';$window.Dispose()}
}
