$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\src\Steam.Session.Dialog.ps1')
$script:passed=0;$script:running=$false;$script:consent=$false;$script:shutdowns=0;$script:prompts=0;$script:waits=0;$script:waitResult=$true;$script:timeout=$false
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;'PASS: '+$Message}
function Test-SteamRunning{$script:running}
function Get-SteamCloseDecision($Owner,$Action){$script:prompts++;$script:consent}
function Request-SteamShutdown($Profile){$script:shutdowns++}
function Wait-SteamClosed($Owner,$TimeoutSeconds){$script:waits++;if($script:timeout){throw 'Steam has not exited yet'};$script:waitResult}
Assert (Confirm-SteamClosed $null @{}) 'An already closed Steam client needs no prompt'
Assert ($script:prompts -eq 0 -and $script:shutdowns -eq 0) 'Idle client handling never launches or shuts down Steam'
$script:running=$true
Assert (-not (Confirm-SteamClosed $null @{})) 'Declining the close prompt cancels the pending write action'
Assert ($script:prompts -eq 1 -and $script:shutdowns -eq 0 -and $script:waits -eq 0) 'A declined prompt cannot request shutdown or wait'
$script:consent=$true
Assert (Confirm-SteamClosed $null @{}) 'Consenting continues only after the exit wait succeeds'
Assert ($script:shutdowns -eq 1 -and $script:waits -eq 1) 'Consenting dispatches exactly one graceful close request'
$script:waitResult=$false
Assert (-not (Confirm-SteamClosed $null @{})) 'Cancelling the exit wait does not authorize the write'
$script:timeout=$true;$threw=$false
try{[void](Confirm-SteamClosed $null @{})}catch{$threw=$true}
Assert $threw 'An exit timeout propagates an error instead of permitting changes'
"`nAll $script:passed Steam session checks passed. No Steam processes were controlled."
