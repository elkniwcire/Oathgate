function Get-PublicSourceFiles([string]$Root) {
    # Explicit source roots; never enumerate the whole working tree for export.
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Force)) {
        if ($file.Extension -in @('.ps1','.cmd','.md') -or $file.Name -in @('LICENSE','.gitignore','.gitattributes','global.json','NuGet.Config')) { $file }
    }
    foreach ($name in @('src','winui','tests','design','docs','tools','.github')) {
        $directory=Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        $pending=New-Object 'System.Collections.Generic.Queue[string]';$pending.Enqueue($directory)
        while ($pending.Count) {
            foreach ($item in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($item.PSIsContainer) {
                    if ($item.Name -notin @('bin','obj','.tmp','.git','data','.tools','artifacts')) { $pending.Enqueue($item.FullName) }
                } elseif ($item.Extension -in @('.cs','.ps1','.psm1','.csproj','.xaml','.manifest','.md','.json','.svg','.png','.ico','.yml','.yaml')) { $item }
            }
        }
    }
}
function Assert-PublicSourceClean([IO.FileInfo[]]$Files) {
    foreach ($file in $Files) {
        if ($file.Extension -notin @('.cs','.ps1','.psm1','.md','.json','.xaml','.yml','.yaml','.csproj','.cmd')) { continue }
        $body=[IO.File]::ReadAllText($file.FullName)
        # High-confidence leak checks; errors name files, never matched secrets.
        if ($body -match '(?i)[A-Z]:\\Users\\(?!Public\b|Default\b|<|fixture\b)[^\\\s"'']+' -or $body -match 'userdata[\\/]+\d{5,}') {
            throw ('Personal account/path data detected in '+$file.Name)
        }
        if ($body -match '["''][a-fA-F0-9]{32,64}["'']' -or $body -match '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|Bearer\s+[A-Za-z0-9._-]{20,})') {
            throw ('Possible literal credential detected in '+$file.Name)
        }
    }
}
