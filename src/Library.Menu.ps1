function Set-GameContextSelection {
    param($List,[Drawing.Point]$Location)
    $hit=$List.GetItemAt($Location.X,$Location.Y)
    if(-not $hit){$List.SelectedItems.Clear();return}
    if(-not $hit.Selected){$List.SelectedItems.Clear();$hit.Selected=$true}
    $hit.Focused=$true
}
function Initialize-GameContextMenu {
    param($List,$Menu,[scriptblock]$Refresh)
    $mouseHandler={
        param($sender,$eventArgs)
        if($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Right){Set-GameContextSelection $List $eventArgs.Location}
    }.GetNewClosure()
    $openingHandler={
        param($sender,$eventArgs)
        & $Refresh
        if(-not $List.SelectedItems.Count){$eventArgs.Cancel=$true}
    }.GetNewClosure()
    $List.ContextMenuStrip=$Menu
    $List.Add_MouseDown($mouseHandler)
    $Menu.Add_Opening($openingHandler)
}
