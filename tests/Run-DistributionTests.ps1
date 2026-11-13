$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $workspace 'tools\PublicSource.ps1')
$files=@(Get-PublicSourceFiles $workspace);$passed=0
function Assert($Value,$Message) { if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++;Write-Output ('PASS: '+$Message) }
Assert-PublicSourceClean $files
Assert $true 'Public source passes account, path and literal credential leak checks'
$fixture=Join-Path $PSScriptRoot ('.tmp\leak-fixture-'+[guid]::NewGuid().ToString('N')+'.json')
[void][IO.Directory]::CreateDirectory((Split-Path $fixture))
try {
    [IO.File]::WriteAllText($fixture,('{"key":"'+('a'*32)+'"}'))
    $rejected=$false;try { Assert-PublicSourceClean @((Get-Item -LiteralPath $fixture)) } catch { $rejected=$true }
    Assert $rejected 'Source leak checks reject a synthetic literal credential'
} finally { [IO.File]::Delete($fixture) }
$paths=@($files|ForEach-Object {$_.FullName.Substring($workspace.Length+1).Replace('\','/')})
Assert ($paths -contains 'winui/MainWindow.xaml' -and $paths -contains '.github/workflows/windows.yml') 'Source export includes native UI and CI files'
Assert (-not @($paths|Where-Object {$_ -match '(^|/)(data|\.tools|bin|obj|\.tmp|\.git|artifacts)/' -or $_ -match '\.(key|exe|pdb)$'}).Count) 'Source export excludes credentials, personal data, history and generated binaries'
Assert ($paths -contains 'src/SteamNite.Storage.psm1' -and $paths -contains 'LICENSE') 'Clean source includes storage implementation and license'
$sourceZip=Join-Path $workspace 'artifacts\Oathgate-source.zip'
if (Test-Path -LiteralPath $sourceZip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($sourceZip)
    try {
        $entries=@($archive.Entries.FullName)
        Assert ($entries -contains 'Oathgate/.github/workflows/windows.yml' -and $entries -contains 'Oathgate/.gitignore') 'Source ZIP retains GitHub workflows and dotfiles'
        Assert (-not @($entries|Where-Object {$_ -match '(^|/)(data|\.git|\.tools|bin|obj|\.tmp)/|\.key$'}).Count) 'Source ZIP excludes history, credentials and generated files'
    } finally { $archive.Dispose() }
}
$privatePaths=@()
foreach($file in $files|Where-Object Extension -in @('.cs','.ps1','.psm1','.md','.json','.xaml','.yml','.yaml','.csproj')) {
    $body=[IO.File]::ReadAllText($file.FullName)
    if($body -match '(?i)[A-Z]:\\Users\\(?!Public\b|Default\b|<|fixture\b)[^\\\s"'']+' -or $body -match 'userdata[\\/]+\d{5,}'){$privatePaths+=$file.Name}
}
Assert ($privatePaths.Count -eq 0) ('Source has no private Windows-user paths or literal Steam account directories: '+($privatePaths -join ', '))
$packages=@(Get-ChildItem -LiteralPath (Join-Path $workspace 'artifacts') -Directory -Filter 'stage-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if($packages.Count) {
    $package=Get-ChildItem -LiteralPath $packages[0].FullName -Directory|Select-Object -First 1
    $contents=@(Get-ChildItem -LiteralPath $package.FullName -File -Recurse)
    Assert (-not @($contents|Where-Object {$_.Extension -in @('.key','.pdb') -or $_.FullName -match '[\\/](data|\.git|\.tools)[\\/]'}).Count) 'Release package contains no personal state or debug symbols'
    Assert ((Test-Path (Join-Path $package.FullName 'Oathgate.exe')) -and (Test-Path (Join-Path $package.FullName 'winui\Native.Service.ps1')) -and (Test-Path (Join-Path $package.FullName 'design\tokens.json'))) 'Release contains the executable and backend support files'
    Assert (@($contents|Where-Object {$_.FullName -match 'notices' -and $_.Name -match 'LICENSE|NOTICE'}).Count -gt 0) 'Release preserves dependency license notices'
}
"All $passed distribution checks passed."
