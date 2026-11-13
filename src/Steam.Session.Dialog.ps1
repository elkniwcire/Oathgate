function Get-SteamCloseDecision {
    param($Owner,[string]$Action)
    $answer=[SteamNite.DialogTheme]::ShowMessageBox($Owner,
        "Steam needs to close before SteamNite can $Action. Save any game progress first.`r`n`r`nClose Steam and continue? Steam will remain closed while you finish your changes.",
        'Close Steam to continue?',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
    return $answer -eq [Windows.Forms.DialogResult]::Yes
}
function Wait-SteamClosed {
    param($Owner,[int]$TimeoutSeconds=45)
    $wait=New-Object Windows.Forms.Form;$wait.Text='Waiting for Steam to close'
    $wait.Size=New-Object Drawing.Size(470,180);$wait.FormBorderStyle='FixedDialog';$wait.MaximizeBox=$false;$wait.MinimizeBox=$false;$wait.StartPosition='CenterParent';$wait.Font=$Owner.Font
    $message=New-Object Windows.Forms.Label;$message.Text='Steam is closing... If it asks about running games, respond in Steam. You can cancel waiting.';$message.Dock='Top';$message.Height=65;$message.Padding=New-Object Windows.Forms.Padding(12);$wait.Controls.Add($message)
    $cancel=New-Object SteamNite.ActionButton;$cancel.Text='Cancel';$cancel.Dock='Bottom';$cancel.Height=35;$wait.Controls.Add($cancel)
    $state=@{Closed=$false;TimedOut=$false;ClosedSince=$null};$deadline=[datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $poll=New-Object Windows.Forms.Timer;$poll.Interval=250
    $poll.Add_Tick({
        if(-not (Test-SteamRunning)){
            if($null -eq $state.ClosedSince){$state.ClosedSince=[datetime]::UtcNow}
            if(([datetime]::UtcNow-$state.ClosedSince).TotalMilliseconds -ge 500){$state.Closed=$true;$wait.Close()}
        }else{$state.ClosedSince=$null}
        if([datetime]::UtcNow -ge $deadline -and -not $state.Closed){$state.TimedOut=$true;$wait.Close()}
    })
    $cancel.Add_Click({$wait.Close()});$poll.Start()
    Set-SteamNiteTheme $wait
    try{[void]$wait.ShowDialog($Owner)}finally{$poll.Stop();$poll.Dispose();$wait.Dispose()}
    if($state.TimedOut){throw 'Steam has not exited yet. No changes were applied. Finish closing Steam, then try the action again.'}
    return $state.Closed
}
function Confirm-SteamClosed {
    param($Owner,$Profile,[string]$Action='apply these changes',[int]$TimeoutSeconds=45)
    if(-not (Test-SteamRunning)){return $true}
    if(-not (Get-SteamCloseDecision -Owner $Owner -Action $Action)){return $false}
    # Request the client's normal exit. Never force-kill Steam or its games.
    Request-SteamShutdown $Profile
    return Wait-SteamClosed -Owner $Owner -TimeoutSeconds $TimeoutSeconds
}
