$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$local=Join-Path $workspace '.tools\dotnet\dotnet.exe'
$dotnet=if(Test-Path -LiteralPath $local){$local}else{(Get-Command dotnet -ErrorAction Stop).Source}
& $dotnet run --project (Join-Path $PSScriptRoot 'WorkflowClient\WorkflowClient.csproj') -- $workspace
if($LASTEXITCODE -ne 0){throw 'Workflow client lifecycle regression checks failed.'}
