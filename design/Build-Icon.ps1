$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
# Original geometric gateway mark. Keep in sync with oathgate.svg.
$images = @()
foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform($size / 256.0, $size / 256.0)
    $graphics.Clear([System.Drawing.Color]::FromArgb(23,25,29))
    $blue = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(156,183,238),16)
    $white = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(240,240,236),16)
    foreach ($pen in @($blue,$white)) { $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round' }
    $graphics.DrawLine($blue,76,198,76,86)
    $graphics.DrawArc($blue,76,34,104,104,180,180)
    $graphics.DrawLine($blue,180,86,180,198)
    $graphics.DrawLine($white,48,142,134,142)
    $graphics.DrawLine($white,112,120,134,142)
    $graphics.DrawLine($white,134,142,112,164)
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
    $images += ,$stream.ToArray()
    if ($size -eq 256) { $bitmap.Save((Join-Path $PSScriptRoot 'oathgate.png'),[System.Drawing.Imaging.ImageFormat]::Png) }
    $stream.Dispose(); $graphics.Dispose(); $blue.Dispose(); $white.Dispose(); $bitmap.Dispose()
}
$file = [System.IO.File]::Create((Join-Path $PSScriptRoot 'oathgate.ico'))
$writer = New-Object System.IO.BinaryWriter($file)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
$sizes = @(16,24,32,48,64,128,256)
for ($index = 0; $index -lt $images.Count; $index++) {
    $dimension = $sizes[$index] % 256
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$index].Length); $writer.Write([uint32]$offset)
    $offset += $images[$index].Length
}
foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
$writer.Dispose()
