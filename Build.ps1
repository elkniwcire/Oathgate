param([ValidateSet('SteamNite.exe','SteamNite.Workflow.exe')][string]$OutputName='SteamNite.exe')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Build with Windows PowerShell: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1' }
$output = Join-Path $PSScriptRoot $OutputName
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
Add-Type -Path (Join-Path $PSScriptRoot 'src\Program.cs') -OutputAssembly $output -OutputType WindowsApplication -ReferencedAssemblies @(
    [System.Management.Automation.PowerShell].Assembly.Location,
    'System.Windows.Forms.dll', 'System.Core.dll'
)
Write-Output ('Built ' + $output)
