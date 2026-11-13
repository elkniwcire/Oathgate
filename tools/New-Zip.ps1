function New-OathgateZip([string]$Directory,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $base=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $prefix=[IO.Path]::GetFileName($base)+'/'
    $stream=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $archive=$null
    try {
        $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        foreach($file in @(Get-ChildItem -LiteralPath $base -File -Recurse -Force)) {
            $name=$prefix+$file.FullName.Substring($base.Length+1).Replace('\','/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { if($archive){$archive.Dispose()};$stream.Dispose() }
}
