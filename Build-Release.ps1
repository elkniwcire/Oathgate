param([ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$')][string]$Version='0.3.0-preview', [switch]$SkipBuild)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'tools\PublicSource.ps1')
Assert-PublicSourceClean @(Get-PublicSourceFiles $PSScriptRoot)
if (-not $SkipBuild) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-WinUI.ps1') -Version $Version;if($LASTEXITCODE){throw 'Build failed.'} }
$runtime=Join-Path $PSScriptRoot 'winui\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64'
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'Oathgate.exe'))) { throw 'Build Release first.' }
$builtVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $runtime 'Oathgate.dll')).ProductVersion.Split('+')[0]
if ($builtVersion -ne $Version) { throw 'The built app version does not match the requested release. Rebuild without -SkipBuild.' }
$artifacts=Join-Path $PSScriptRoot 'artifacts';[void][IO.Directory]::CreateDirectory($artifacts)
$stage=Join-Path $artifacts ('stage-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $stage ('Oathgate-'+$Version+'-win-x64');[void][IO.Directory]::CreateDirectory($package)
foreach ($item in @(Get-ChildItem -LiteralPath $runtime)) {
    if ($item.Extension -eq '.pdb' -or $item.Name -like 'SteamNite.WinUI.*' -or $item.Name -in @('data','obj','bin')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $package -Recurse
}
foreach ($name in @('src','design','winui')) { [void][IO.Directory]::CreateDirectory((Join-Path $package $name)) }
foreach ($item in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -File | Where-Object Extension -in @('.cs','.psm1','.ps1'))) { Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $package 'src') }
foreach ($name in @('tokens.json')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('design\'+$name)) -Destination (Join-Path $package 'design') }
foreach ($name in @('Native.Service.ps1','Backend.Snapshot.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('winui\'+$name)) -Destination (Join-Path $package 'winui') }
foreach ($name in @('SteamNite.ps1','LICENSE','THIRD-PARTY-NOTICES.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs\release-readme.md') -Destination (Join-Path $package 'README.md')
& (Join-Path $PSScriptRoot 'tools\Copy-Notices.ps1') -Workspace $PSScriptRoot -Destination (Join-Path $package 'notices')
$files=@(Get-ChildItem -LiteralPath $package -File -Recurse)
$manifest=@(foreach($file in $files){[pscustomobject]@{Path=$file.FullName.Substring($package.Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}})
$manifest|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $package 'files.sha256.json') -Encoding UTF8
$zip=Join-Path $artifacts ('Oathgate-'+$Version+'-win-x64.zip')
. (Join-Path $PSScriptRoot 'tools\New-Zip.ps1')
New-OathgateZip $package $zip
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash+'  '+[IO.Path]::GetFileName($zip)|Set-Content -LiteralPath ($zip+'.sha256') -Encoding ASCII
Write-Output ('Release: '+$zip)
Write-Output ('Staged app: '+(Join-Path $package 'Oathgate.exe'))
