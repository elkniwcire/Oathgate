$ErrorActionPreference = 'Stop'
function Get-OathgateDataDirectory {
    # Tests and development can isolate state without changing the Windows profile.
    if ($env:OATHGATE_DATA_DIR) {
        if (-not [IO.Path]::IsPathRooted($env:OATHGATE_DATA_DIR)) { throw 'OATHGATE_DATA_DIR must be an absolute path.' }
        return [IO.Path]::GetFullPath($env:OATHGATE_DATA_DIR)
    }
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Oathgate'
}
function Initialize-OathgateStorage {
    param([string]$LegacyDirectory, [string]$Destination=(Get-OathgateDataDirectory))
    [void][IO.Directory]::CreateDirectory($Destination)
    # Explicit test/development storage must never import personal state.
    if ($env:OATHGATE_DATA_DIR -or -not $LegacyDirectory) { return $Destination }
    $legacy = [IO.Path]::GetFullPath($LegacyDirectory).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($legacy -eq $target) { return $Destination }
    $lock = $null
    try {
        # Snapshot and workflow services can initialize at the same time.
        for ($attempt=0; $attempt -lt 50 -and -not $lock; $attempt++) {
            try { $lock=[IO.File]::Open((Join-Path $Destination '.migration.lock'),'OpenOrCreate','ReadWrite','None') }
            catch [IO.IOException] { Start-Sleep -Milliseconds 100 }
        }
        if (-not $lock) { throw 'Another Oathgate process is migrating settings. Please try again.' }
        $marker=Join-Path $Destination '.migration-v1'
        if (Test-Path -LiteralPath $marker) { return $Destination }
        if (Test-Path -LiteralPath $legacy -PathType Container) {
            # Copy only app state; never scan exports, SDKs, or arbitrary files.
            $files=@('settings.json','game-preferences.json','launch-overrides.json','install-history.json','steamgriddb.key')
            foreach ($item in @(Get-ChildItem -LiteralPath $legacy -File)) {
                if (($item.Name -in $files -or $item.Name -match '^artwork-\d+\.json$') -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $out=Join-Path $Destination $item.Name
                    if (-not (Test-Path -LiteralPath $out)) { [IO.File]::Copy($item.FullName,$out,$false) }
                }
            }
            # History and cache paths remain usable; originals are retained.
            foreach ($name in @('operations','artwork-cache')) {
                $source=Join-Path $legacy $name
                if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
                $pending=New-Object 'System.Collections.Generic.Queue[string]';$pending.Enqueue($source)
                while ($pending.Count) {
                    $folder=$pending.Dequeue()
                    if ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    foreach ($item in @(Get-ChildItem -LiteralPath $folder)) {
                        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                        if ($item.PSIsContainer) { $pending.Enqueue($item.FullName);continue }
                        $out=Join-Path $Destination $item.FullName.Substring($legacy.Length+1)
                        [void][IO.Directory]::CreateDirectory((Split-Path $out))
                        if (-not (Test-Path -LiteralPath $out)) { [IO.File]::Copy($item.FullName,$out,$false) }
                    }
                }
            }
        }
        [IO.File]::WriteAllText($marker,'Legacy state copied without overwriting existing files. Original files were retained.')
        return $Destination
    } finally { if ($lock) { $lock.Dispose() } }
}
Export-ModuleMember -Function Get-OathgateDataDirectory, Initialize-OathgateStorage
