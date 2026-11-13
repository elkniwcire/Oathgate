if(-not ('SteamNite.DialogTheme' -as [type])){
    Add-Type -Path (Join-Path $PSScriptRoot 'DialogTheme.cs') -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll','System.Core.dll'
}
$themeTokens=Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'design\tokens.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($entry in @{Background='background';Panel='surface';Input='input';Hover='hover';Selection='selection';Text='text';Muted='muted';Accent='accent';Border='border';Success='success';Warning='warning';Danger='danger'}.GetEnumerator()){
    [SteamNite.DialogTheme].GetField($entry.Key).SetValue($null,[Drawing.ColorTranslator]::FromHtml([string]$themeTokens.($entry.Value)))
}
function Set-SteamNiteTheme($Window){[SteamNite.DialogTheme]::Apply($Window)}
