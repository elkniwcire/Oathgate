param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
$assets=Get-Content -LiteralPath (Join-Path $Workspace 'winui\obj\project.assets.json') -Raw|ConvertFrom-Json
$packageRoots=@($assets.packageFolders.PSObject.Properties.Name)
$packages=@($assets.libraries.PSObject.Properties|ForEach-Object {$_.Value.path})
# Runtime packs are resolved separately from application NuGet libraries.
$config=Get-Content -LiteralPath (Join-Path $Workspace 'winui\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\Oathgate.runtimeconfig.json') -Raw|ConvertFrom-Json
$version=($config.runtimeOptions.includedFrameworks|Where-Object name -eq 'Microsoft.NETCore.App').version
if (-not $version) { throw 'Cannot resolve the bundled .NET runtime notice version.' }
$packages+=('microsoft.netcore.app.runtime.win-x64/'+$version)
foreach ($package in @($packages|Select-Object -Unique)) {
    foreach ($root in $packageRoots) {
        $path=Join-Path $root $package
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $path -File -Recurse | Where-Object { $_.Name -match '^(license|third.party|notice)' -and $_.Extension -in @('','.txt','.md','.html','.rtf') -or $_.Extension -eq '.nuspec' })) {
            $out=Join-Path $Destination ($package+'/'+$file.FullName.Substring($path.Length+1))
            [void][IO.Directory]::CreateDirectory((Split-Path $out));[IO.File]::Copy($file.FullName,$out,$true)
        }
        break
    }
}
if (-not @(Get-ChildItem -LiteralPath $Destination -File -Recurse).Count) { throw 'Dependency notices were not found.' }
if (-not @(Get-ChildItem -LiteralPath (Join-Path $Destination ('microsoft.netcore.app.runtime.win-x64/'+$version)) -File -Recurse | Where-Object Name -match '^LICENSE').Count) { throw 'Bundled .NET runtime license is missing.' }
