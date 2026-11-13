$ErrorActionPreference='Stop'
function Read-WorkflowRequest([string]$Path) {
    if((Get-Item -LiteralPath $Path).Length -gt 1MB){throw 'Workflow request is too large.'}
    $request=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    $allowed=@('Prepare','Launch','Artwork','Shortcuts','EditLaunch','Ignore','Unignore','Remove','ManageFolders','Settings','History','AllArtwork')
    if($request.Action -notin $allowed){throw 'Unsupported workflow action.'}
    if(@($request.PSObject.Properties|Where-Object {$_.Name -notin @('Action','GameIds','ProfileShortcutPath')}).Count){throw 'Unsupported workflow request fields.'}
    $ids=@($request.GameIds|Where-Object {$_})
    if($ids.Count -gt 500 -or @($ids|Where-Object {$_ -isnot [string] -or $_.Length -gt 1024}).Count){throw 'Invalid workflow game selection.'}
    $global=$request.Action -in @('ManageFolders','Settings','History','AllArtwork')
    if(($global -and $ids.Count) -or (-not $global -and -not $ids.Count)){throw 'The action requires an explicit, correctly scoped selection.'}
    [pscustomobject]@{Action=[string]$request.Action;GameIds=@($ids|Select-Object -Unique);ProfileShortcutPath=[string]$request.ProfileShortcutPath}
}
function Resolve-WorkflowSelection {
    param($Request,[object[]]$Library)
    $games=@(foreach($id in $Request.GameIds){
        $matches=@($Library|Where-Object Id -eq $id)
        if($matches.Count -ne 1){throw 'A selected game changed or is no longer available. Rescan and review the selection again.'}
        $matches[0]
    })
    if($Request.Action -in @('Prepare','Launch','Artwork','Shortcuts','EditLaunch')){
        if(@($games|Where-Object InstallState -ne 'Installed').Count){throw 'This action requires installed games.'}
    }
    if($Request.Action -in @('Launch','Artwork','EditLaunch') -and $games.Count -ne 1){throw 'This action requires exactly one selected game.'}
    if($Request.Action -eq 'Launch' -and $games[0].Status -ne 'Ready to test'){throw 'The selected game does not have a usable launch configuration.'}
    if($Request.Action -eq 'Artwork' -and $games[0].Ignored){throw 'Unignore this game before changing its artwork.'}
    if($Request.Action -in @('Ignore','Unignore') -and @($games|Where-Object {-not $_.NativeGameId}).Count){throw 'Only detected or SteamNite-managed games support exclusions.'}
    if($Request.Action -eq 'Remove' -and @($games|Where-Object {-not $_.CanRemove -or $_.Ignored}).Count){throw 'Only verified, uninstalled SteamNite shortcuts may be removed.'}
    if($Request.Action -eq 'ExplicitRemove' -and @($games|Where-Object {-not $_.CanRemoveExplicitly -or $_.Ignored}).Count){throw 'Each selected game must have one current Steam shortcut and must not be ignored.'}
    return $games
}
Export-ModuleMember -Function Read-WorkflowRequest, Resolve-WorkflowSelection
