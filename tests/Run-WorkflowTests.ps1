$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Workflow.psm1') -Force
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Throws($Action){try{& $Action;return $false}catch{return $true}}
$root=Join-Path $PSScriptRoot ('.tmp\workflow-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root);$file=Join-Path $root 'request.json'
function Request($Action,[string[]]$Ids=@()){
    @{Action=$Action;GameIds=$Ids;ProfileShortcutPath='C:\Steam\userdata\fixture\config\shortcuts.vdf'}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $file -Encoding UTF8
    Read-WorkflowRequest $file
}
try{
    $first=[pscustomobject]@{Id='gog:first';Title='First';NativeGameId='gog:first';InstallState='Installed';Status='Ready to test';Ignored=$false;CanRemove=$false}
    $second=$first.PSObject.Copy();$second.Id='ubisoft:second';$second.NativeGameId='ubisoft:second'
    $manual=[pscustomobject]@{Id='steam:manual';NativeGameId='';InstallState='Manual shortcut';Status='Manual shortcut';Ignored=$false;CanRemove=$false}
    $removed=[pscustomobject]@{Id='steam:removed';NativeGameId='ea:removed';InstallState='Not installed';Status='Not installed';Ignored=$false;CanRemove=$true}
    $library=@($first,$second,$manual,$removed)
    $request=Request 'Prepare' @($first.Id,$second.Id,$first.Id)
    Assert ($request.GameIds.Count -eq 2) 'The action request contains explicit unique selected identities'
    $selected=@(Resolve-WorkflowSelection $request $library)
    Assert ($selected.Count -eq 2 -and $manual.Id -notin $selected.Id) 'Preparation resolves exactly the selected games, not the whole library'
    Assert (Throws {Resolve-WorkflowSelection $request @($first)}) 'A missing selected game invalidates the entire request'
    Assert (Throws {Resolve-WorkflowSelection $request @($first,$first,$second)}) 'Ambiguous current identities cannot be silently chosen'
    Assert (Throws {Resolve-WorkflowSelection (Request 'Prepare' @($removed.Id)) $library}) 'Uninstalled shortcuts cannot enter preparation'
    Assert (Throws {Resolve-WorkflowSelection (Request 'Launch' @($first.Id,$second.Id)) $library}) 'Launching requires a single selected game'
    Assert (@(Resolve-WorkflowSelection (Request 'Launch' @($first.Id)) $library).Count -eq 1) 'A current launchable installed game resolves successfully'
    $unresolved=$first.PSObject.Copy();$unresolved.Status='Unresolved'
    Assert (Throws {Resolve-WorkflowSelection (Request 'Launch' @($first.Id)) @($unresolved)}) 'Unresolved launch recipes are rejected at the action boundary'
    $ignored=$first.PSObject.Copy();$ignored.Ignored=$true
    Assert (Throws {Resolve-WorkflowSelection (Request 'Artwork' @($first.Id)) @($ignored)}) 'Ignored games cannot bypass artwork exclusion through the bridge'
    Assert (Throws {Resolve-WorkflowSelection (Request 'EditLaunch' @($first.Id,$second.Id)) $library}) 'Launch editing cannot silently use the first game in a multi-selection'
    Assert (Throws {Resolve-WorkflowSelection (Request 'Ignore' @($manual.Id)) $library}) 'Manual Steam-only entries cannot be adopted accidentally by exclusions'
    Assert (@(Resolve-WorkflowSelection (Request 'Remove' @($removed.Id)) $library).Count -eq 1) 'Verified managed uninstall candidates can proceed to named confirmation'
    Assert (Throws {Resolve-WorkflowSelection (Request 'Remove' @($removed.Id,$manual.Id)) $library}) 'A mixed removal selection cannot include protected manual shortcuts'
    Assert (Throws {Request 'AllArtwork' @($first.Id)}) 'Whole-library actions cannot disguise themselves as selection-scoped actions'
    Assert ((Request 'History').GameIds.Count -eq 0) 'Global history actions do not require a selected game'
    Assert (Throws {Request 'Prepare'}) 'Selection actions cannot fall back to all games when no IDs are supplied'
    Assert (Throws {Request 'ArbitraryCommand' @($first.Id)}) 'Only explicitly supported workflow actions are accepted'
    @{Action='Launch';GameIds=@($first.Id);Executable='C:\Arbitrary.exe'}|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
    Assert (Throws {Read-WorkflowRequest $file}) 'The bridge rejects executable recipes and other unsupported request fields'
    "`nAll $script:passed workflow boundary checks passed. No workflows or personal records changed."
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
