$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SteamNite.Core.psm1') -Force
$script:passed = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:passed++; Write-Output ('PASS: ' + $Message)
}
$testRoot = Join-Path $PSScriptRoot ('.tmp\' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot -Force)
function New-XboxFixture($Name, $Executables, $ManifestApps = '<Application Id="Game" Executable="GameLaunchHelper.exe" />') {
    $folder = Join-Path $testRoot $Name
    $content = Join-Path $folder 'Content'
    [void](New-Item -ItemType Directory -Path $content -Force)
    @"
<Game><Identity Name="Fixture.$Name"/><ShellVisuals DefaultDisplayName="$Name"/><ExecutableList>$Executables</ExecutableList></Game>
"@ | Set-Content -LiteralPath (Join-Path $content 'MicrosoftGame.config') -Encoding UTF8
    "<Package xmlns='http://schemas.microsoft.com/appx/manifest/foundation/windows10'><Applications>$ManifestApps</Applications></Package>" | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $content 'appxmanifest.xml')
    [System.IO.File]::WriteAllBytes((Join-Path $content 'gamelaunchhelper.exe'), [byte[]]@())
    return $folder
}
try {
    $folder = New-XboxFixture 'Helper' '<Executable Name="ActualGame.exe" Id="Game"/>'
    $g = Get-XboxFolderGame $folder
    Assert ($g.Method -eq 'Xbox launch helper' -and $g.Target -like '*gamelaunchhelper.exe') 'Xbox uses the manifest launch helper instead of the named game EXE'
    $recipe = Start-DetectedGame $g -DryRun
    Assert ($recipe.WorkingDirectory -eq $g.InstallPath -and $recipe.UseShellExecute) 'Helper launch has the content working directory'
    $folder = New-XboxFixture 'MissingId' '<Executable Name="ActualGame.exe"/>'
    $g = Get-XboxFolderGame $folder
    Assert ($g.Method -eq 'Xbox launch helper') 'Single manifest application resolves a config without an executable ID'
    $folder = New-XboxFixture 'DLC' ''
    Assert ($null -eq (Get-XboxFolderGame $folder)) 'Content-only packages do not become launchable games'
    $folder = New-XboxFixture 'DevOnly' '<Executable Name="Editor.exe" Id="Game" IsDevOnly="true"/>'
    Assert ($null -eq (Get-XboxFolderGame $folder)) 'Development-only executables are excluded'
    $folder = New-XboxFixture 'Multiple' '<Executable Name="One.exe" Id="Game"/><Executable Name="Two.exe" Id="Other"/>'
    Assert ((Get-XboxFolderGame $folder).Status -eq 'Unresolved') 'Ambiguous executable lists require resolution'
    $folder = New-XboxFixture 'Activation' '<Executable Name="ActualGame.exe" Id="Game"/>' '<Application Id="Game" Executable="ActualGame.exe"/>'
    $package = [pscustomobject]@{Name='Fixture.Activation'; PackageFamilyName='Fixture.Activation_123abc'}
    $g = Get-XboxFolderGame $folder @($package)
    Assert ($g.Method -eq 'Windows activation' -and $g.Target -eq 'Fixture.Activation_123abc!Game') 'Registered package activation works when helper is not the manifest entry point'
    $recipe = Start-DetectedGame $g -DryRun
    Assert ($recipe.FileName -eq 'explorer.exe' -and $recipe.Arguments -eq 'shell:AppsFolder\Fixture.Activation_123abc!Game') 'Package launch builds the Windows activation command'
    Assert ((Get-XboxFolderGame $folder).Status -eq 'Unresolved') 'An arbitrary helper file alone is insufficient evidence'
    $blocked = $false
    try { Start-DetectedGame (Get-XboxFolderGame $folder) -DryRun } catch { $blocked = $true }
    Assert $blocked 'Unresolved games cannot launch'

    $epicPath = Join-Path $testRoot 'epic.item'
    $m = @{AppName='game-id';DisplayName='Epic Fixture';InstallLocation=$testRoot;LaunchExecutable='game.exe';CatalogNamespace='namespace';CatalogItemId='catalog';bIsIncompleteInstall=$false}
    $m | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $epicPath
    $g = Get-EpicManifestGame $epicPath
    Assert ($g.Target -eq 'com.epicgames.launcher://apps/namespace%3Acatalog%3Agame-id?action=launch&silent=true') 'Epic preserves catalog identity in its launch protocol'
    Assert ((Start-DetectedGame $g -DryRun).FileName -eq $g.Target) 'Epic launch dispatch uses the platform client'
    $m.MainGameAppName = 'different-base-game'; $m | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $epicPath
    Assert ($null -eq (Get-EpicManifestGame $epicPath)) 'Epic separate DLC records are excluded'
    $m.Remove('MainGameAppName'); $m.bIsIncompleteInstall=$true; $m | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $epicPath
    Assert ($null -eq (Get-EpicManifestGame $epicPath)) 'Incomplete Epic installs are excluded'
    $m.bIsIncompleteInstall=$false; $m.InstallLocation=Join-Path $testRoot 'not-installed'; $m | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $epicPath
    Assert ($null -eq (Get-EpicManifestGame $epicPath)) 'Missing Epic installation directories are excluded'

    # Build a disposable SQLite fixture using Windows' built-in SQLite, with no package dependencies.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SqliteFixture {
 [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] p, out IntPtr db, int flags, IntPtr vfs);
 [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr err);
 [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
 public static void Create(string path, string sql) {
  IntPtr db; if(sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"), out db, 6, IntPtr.Zero)!=0) throw new Exception("Fixture open failed");
  try { IntPtr err; if(sqlite3_exec(db, Encoding.UTF8.GetBytes(sql+"\0"), IntPtr.Zero, IntPtr.Zero, out err)!=0) throw new Exception("Fixture SQL failed"); }
  finally { sqlite3_close(db); }
 }
}
'@
    $dbPath = Join-Path $testRoot 'amazon.sqlite'
    $sqlPath = $testRoot.Replace("'", "''")
    [SqliteFixture]::Create($dbPath, "CREATE TABLE DbSet (Id TEXT, ProductTitle TEXT, InstallDirectory TEXT, Installed INTEGER); INSERT INTO DbSet VALUES ('amazon-id','Amazon Unicode $([char]0x00E9)','$sqlPath',1),('not-installed','Hidden','$sqlPath',0),('missing-folder','Missing','$sqlPath\missing',1);")
    $before = (Get-FileHash -LiteralPath $dbPath).Hash
    $amazon = @(Get-AmazonGames $dbPath)
    Assert ($amazon.Count -eq 1 -and $amazon[0].Id -eq 'amazon:amazon-id') 'Amazon reads only installed games with existing directories'
    Assert ($amazon[0].Title -eq "Amazon Unicode $([char]0x00E9)") 'SQLite title decoding preserves Unicode'
    Assert ($amazon[0].Target -eq 'amazon-games://play/amazon-id') 'Amazon launch uses its game identity'
    Assert ((Start-DetectedGame $amazon[0] -DryRun).FileName -eq $amazon[0].Target) 'Amazon launch dispatch uses the platform client'
    Assert ((Get-FileHash -LiteralPath $dbPath).Hash -eq $before) 'Amazon discovery leaves the launcher database unchanged'
    $writeBlocked = $false
    try { [void][SteamNite.NativeSqlite]::Read($dbPath, 'DELETE FROM DbSet;') } catch { $writeBlocked = $true }
    Assert $writeBlocked 'SQLite connection enforces read-only mode'
    Write-Output ("`nAll $script:passed checks passed. No games were launched.")
} finally {
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    $allowed = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp')) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
