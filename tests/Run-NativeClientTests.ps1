$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$local=Join-Path $workspace '.tools\dotnet\dotnet.exe'
$dotnet=if(Test-Path -LiteralPath $local){$local}else{(Get-Command dotnet -ErrorAction Stop).Source}
& $dotnet run --project (Join-Path $PSScriptRoot 'NativeClient\NativeClient.csproj') -- $workspace
if($LASTEXITCODE -ne 0){throw 'Native pipe tests failed.'}
