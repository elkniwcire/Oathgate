function Invoke-ClassicWorkflow([string]$RequestPath) {
    # Give hidden-owner dialogs a real desktop-centered parent rectangle.
    $area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.StartPosition='Manual'
    $form.Location=New-Object Drawing.Point(($area.Left+[Math]::Max(0,($area.Width-$form.Width)/2)),($area.Top+[Math]::Max(0,($area.Height-$form.Height)/2)))
    Import-Module (Join-Path $PSScriptRoot 'SteamNite.Workflow.psm1') -Force
    $request=Read-WorkflowRequest $RequestPath
    $profiles=@(Get-SteamProfiles);$profile=$null
    if($request.ProfileShortcutPath){
        $found=@($profiles|Where-Object ShortcutPath -eq $request.ProfileShortcutPath)
        if($found.Count -ne 1){throw 'The chosen Steam account is unavailable. Review account settings before continuing.'}
        $profile=$found[0]
    }elseif($profiles.Count -eq 1){$profile=$profiles[0]}
    if($profile){$script:libraryProfile=$profile}
    $scan=Get-GameScan -ExtraRoots $script:extraRoots
    $script:catalog=@($scan.Games);$script:diagnostics=@($scan.Diagnostics)
    # Fresh evidence and current overrides, never executable recipes from the UI.
    $history=Join-Path $script:dataDir 'install-history.json'
    $plan=if($profile){New-SteamRemovalPlan $profile $history}else{$null}
    $library=@(Get-UnifiedGameLibrary $script:catalog $profile $plan $history)
    $games=@(Resolve-WorkflowSelection $request $library)
    Update-GameInstallHistory $history $script:catalog
    switch($request.Action){
        'Prepare'{Show-SteamPreparationDialog -Games $games -PreferredProfile $profile}
        'Launch'{Start-DetectedGame $games[0]}
        'Artwork'{Show-ArtworkDialog -Game $games[0] -PreferredProfile $profile}
        'Shortcuts'{Show-SteamSyncDialog -Games $games}
        'EditLaunch'{Show-LaunchOverrideDialog $games[0]}
        'Ignore'{Set-GameIgnored -GameIds @($games|ForEach-Object NativeGameId) -Ignored $true}
        'Unignore'{Set-GameIgnored -GameIds @($games|ForEach-Object NativeGameId) -Ignored $false}
        'Remove'{
            if(-not $plan){throw 'Choose a Steam account before reviewing removal.'}
            $selected=@($games|ForEach-Object {[pscustomobject]@{Title=$_.Title;AppId=$_.SteamAppId;GameId=$_.NativeGameId}})
            [void](Remove-ReviewedSteamShortcuts -Owner $form -Plan $plan -Selected $selected)
        }
        'ManageFolders'{
            $result=Show-ScanFoldersDialog -Folders $script:extraRoots
            if($result.Saved){Save-AppSettings $script:settingsFile @{ExtraRoots=@($result.Folders)}}
        }
        'Settings'{
            $chosen=Show-SteamAccountSettings -Profiles $profiles -SelectedPath $(if($profile){$profile.ShortcutPath}else{$script:preferredSteamPath})
            if($chosen){Save-AppSettings $script:settingsFile @{SteamShortcutPath=$chosen}}
        }
        'History'{Show-PreparationHistoryDialog}
        'AllArtwork'{Show-BulkArtworkDialog -Games @($script:catalog|Where-Object {$_.Id -notin @(Get-IgnoredGameIds)}) -PreferredProfile $profile}
    }
}
