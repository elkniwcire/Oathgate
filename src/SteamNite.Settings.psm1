$ErrorActionPreference='Stop'
function Get-AppSettings([string]$Path, [switch]$Recover) {
    $values=@{}
    if(Test-Path -LiteralPath $Path){
        $raw=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        try {
            $saved=$raw|ConvertFrom-Json
            if ($null -eq $saved -or $saved -isnot [pscustomobject]) { throw 'Settings must be a JSON object.' }
        } catch {
            if (-not $Recover) { throw }
            $backup=$Path+'.invalid-'+[guid]::NewGuid().ToString('N')
            [IO.File]::Move($Path,$backup)
            [IO.File]::WriteAllText((Join-Path (Split-Path $Path) 'settings-recovery.txt'),'Unreadable settings were preserved in a settings.json.invalid-* file. Select your Steam account and scan folders again. Other app data was preserved.')
            return $values
        }
        foreach($property in $saved.PSObject.Properties){$values[$property.Name]=$property.Value}
    }
    return $values
}
function Save-AppSettings {
    param([string]$Path,[hashtable]$Changes)
    $values=Get-AppSettings $Path;foreach($key in $Changes.Keys){$values[$key]=$Changes[$key]}
    [void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($Path))))
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        $values|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Get-NormalizedScanFolders([string[]]$Folders) {
    $seen=@{}
    foreach($folder in $Folders){
        if(-not $folder){continue}
        if(-not [IO.Path]::IsPathRooted($folder)){throw 'Scan folders must use absolute paths.'}
        $path=[IO.Path]::GetFullPath($folder)
        if($path -ne [IO.Path]::GetPathRoot($path)){$path=$path.TrimEnd([char[]]'\/')}
        if(-not $seen.ContainsKey($path)){$seen[$path]=$true;$path}
    }
}
Export-ModuleMember -Function Get-AppSettings, Save-AppSettings, Get-NormalizedScanFolders
