$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'tools\PublicSource.ps1')
$files=@(Get-PublicSourceFiles $PSScriptRoot)
Assert-PublicSourceClean $files
$artifacts=Join-Path $PSScriptRoot 'artifacts';[void][IO.Directory]::CreateDirectory($artifacts)
$stage=Join-Path $artifacts ('source-'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $stage 'Oathgate';[void][IO.Directory]::CreateDirectory($source)
foreach ($file in $files) {
    $relative=$file.FullName.Substring($PSScriptRoot.Length+1)
    $out=Join-Path $source $relative
    [void][IO.Directory]::CreateDirectory((Split-Path $out))
    [IO.File]::Copy($file.FullName,$out,$false)
}
$zip=Join-Path $artifacts 'Oathgate-source.zip'
# Compress-Archive skips dotfiles; GitHub workflows and .gitignore must ship.
. (Join-Path $PSScriptRoot 'tools\New-Zip.ps1')
New-OathgateZip $source $zip
Write-Output ('Clean source tree (no Git history): '+$source)
Write-Output ('Source archive: '+$zip)
