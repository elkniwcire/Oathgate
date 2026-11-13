param([ValidateSet('Debug','Release')][string]$Configuration='Release', [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$')][string]$Version='0.3.0-preview')
$ErrorActionPreference='Stop'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build.ps1') -OutputName SteamNite.Workflow.exe
if($LASTEXITCODE -ne 0){throw 'The workflow host could not be built. Close any open workflow dialog before rebuilding.'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build.ps1')
if($LASTEXITCODE -ne 0){throw 'The native app launcher could not be built.'}
$local=Join-Path $PSScriptRoot '.tools\dotnet\dotnet.exe'
$dotnet=if(Test-Path -LiteralPath $local){$local}else{(Get-Command dotnet -ErrorAction Stop).Source}
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1';$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1'
& $dotnet build (Join-Path $PSScriptRoot 'winui\SteamNite.WinUI.csproj') -c $Configuration -p:Platform=x64 ('-p:Version='+$Version)
if($LASTEXITCODE -ne 0){throw 'WinUI build failed. A .NET 8 SDK and access to NuGet are required.'}
Write-Output ('Native app: '+(Join-Path $PSScriptRoot ('winui\bin\x64\'+$Configuration+'\net8.0-windows10.0.19041.0\win-x64\Oathgate.exe')))
