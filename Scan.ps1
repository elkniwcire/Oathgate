param([string[]]$ExtraRoots = @(), [string]$OutputPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\SteamNite.Core.psm1') -Force
$result = Get-GameScan -ExtraRoots $ExtraRoots
if ($OutputPath) { $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
else { $result | ConvertTo-Json -Depth 8 }
