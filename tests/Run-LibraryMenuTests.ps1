$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot '..\src\Library.Menu.ps1')
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
$list=New-Object Windows.Forms.ListView;$list.View='Details';$list.MultiSelect=$true;$list.Size=New-Object Drawing.Size(500,300)
[void]$list.Columns.Add('Game',300)
foreach($title in @('One','Two','Three')){[void]$list.Items.Add($title)}
$menu=New-Object Windows.Forms.ContextMenuStrip;[void]$menu.Items.Add('Fixture action')
$state=@{Refreshes=0}
try{
    [void]$list.Handle
    Initialize-GameContextMenu $list $menu {$state.Refreshes++}.GetNewClosure()
    $list.Items[0].Selected=$true;$list.Items[1].Selected=$true
    $point=New-Object Drawing.Point(20,($list.Items[1].Bounds.Top+5))
    $eventArgs=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Right,1,$point.X,$point.Y,0)
    $mouse=[Windows.Forms.Control].GetMethod('OnMouseDown',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$mouse.Invoke($list,@($eventArgs.PSObject.BaseObject))
    Assert ($list.SelectedItems.Count -eq 2 -and $list.Items[0].Selected -and $list.Items[1].Selected) 'Right-clicking inside a selection preserves all selected games'
    $point=New-Object Drawing.Point(20,($list.Items[2].Bounds.Top+5))
    $eventArgs=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Right,1,$point.X,$point.Y,0)
    [void]$mouse.Invoke($list,@($eventArgs.PSObject.BaseObject))
    Assert ($list.SelectedItems.Count -eq 1 -and $list.Items[2].Selected) 'Right-clicking another game selects only that game'
    Assert ($list.Items[2].Focused) 'The clicked game receives keyboard focus'
    $opening=[Windows.Forms.ToolStripDropDown].GetMethod('OnOpening',[Reflection.BindingFlags]'Instance,NonPublic')
    $cancel=New-Object ComponentModel.CancelEventArgs
    [void]$opening.Invoke($menu,@($cancel.PSObject.BaseObject))
    Assert (-not $cancel.Cancel -and $state.Refreshes -eq 1) 'Opening the context menu refreshes action eligibility'
    $list.Items[0].Selected=$true
    $before=$list.SelectedItems.Count;$cancel=New-Object ComponentModel.CancelEventArgs
    [void]$opening.Invoke($menu,@($cancel.PSObject.BaseObject))
    Assert (-not $cancel.Cancel -and $list.SelectedItems.Count -eq $before) 'Keyboard menu opening keeps the current multi-selection'
    $eventArgs=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Right,1,20,250,0)
    [void]$mouse.Invoke($list,@($eventArgs.PSObject.BaseObject))
    Assert ($list.SelectedItems.Count -eq 0) 'Right-clicking empty space clears stale game targets'
    $cancel=New-Object ComponentModel.CancelEventArgs;[void]$opening.Invoke($menu,@($cancel.PSObject.BaseObject))
    Assert ($cancel.Cancel) 'Empty-space menus cannot act on a previously selected game'
    $list.Items[1].Selected=$true
    $eventArgs=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Left,1,20,250,0)
    [void]$mouse.Invoke($list,@($eventArgs.PSObject.BaseObject))
    Assert ($list.Items[1].Selected) 'The helper leaves ordinary left-click handling to Windows'
    "`nAll $script:passed library menu checks passed. No game or Steam actions were invoked."
}finally{$menu.Dispose();$list.Dispose()}
