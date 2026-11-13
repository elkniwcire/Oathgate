$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '..\src\Removal.Dialog.ps1')
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
$list=New-Object Windows.Forms.ListView;$list.CheckBoxes=$true
$button=New-Object Windows.Forms.Button;$button.Enabled=$false
$context=@{Worker=$null}
try{
    foreach($status in @('Removal candidate','Keep','Removal candidate','Cannot verify','')){
        $item=New-Object Windows.Forms.ListViewItem($status)
        if($status){$item.Tag=[pscustomobject]@{Status=$status}}
        [void]$list.Items.Add($item)
    }
    # Create the actual native control and invoke the production ItemCheck delegate.
    # No application window is shown, and no removal callback or Steam writer is used.
    [void]$list.Handle
    Initialize-RemovalSelection -Rows $list -RemoveButton $button -Context $context
    $list.Items[0].Checked=$true
    Assert ($list.Items[0].Checked -and $button.Enabled) 'Checking a removal candidate raises the real event without an exception and enables removal'
    $list.Items[0].Checked=$false
    Assert (-not $button.Enabled) 'Unchecking the last candidate disables removal'
    $list.Items[1].Checked=$true
    Assert (-not $list.Items[1].Checked -and -not $button.Enabled) 'Manually added shortcuts cannot be checked'
    $list.Items[0].Checked=$true;$list.Items[1].Checked=$true
    Assert ($list.CheckedItems.Count -eq 1 -and $button.Enabled) 'Clicking a protected entry does not disable an already selected candidate'
    $list.Items[2].Checked=$true
    Assert ($list.CheckedItems.Count -eq 2 -and $button.Enabled) 'Multiple eligible candidates can be checked'
    $list.Items[0].Checked=$false
    Assert ($list.CheckedItems.Count -eq 1 -and $button.Enabled) 'Unchecking one candidate preserves the other selection'
    $list.Items[3].Checked=$true
    Assert (-not $list.Items[3].Checked -and $button.Enabled) 'Unverifiable entries remain unselectable'
    $list.Items[4].Checked=$true
    Assert (-not $list.Items[4].Checked -and $button.Enabled) 'Missing row metadata cannot crash checkbox handling'
    $context.Worker=[pscustomobject]@{Busy=$true};$list.Items[0].Checked=$true
    Assert (-not $list.Items[0].Checked -and -not $button.Enabled) 'A pending preview prevents new removal selections'
    $context.Worker=$null;$list.Items[0].Checked=$true
    Assert ($list.Items[0].Checked -and $button.Enabled) 'The event closure observes updated preview state'
    $list.Items[0].Checked=$false;$list.Items[2].Checked=$false
    Assert ($list.CheckedItems.Count -eq 0 -and -not $button.Enabled) 'Clearing all selections leaves removal disabled'
    "`nAll $script:passed checkbox interaction checks passed. No shortcuts were removed."
}finally{$list.Dispose();$button.Dispose()}
