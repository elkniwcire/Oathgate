$ErrorActionPreference='Stop'
$hostSource=Join-Path $PSScriptRoot '..\SteamNite.Workflow.exe'
if(-not (Test-Path -LiteralPath $hostSource)){throw 'Build the workflow host with Build.ps1 -OutputName SteamNite.Workflow.exe first.'}
$root=Join-Path $PSScriptRoot ('.tmp\workflow-host-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
try{
    $executable=Join-Path $root 'SteamNite.Workflow.exe';[IO.File]::Copy([IO.Path]::GetFullPath($hostSource),$executable)
    $request=Join-Path $root 'request with spaces.json';[IO.File]::WriteAllText($request,'{}')
    @'
param([string]$WorkflowRequest)
@{Request=$WorkflowRequest;Apartment=[Threading.Thread]::CurrentThread.ApartmentState.ToString()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding UTF8
'@|Set-Content -LiteralPath (Join-Path $root 'SteamNite.ps1') -Encoding UTF8
    function Run-FixtureHost {
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$executable;$start.Arguments='--workflow-request "'+$request+'"';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardError=$true;$start.RedirectStandardOutput=$true
        $process=[Diagnostics.Process]::Start($start)
        try{
            $errorTask=$process.StandardError.ReadToEndAsync();$outputTask=$process.StandardOutput.ReadToEndAsync()
            if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Fixture host timed out.'}
            [pscustomobject]@{Code=$process.ExitCode;Error=$errorTask.Result}
        }finally{$process.Dispose()}
    }
    $result=Run-FixtureHost
    if($result.Code -ne 0){throw ('Workflow host failed: '+$result.Error)}
    $record=Get-Content -LiteralPath (Join-Path $root 'result.json') -Raw|ConvertFrom-Json
    if($record.Request -ne $request){throw 'Typed workflow path was not preserved.'}
    if($record.Apartment -ne 'STA'){throw 'Workflow host is not STA.'}
    "throw 'Synthetic workflow failure'"|Set-Content -LiteralPath (Join-Path $root 'SteamNite.ps1') -Encoding UTF8
    $failed=Run-FixtureHost
    if($failed.Code -eq 0 -or $failed.Error -notlike '*Synthetic workflow failure*'){throw 'Workflow host did not report a structured process failure.'}
    'All 3 workflow host checks passed. Isolated synthetic script; no real app data or Steam changes.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
