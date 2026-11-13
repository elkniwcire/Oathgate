param(
    [Parameter(Mandatory)][string[]]$GameId,
    [Parameter(Mandatory)][string]$AccountId,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Steam.psm1') -Force
$profiles = @(Get-SteamProfiles | Where-Object { $_.AccountId -eq $AccountId })
if ($profiles.Count -ne 1) { throw 'Expected exactly one matching Steam profile.' }
$scan = Get-GameScan
$games = @($scan.Games | Where-Object { $_.Id -in $GameId })
if ($games.Count -ne @($GameId | Select-Object -Unique).Count) { throw 'One or more requested games were not discovered.' }
$plan = New-SteamSyncPlan -Profile $profiles[0] -Games $games
if ($Apply) { Save-SteamSyncPlan -Plan $plan | ConvertTo-Json }
else {
    [pscustomobject]@{ Destination=$plan.Profile.ShortcutPath; ExistingCount=$plan.ExistingCount; AddCount=$plan.AddCount;RepairCount=$plan.RepairCount; SteamRunning=(Test-SteamRunning); Rows=$plan.Rows } | ConvertTo-Json -Depth 6
}
