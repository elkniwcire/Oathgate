$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Steam.psm1') -Force
$script:passed=0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:passed++; Write-Output ('PASS: ' + $Message)
}
function Throws($Action) { try { & $Action; return $false } catch { return $true } }
$root=Join-Path $PSScriptRoot ('.tmp\steam-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root -Force)
$module=Get-Module SteamNite.Steam
# Control process detection only inside this test process; never manipulate the real Steam client.
& $module { function script:Test-SteamRunning { return $false } }
try {
    $empty=[SteamNite.SteamShortcuts]::new([byte[]]$null)
    Assert ($empty.Items.Count -eq 0) 'A missing shortcut file initializes a valid empty document'
    Assert ([SteamNite.SteamShortcuts]::AppId('1234','56789') -eq [uint32]3421780262) 'Shortcut ID matches the standard CRC32 test vector'
    $d=New-Object SteamNite.ShortcutDraft
    $d.Title='Manual Unicode '+[char]0x00e9; $d.Exe='"C:\Games\manual.exe"'; $d.StartDir='"C:\Games"'; $d.LaunchOptions='--custom-option'; $d.ManagedId=''
    $d.AppId=[SteamNite.SteamShortcuts]::AppId($d.Exe,$d.Title)
    [byte[]]$original=$empty.Append([SteamNite.ShortcutDraft[]]@($d))
    $parsed=[SteamNite.SteamShortcuts]::new($original)
    Assert ($parsed.Items[0].Title -eq $d.Title -and $parsed.Items[0].LaunchOptions -eq '--custom-option') 'Binary VDF round-trip preserves Unicode and custom launch options'
    $caseBytes=[byte[]]$original.Clone()
    $key=[Text.Encoding]::ASCII.GetBytes('AppName')
    for($i=0;$i -le $caseBytes.Length-$key.Length;$i++) {
        $match=$true
        for($j=0;$j -lt $key.Length;$j++) { if($caseBytes[$i+$j] -ne $key[$j]) { $match=$false;break } }
        if($match) { [Array]::Copy([Text.Encoding]::ASCII.GetBytes('appname'),0,$caseBytes,$i,$key.Length);break }
    }
    Assert (([SteamNite.SteamShortcuts]::new($caseBytes)).Items[0].Title -eq $d.Title) 'Field names are read without casing assumptions'
    Assert (Throws { [void][SteamNite.SteamShortcuts]::new([byte[]]@(0,115,0,8,8)) }) 'Malformed roots are rejected'
    Assert (Throws { [void][SteamNite.SteamShortcuts]::new($original[0..($original.Length-3)]) }) 'Truncated files are rejected'
    $bad=[byte[]]$original.Clone(); $bad[14]=99
    Assert (Throws { [void][SteamNite.SteamShortcuts]::new($bad) }) 'Unknown field types are rejected rather than discarded'
    Assert (Throws { [void]$parsed.Append([SteamNite.ShortcutDraft[]]@($d)) }) 'Duplicate shortcut IDs cannot be appended'
    $profile=[pscustomobject]@{ShortcutPath=(Join-Path $root 'shortcuts.vdf');AccountId='fixture';SteamRoot=$root}
    [System.IO.File]::WriteAllBytes($profile.ShortcutPath,$original)
    $helper=Join-Path $root 'gamelaunchhelper.exe'; [System.IO.File]::WriteAllBytes($helper,[byte[]]@())
    $game=[pscustomobject]@{Id='xbox:Fixture.Game';Title='Fixture Game';Status='Ready to test';Method='Xbox launch helper';Target=$helper;InstallPath=$root}
    $beforeHash=(Get-FileHash -LiteralPath $profile.ShortcutPath).Hash
    $plan=New-SteamSyncPlan $profile @($game)
    Assert ($plan.ExistingCount -eq 1 -and $plan.AddCount -eq 1) 'Preview adds only the selected game'
    $preserved=$true
    for($i=0;$i -lt $original.Length-2;$i++) { if ($original[$i] -ne $plan.OutputBytes[$i]) { $preserved=$false;break } }
    Assert $preserved 'Existing shortcut bytes are preserved exactly, including custom fields'
    Assert ((Get-FileHash -LiteralPath $profile.ShortcutPath).Hash -eq $beforeHash) 'Preview leaves the original file unchanged'
    & $module { function script:Test-SteamRunning { return $true } }
    Assert (Throws { Save-SteamSyncPlan $plan }) 'A running Steam client blocks writes'
    Assert ((Get-ShortcutSnapshot $profile.ShortcutPath).Hash -eq $plan.OriginalHash) 'Blocked sync leaves Steam data intact'
    & $module { function script:Test-SteamRunning { return $false } }
    $result=Save-SteamSyncPlan $plan
    Assert ($result.Added -eq 1 -and (Test-Path -LiteralPath $result.BackupPath)) 'Apply creates a backup and adds the selected shortcut'
    $backup=[System.IO.File]::ReadAllBytes($result.BackupPath)
    Assert ([Convert]::ToBase64String($backup) -eq [Convert]::ToBase64String($original)) 'Backup is an exact copy of the previous shortcut file'
    $after=(Get-ShortcutSnapshot $profile.ShortcutPath).File
    Assert ($after.Items.Count -eq 2 -and $after.Items[0].Title -eq $d.Title) 'Apply preserves the existing manual shortcut'
    Assert ($after.Items[1].Exe -eq ('"'+$helper+'"') -and $after.Items[1].StartDir -eq ('"'+$root+'"')) 'Steam shortcut uses the tested helper and working directory'
    Assert (Throws { Save-SteamSyncPlan $plan }) 'A stale preview cannot overwrite newer shortcuts'
    $again=New-SteamSyncPlan $profile @($game)
    Assert ($again.AddCount -eq 0 -and $again.Rows[0].Action -eq 'Keep existing') 'Repeating sync does not duplicate a game'
    $sameTitle=$game.PSObject.Copy(); $sameTitle.Id='different-game'; $sameTitle.Target=Join-Path $root 'other-helper.exe'
    [System.IO.File]::WriteAllBytes($sameTitle.Target,[byte[]]@())
    Assert ((New-SteamSyncPlan $profile @($sameTitle)).AddCount -eq 0) 'A manual title conflict is preserved rather than overwritten'
    $renamed=$game.PSObject.Copy(); $renamed.Title='Renamed'; $renamed.Id='different-game'
    Assert ((New-SteamSyncPlan $profile @($renamed)).AddCount -eq 0) 'An existing launch target prevents a renamed duplicate'
    Assert ((New-SteamSyncPlan $profile @($game,$game)).Rows.Count -eq 1) 'Repeated selection of the same game is deduplicated'
    $blocked=$game.PSObject.Copy(); $blocked.Status='Unresolved'
    $p=New-SteamSyncPlan $profile @($blocked)
    Assert ($p.AddCount -eq 0 -and $p.Rows[0].Action -eq 'Blocked') 'Unresolved launch recipes cannot be imported'
    $newDir=Join-Path $root 'new'; [void](New-Item -ItemType Directory -Path $newDir)
    $missingProfile=[pscustomobject]@{ShortcutPath=(Join-Path $newDir 'shortcuts.vdf')}
    $newPlan=New-SteamSyncPlan $missingProfile @($game)
    $newResult=Save-SteamSyncPlan $newPlan
    Assert ($newResult.Added -eq 1 -and $newResult.BackupPath -eq '' -and (Test-Path $missingProfile.ShortcutPath)) 'First import creates a missing file without overwriting anything'
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count -eq 0) 'Atomic apply leaves no temporary files'
    $state=@(Get-GameSteamStatuses -Games @($game) -Profile $profile)[0]
    Assert ($state.Status -eq 'Synced' -and $state.AppId -eq $after.Items[1].AppId) 'Sync status recognizes the same shortcut identity used by artwork'
    $renamedState=@(Get-GameSteamStatuses -Games @($renamed) -Profile $profile)[0]
    Assert ($renamedState.Status -eq 'Synced') 'Renamed games can be recognized by their exact launch target'
    $titleConflict=@(Get-GameSteamStatuses -Games @($sameTitle) -Profile $profile)[0]
    Assert ($titleConflict.Status -eq 'Needs attention' -and $titleConflict.Detail -like '*different launch target*') 'A title-only conflict is not incorrectly labeled synced'
    $newGame=$sameTitle.PSObject.Copy();$newGame.Title='New game';$newGame.Id='new:game'
    Assert (@(Get-GameSteamStatuses -Games @($newGame) -Profile $profile)[0].Status -eq 'Not synced') 'A game without a matching shortcut is clearly marked not synced'
    Assert (@(Get-GameSteamStatuses -Games @($game))[0].Status -eq 'No profile') 'No Steam profile is distinguished from an unsynced game'
    Assert (@(Get-GameSteamStatuses -Games @($blocked) -Profile $profile)[0].Status -eq 'Needs attention') 'Unresolved launch recipes have an actionable sync status'
    $corruptDir=Join-Path $root 'corrupt';[void](New-Item -ItemType Directory -Path $corruptDir)
    $corruptProfile=[pscustomobject]@{ShortcutPath=(Join-Path $corruptDir 'shortcuts.vdf')}
    [IO.File]::WriteAllBytes($corruptProfile.ShortcutPath,[byte[]]@(1,2,3))
    Assert (@(Get-GameSteamStatuses -Games @($game) -Profile $corruptProfile)[0].Status -eq 'Unknown') 'Unreadable shortcut data never makes games appear unsynced'
    $duplicate=New-Object SteamNite.ShortcutDraft
    $duplicate.Title='Duplicate fixture';$duplicate.Exe='"'+$helper+'"';$duplicate.StartDir='"'+$root+'"';$duplicate.LaunchOptions='';$duplicate.ManagedId='steamnite:'+$game.Id
    $duplicate.AppId=[SteamNite.SteamShortcuts]::AppId($duplicate.Exe,$duplicate.Title)
    $ambiguousDir=Join-Path $root 'ambiguous';[void](New-Item -ItemType Directory -Path $ambiguousDir)
    $ambiguousProfile=[pscustomobject]@{ShortcutPath=(Join-Path $ambiguousDir 'shortcuts.vdf')}
    [IO.File]::WriteAllBytes($ambiguousProfile.ShortcutPath,$after.Append([SteamNite.ShortcutDraft[]]@($duplicate)))
    Assert (@(Get-GameSteamStatuses -Games @($game) -Profile $ambiguousProfile)[0].Status -eq 'Needs attention') 'Duplicate matching shortcuts are reported instead of silently selecting one'
    [IO.File]::WriteAllBytes((Join-Path $root 'steam.exe'),[byte[]]@())
    $closeCommand=Get-SteamClientCommand $profile -Shutdown
    Assert ($closeCommand.Arguments -eq '-shutdown' -and $closeCommand.WindowStyle -eq 'Hidden' -and $closeCommand.UseShellExecute) 'Steam close requests use graceful shutdown with a hidden command window'
    Assert ((Get-SteamClientCommand $profile).Arguments -eq '') 'Opening Steam does not reuse shutdown arguments'
    Assert (Throws {Get-SteamClientCommand ([pscustomobject]@{SteamRoot=(Join-Path $root 'not-steam')}) -Shutdown}) 'A missing Steam executable cannot dispatch a shutdown command'
    $beforeExit=New-SteamSyncPlan $profile @($newGame)
    $external=New-Object SteamNite.ShortcutDraft
    $external.Title='Saved by Steam on exit';$external.Exe='"C:\External\game.exe"';$external.StartDir='"C:\External"';$external.LaunchOptions='';$external.ManagedId=''
    $external.AppId=[SteamNite.SteamShortcuts]::AppId($external.Exe,$external.Title)
    [IO.File]::WriteAllBytes($profile.ShortcutPath,(Get-ShortcutSnapshot $profile.ShortcutPath).File.Append([SteamNite.ShortcutDraft[]]@($external)))
    $afterExit=New-SteamSyncPlan $profile @($newGame)
    Assert ($beforeExit.OriginalHash -ne $afterExit.OriginalHash -and (Get-SteamPlanChangeSignature $beforeExit) -eq (Get-SteamPlanChangeSignature $afterExit)) 'Unrelated shortcut saves can be rebased without changing the reviewed additions'
    [void](Save-SteamSyncPlan $afterExit)
    Assert (@((Get-ShortcutSnapshot $profile.ShortcutPath).File.Items|Where-Object Title -eq $external.Title).Count -eq 1) 'Rebased imports preserve shortcuts Steam saved while exiting'
    $alreadyAdded=New-SteamSyncPlan $profile @($newGame)
    Assert ((Get-SteamPlanChangeSignature $alreadyAdded) -ne (Get-SteamPlanChangeSignature $beforeExit)) 'Changed proposed actions require a fresh preview review'
    Write-Output ("`nAll $script:passed Steam checks passed. Real Steam files were not modified.")
} finally {
    $resolved=[System.IO.Path]::GetFullPath($root)
    $allowed=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[System.IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
