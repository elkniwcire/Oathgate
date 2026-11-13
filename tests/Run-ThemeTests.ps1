$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot '..\src\Theme.ps1')
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw "FAIL: $Message"};$script:passed++;"PASS: $Message"}
$form=New-Object Windows.Forms.Form
try{
    $apply=New-Object SteamNite.ActionButton;$apply.Text='Apply recommended';$apply.Tag='game-id'
    $remove=New-Object SteamNite.ActionButton;$remove.Text='Remove checked'
    $password=New-Object Windows.Forms.TextBox;$password.UseSystemPasswordChar=$true
    $list=New-Object Windows.Forms.ListView;$list.View='Details';[void]$list.Columns.Add('Game');[void]$list.Items.Add('Valheim');$list.MultiSelect=$true
    $checked=New-Object Windows.Forms.ListView;$checked.View='Details';$checked.CheckBoxes=$true
    $combo=New-Object SteamNite.ThemeComboBox;[void]$combo.Items.Add('Account');$combo.SelectedIndex=0
    $menu=New-Object Windows.Forms.ContextMenuStrip;[void]$menu.Items.Add('Remove shortcut');$list.ContextMenuStrip=$menu
    $form.Controls.AddRange(@($apply,$remove,$password,$list,$checked,$combo))
    Set-SteamNiteTheme $form
    Set-SteamNiteTheme $form
    Assert ($form.BackColor.ToArgb() -eq [Drawing.ColorTranslator]::FromHtml($themeTokens.background).ToArgb()) 'Dialog background comes from shared design tokens'
    Assert ($apply.Primary -and $remove.Destructive) 'Primary and destructive actions retain distinct roles'
    Assert ($apply.Tag -eq 'game-id') 'Theming preserves action identities'
    Assert ($password.UseSystemPasswordChar) 'Theming preserves masked credential fields'
    Assert ($list.OwnerDraw -and $list.MultiSelect -and $list.Items[0].Text -eq 'Valheim') 'Styled lists preserve data and multiple selection'
    Assert ($checked.CheckBoxes -and -not $checked.OwnerDraw) 'Checkbox lists preserve native check behavior'
    Assert ($combo.SelectedIndex -eq 0 -and $combo.DrawMode -eq 'OwnerDrawFixed') 'Styled dropdowns preserve selection'
    Assert ($menu.Items[0].ForeColor.ToArgb() -eq [SteamNite.DialogTheme]::Danger.ToArgb()) 'Context menus distinguish removal actions'
    $new=New-Object Windows.Forms.TextBox;$form.Controls.Add($new)
    Assert ($new.BackColor.ToArgb() -eq [SteamNite.DialogTheme]::Input.ToArgb()) 'Dynamically added controls inherit the shared theme'
    Assert (([SteamNite.DialogTheme]::Semantic([Drawing.Color]::FromArgb(30,125,70))).ToArgb() -eq [SteamNite.DialogTheme]::Success.ToArgb()) 'Status colors are translated for dark surfaces'
    $bitmap=New-Object Drawing.Bitmap 160,44;$apply.Size=New-Object Drawing.Size 160,44
    try{$apply.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle 0,0,160,44));Assert ($bitmap.GetPixel(80,5).ToArgb() -eq [SteamNite.DialogTheme]::Accent.ToArgb()) 'Primary buttons render the shared accent'}finally{$bitmap.Dispose()}
    $confirmation=[SteamNite.DialogTheme]::CreateMessageBox('Close Steam and continue?','Close Steam?','YesNo','Question')
    try{
        Assert ($confirmation.AcceptButton.DialogResult -eq 'No' -and $confirmation.CancelButton.DialogResult -eq 'No') 'Themed Steam-close confirmations default Enter and Escape to No'
        Assert ($confirmation.BackColor.ToArgb() -eq [SteamNite.DialogTheme]::Background.ToArgb()) 'Confirmation dialogs use the shared palette'
    }finally{$confirmation.Dispose()}
    "All $script:passed theme checks passed."
}finally{$form.Dispose();$menu.Dispose()}
