function Show-ArtworkDialog {
    param($Game, $PreferredProfile=$null, [switch]$SmokeTest)
    $profiles = @(Get-SteamProfiles)
    if (-not $profiles.Count -and -not $SmokeTest) { throw 'Sign into Steam once before adding artwork.' }
    $window = New-Object System.Windows.Forms.Form
    $window.Text = 'SteamNite artwork | ' + $Game.Title
    $window.Size = New-Object Drawing.Size(1150,800); $window.MinimumSize = New-Object Drawing.Size(950,700)
    $window.Font = $form.Font; $window.StartPosition = 'CenterParent'
    $root = New-Object Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'; $root.Padding = New-Object Windows.Forms.Padding(14); $root.ColumnCount=1; $root.RowCount=7
    foreach ($height in @(42,42,42)) { [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height))) }
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
    foreach ($height in @(60,65,84)) { [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height))) }
    $window.Controls.Add($root)
    $keyBar = New-Object Windows.Forms.FlowLayoutPanel; $keyBar.Dock='Fill'; $keyBar.WrapContents=$false; $root.Controls.Add($keyBar,0,0)
    $keyLabel=New-Object Windows.Forms.Label; $keyLabel.Text='SteamGridDB key:'; $keyLabel.AutoSize=$true; $keyLabel.Margin=New-Object Windows.Forms.Padding(0,8,6,0); $keyBar.Controls.Add($keyLabel)
    $keyBox=New-Object Windows.Forms.TextBox; $keyBox.Width=280; $keyBox.UseSystemPasswordChar=$true; $keyBox.AccessibleName='SteamGridDB API key'; $keyBar.Controls.Add($keyBox)
    $remember=New-Object Windows.Forms.CheckBox; $remember.Text='Remember key'; $remember.AutoSize=$true; $keyBar.Controls.Add($remember)
    $keyLink=Add-Button 'Get API key' $keyBar 110
    $forget=Add-Button 'Forget key' $keyBar 110
    $queryBar=New-Object Windows.Forms.FlowLayoutPanel; $queryBar.Dock='Fill'; $queryBar.WrapContents=$false; $root.Controls.Add($queryBar,0,1)
    $query=New-Object Windows.Forms.TextBox; $query.Width=340; $query.Text=$Game.Title; $query.AccessibleName='Artwork search title'; $queryBar.Controls.Add($query)
    $searchHint=New-Object Windows.Forms.Label; $searchHint.Text='Searches automatically'; $searchHint.AutoSize=$true; $searchHint.Margin=New-Object Windows.Forms.Padding(8,8,12,0); $queryBar.Controls.Add($searchHint)
    $kindBox=New-Object SteamNite.ThemeComboBox; $kindBox.DropDownStyle='DropDownList'; $kindBox.Width=130; $kindBox.AccessibleName='Artwork type'
    [void]$kindBox.Items.AddRange([object[]]@('Cover','Wide','Hero','Logo','Icon')); $kindBox.SelectedIndex=0; $queryBar.Controls.Add($kindBox)
    $profileBox=New-Object SteamNite.ThemeComboBox; $profileBox.DropDownStyle='DropDownList'; $profileBox.Dock='Fill'; $profileBox.AccessibleName='Artwork Steam profile'
    foreach ($p in $profiles) { [void]$profileBox.Items.Add($p.Label) }; $root.Controls.Add($profileBox,0,2)
    $content=New-Object Windows.Forms.TableLayoutPanel; $content.Dock='Fill'; $content.ColumnCount=3; $content.RowCount=1
    [void]$content.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',20)))
    [void]$content.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',55)))
    [void]$content.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',25)))
    $root.Controls.Add($content,0,3)
    $matches=New-Object Windows.Forms.ListBox; $matches.Dock='Fill'; $matches.HorizontalScrollbar=$true; $matches.AccessibleName='Game matches'; $content.Controls.Add($matches,0,0)
    $thumbs=New-Object Windows.Forms.ImageList
    $thumbs.ImageSize=New-Object Drawing.Size(144,184); $thumbs.ColorDepth='Depth32Bit'
    $assets=New-Object Windows.Forms.ListView; $assets.Dock='Fill'; $assets.View='LargeIcon'; $assets.MultiSelect=$false
    $assets.HideSelection=$false; $assets.LargeImageList=$thumbs; $assets.AccessibleName='Artwork thumbnail grid'
    $assets.BackColor=[Drawing.Color]::FromArgb(238,241,245); $assets.ShowItemToolTips=$true
    $content.Controls.Add($assets,1,0)
    $picture=New-Object Windows.Forms.PictureBox; $picture.Dock='Fill'; $picture.SizeMode='Zoom'; $picture.BackColor=[Drawing.Color]::FromArgb(38,43,52); $picture.AccessibleName='Selected artwork preview'; $content.Controls.Add($picture,2,0)
    $selection=New-Object Windows.Forms.Label; $selection.Dock='Fill'; $root.Controls.Add($selection,0,4)
    $artStatus=New-Object Windows.Forms.Label; $artStatus.Dock='Fill'; $artStatus.Text='Artwork loads automatically. Paste your SteamGridDB key to begin. Choose images to add or replace artwork. Automatic recommendations fill missing slots only.'; $root.Controls.Add($artStatus,0,5)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel; $buttons.Dock='Fill'; $root.Controls.Add($buttons,0,6)
    $use=Add-Button 'Use this image' $buttons 145; $use.Enabled=$false
    $applyArt=Add-Button 'Apply selections' $buttons 185; $applyArt.Enabled=$false
    $recommend=Add-Button 'Fill missing recommended' $buttons 225; $recommend.Enabled=$false
    $showCurrent=Add-Button 'Show current art' $buttons 150;$showCurrent.Enabled=$false
    $clearArt=Add-Button 'Clear choices' $buttons 130
    $closeArt=Add-Button 'Close' $buttons 100
    $openSteam=Add-Button 'Open Steam' $buttons 120;$openSteam.Enabled=$false
    $ctx=@{Worker=$null;Handle=$null;Callback=$null;MatchItems=@();Sets=@{};CurrentAssets=@();Selections=@{};CurrentPath='';CurrentAsset=$null;ConfirmedMatch=$null;Steam=$null;ContextError='';Loading=$false;Applied=$false;Generation=0;JobGeneration=0;Pending='';DueAt=[datetime]::MinValue;Cancellation=$null;Mode=''}
    try { $savedKey=Get-ArtworkApiKey $script:dataDir; if ($savedKey) { $keyBox.Text=$savedKey; $remember.Checked=$true }; $savedKey=$null }
    catch { $artStatus.Text='Saved key could not be read on this Windows account. Enter your key again.' }

    function Update-ArtworkSelection {
        $parts=@(foreach ($kind in @('Cover','Wide','Hero','Logo','Icon')) {
            $label='not selected'
            $exists=$ctx.Steam -and (@(Get-ExistingArtwork $ctx.Steam $kind).Count -gt 0 -or ($kind -eq 'Icon' -and $ctx.Steam.Icon))
            if($exists){$label='current artwork'}
            if($ctx.Selections.ContainsKey($kind)){$label=if($exists){'REPLACE selected'}else{'ADD selected'}}
            $kind+': '+$label
        })
        $selection.Text=($parts -join '   |   ')
        $replacementCount=@($ctx.Selections.Keys|Where-Object {$ctx.Steam -and (@(Get-ExistingArtwork $ctx.Steam $_).Count -gt 0 -or ($_ -eq 'Icon' -and $ctx.Steam.Icon))}).Count
        $applyArt.Text=if($replacementCount){'Apply ('+$replacementCount+' replacements)'}else{'Apply selections'}
        $currentKind=[string]$kindBox.SelectedItem
        $showCurrent.Enabled=$null -ne $ctx.Steam -and -not $ctx.Worker -and -not $ctx.Pending -and (@(Get-ExistingArtwork $ctx.Steam $currentKind).Count -gt 0 -or ($currentKind -eq 'Icon' -and $ctx.Steam.Icon))
        if($ctx.ContextError){$selection.Text+="`r`n"+$ctx.ContextError}
        $applyArt.Enabled=$ctx.Selections.Count -gt 0 -and $null -ne $ctx.Steam -and -not $ctx.Worker -and -not $ctx.Pending
        $recommend.Enabled=$null -ne $ctx.ConfirmedMatch -and $null -ne $ctx.Steam -and -not $ctx.Worker -and -not $ctx.Pending -and -not $ctx.Applied
        $openSteam.Enabled=$profileBox.SelectedIndex -ge 0 -and -not $ctx.Worker -and -not $ctx.Pending
    }
    function Refresh-ArtworkContext {
        $ctx.Steam=$null;$ctx.ContextError=''
        if ($profileBox.SelectedIndex -ge 0) {
            try { $ctx.Steam=Get-SteamArtworkContext $profiles[$profileBox.SelectedIndex] $Game }
            catch { $ctx.ContextError=$_.Exception.Message;$artStatus.Text=$ctx.ContextError }
        }
        Update-ArtworkSelection
    }
    function Set-ArtworkBusy([bool]$Busy) {
        $locked=$Busy -and $ctx.Mode -eq 'Recommended'
        $query.Enabled=-not $locked; $kindBox.Enabled=-not $locked; $matches.Enabled=-not $locked
        $assets.Enabled=-not $locked
        $profileBox.Enabled=-not $Busy -and -not $ctx.Applied; $use.Enabled=-not $Busy -and -not $ctx.Pending -and [bool]$ctx.CurrentPath
        $keyBox.Enabled=-not $locked; $forget.Enabled=-not $locked; $remember.Enabled=-not $locked
        $clearArt.Enabled=-not $Busy; Update-ArtworkSelection
    }
    function Clear-ArtworkPreview {
        $ctx.CurrentPath='';$ctx.CurrentAsset=$null;$use.Enabled=$false
        if ($picture.Image) {$picture.Image.Dispose();$picture.Image=$null}
    }
    function Queue-ArtworkRefresh([string]$Action,[int]$Delay=0) {
        $ctx.Generation++;$ctx.Pending=$Action;$ctx.DueAt=[datetime]::UtcNow.AddMilliseconds($Delay)
        if ($ctx.Cancellation) {$ctx.Cancellation.Cancel()}
        Clear-ArtworkPreview
        if ($Action -in @('Search','Match','Category')) {
            $ctx.Loading=$true;$assets.Items.Clear();$thumbs.Images.Clear();$ctx.Loading=$false
        }
        if ($Action -eq 'Search') {
            $ctx.Loading=$true;$matches.Items.Clear();$ctx.Loading=$false
            $ctx.MatchItems=@();$ctx.ConfirmedMatch=$null;$ctx.Sets=@{};$ctx.Selections=@{};$ctx.Applied=$false
        }
        $artStatus.Text='Refreshing artwork...'
        Update-ArtworkSelection
    }
    function Start-ArtworkJob($Operation,$Payload,$Callback) {
        if ($ctx.Worker) { return }
        $ctx.Callback=$Callback; $ctx.Worker=[PowerShell]::Create();$ctx.JobGeneration=$ctx.Generation;$ctx.Mode=$Operation
        $ctx.Cancellation=New-Object Threading.CancellationTokenSource
        $Payload.Cancellation=$ctx.Cancellation
        [void]$ctx.Worker.AddScript({
            param($module,$op,$payload)
            $ErrorActionPreference='Stop'; Import-Module $module -Force
            $value=switch ($op) {
                'Search' { @(Search-ArtworkGames $payload.Query $payload.Key) }
                'Candidates' { Get-ArtworkCandidates $payload.Id $payload.Key $payload.Kind }
                'Image' { Get-CachedArtwork $payload.Asset $payload.Cache }
                'Thumbnails' { @(Get-ArtworkThumbnails $payload.Assets $payload.Cache $payload.Cancellation) }
                'Recommended' {
                    $sets=$payload.Sets
                    if ($sets.Count -lt 5) { $sets=Get-ArtworkCandidates $payload.Id $payload.Key }
                    Get-RecommendedArtwork -Sets $sets -Context $payload.Context -CacheDirectory $payload.Cache
                }
            }
            [pscustomobject]@{Value=$value}
        }).AddArgument((Join-Path $PSScriptRoot 'SteamNite.Artwork.psm1')).AddArgument($Operation).AddArgument($Payload)
        $ctx.Handle=$ctx.Worker.BeginInvoke(); Set-ArtworkBusy $true
    }
    $artTimer=New-Object Windows.Forms.Timer; $artTimer.Interval=150
    $artTimer.Add_Tick({
        if (-not $ctx.Handle) { Process-ArtworkRefresh; return }
        if (-not $ctx.Handle.IsCompleted) {return}
        $current=$ctx.JobGeneration -eq $ctx.Generation
        $callback=$ctx.Callback; $value=$null; $success=$false
        try {
            $result=@($ctx.Worker.EndInvoke($ctx.Handle))
            if ($ctx.Worker.HadErrors -or -not $result.Count) {
                $message=if ($ctx.Worker.Streams.Error.Count) { $ctx.Worker.Streams.Error[0].Exception.GetBaseException().Message } else { 'Artwork request failed.' }
                throw $message
            }
            $value=$result[-1].Value; $success=$true
        } catch { if($current){$artStatus.Text=$_.Exception.GetBaseException().Message} }
        finally { $ctx.Worker.Dispose();$ctx.Cancellation.Dispose();$ctx.Cancellation=$null; $ctx.Worker=$null; $ctx.Handle=$null; $ctx.Callback=$null }
        try { if ($success -and $current) { & $callback $value } } catch { $artStatus.Text=$_.Exception.GetBaseException().Message }
        Process-ArtworkRefresh
        Set-ArtworkBusy ([bool]$ctx.Worker)
    })
    function Add-ArtworkThumbnail([string]$Path) {
        $tile=New-Object Drawing.Bitmap(144,184)
        $graphics=[Drawing.Graphics]::FromImage($tile)
        try {
            $graphics.Clear([Drawing.Color]::FromArgb(38,43,52))
            if ($Path) {
                $image=[Drawing.Image]::FromFile($Path)
                try {
                    $scale=[Math]::Min(136.0/$image.Width,176.0/$image.Height)
                    $width=[int]($image.Width*$scale);$height=[int]($image.Height*$scale)
                    $graphics.InterpolationMode='HighQualityBicubic'
                    $graphics.DrawImage($image,[int]((144-$width)/2),[int]((184-$height)/2),$width,$height)
                } finally { $image.Dispose() }
            }
            $index=$thumbs.Images.Count; $thumbs.Images.Add($tile); return $index
        } finally { $graphics.Dispose(); $tile.Dispose() }
    }
    function Populate-ArtworkChoices {
        $ctx.CurrentPath=''; $ctx.CurrentAsset=$null; $use.Enabled=$false
        if ($picture.Image) { $picture.Image.Dispose(); $picture.Image=$null }
        $ctx.Loading=$true; $assets.Items.Clear(); $thumbs.Images.Clear(); $ctx.CurrentAssets=@()
        $kind=[string]$kindBox.SelectedItem
        if ($ctx.Sets.ContainsKey($kind)) { $ctx.CurrentAssets=@($ctx.Sets[$kind]) }
        $rank=0
        foreach ($asset in $ctx.CurrentAssets) {
            $rank++
            $label=if($rank -eq 1){'Recommended'}else{'Rank '+$rank}
            $item=New-Object Windows.Forms.ListViewItem(($label+"`n"+$asset.author.name))
            $item.Tag=$asset; $item.ImageIndex=Add-ArtworkThumbnail ''
            $item.ToolTipText=('#{0} | {1}x{2} | {3} | SteamGridDB rank {4}' -f $asset.id,$asset.width,$asset.height,$asset.author.name,$rank)
            [void]$assets.Items.Add($item)
        }
        $ctx.Loading=$false
        $artStatus.Text=if ($ctx.CurrentAssets.Count) { 'Select an image to preview it, then click Use this image.' } else { 'No supported static PNG/JPEG images found for this artwork type. Try another type or game match.' }
        if ($ctx.CurrentAssets.Count -gt 0 -and -not $ctx.Worker) {
            $artStatus.Text='Loading thumbnail grid... Recommendations follow SteamGridDB ranking; existing artwork will be preserved.'
            Start-ArtworkJob 'Thumbnails' @{Assets=$ctx.CurrentAssets;Cache=(Join-Path $script:dataDir 'artwork-cache')} {
                param($value)
                foreach ($thumbnail in @($value)) {
                    if (-not $thumbnail.Path) { continue }
                    foreach ($item in $assets.Items) { if ($item.Tag.id -eq $thumbnail.Id) { $item.ImageIndex=Add-ArtworkThumbnail $thumbnail.Path;break } }
                }
                $artStatus.Text="Choose artwork from the grid, or exit Steam and click Fill missing recommended to fill this game's missing categories."
            }
        }
    }
    function Begin-AutomaticArtworkSearch {
        try {
            if ($remember.Checked) { Set-ArtworkApiKey $script:dataDir $keyBox.Text }
            else { Remove-ArtworkApiKey $script:dataDir }
            $ctx.Sets=@{}; $ctx.Selections=@{}; $ctx.ConfirmedMatch=$null; $ctx.Applied=$false; $ctx.MatchItems=@()
            $ctx.Loading=$true;$matches.Items.Clear();$ctx.Loading=$false; Update-ArtworkSelection
            $artStatus.Text='Searching SteamGridDB...'
            Start-ArtworkJob 'Search' @{Query=$query.Text;Key=$keyBox.Text} {
                param($value)
                $ctx.MatchItems=@($value)
                $ctx.Loading=$true
                foreach ($match in $ctx.MatchItems) { [void]$matches.Items.Add(('{0}  [SGDB {1}]' -f $match.name,$match.id)) }
                $savedId=0
                if ($ctx.Steam) {
                    $savedPath=Join-Path $script:dataDir ('artwork-'+$ctx.Steam.AppId+'.json')
                    try {if(Test-Path -LiteralPath $savedPath){$saved=Get-Content -LiteralPath $savedPath -Raw -Encoding UTF8|ConvertFrom-Json;if($saved.GameId -eq $Game.Id){$savedId=[long]$saved.SgdbId}}}catch{}
                }
                $matches.SelectedIndex=Get-LikelyArtworkMatchIndex $query.Text $ctx.MatchItems $savedId
                $ctx.Loading=$false
                if ($matches.SelectedIndex -ge 0) {Queue-ArtworkRefresh 'Match'}
                else {$artStatus.Text='No matches. Edit the search title to try again.'}
            }
        } catch { $artStatus.Text=$_.Exception.GetBaseException().Message }
    }
    function Begin-AutomaticArtworkMatch {
        if ($matches.SelectedIndex -lt 0) { return }
        $ctx.ConfirmedMatch=$ctx.MatchItems[$matches.SelectedIndex]; $ctx.Sets=@{}; $ctx.Selections=@{}; $ctx.Applied=$false
        Update-ArtworkSelection
        Begin-AutomaticArtworkCategory
    }
    function Begin-AutomaticArtworkCategory {
        if (-not $ctx.ConfirmedMatch) {return}
        $artStatus.Text='Loading artwork choices for '+$ctx.ConfirmedMatch.name+'...'
        $kind=[string]$kindBox.SelectedItem
        if($ctx.Sets.ContainsKey($kind)){Populate-ArtworkChoices;return}
        Start-ArtworkJob 'Candidates' @{Id=$ctx.ConfirmedMatch.id;Key=$keyBox.Text;Kind=$kind} {param($value) foreach($key in $value.Keys){$ctx.Sets[$key]=$value[$key]};Populate-ArtworkChoices}
    }
    function Process-ArtworkRefresh {
        if($ctx.Worker -or -not $ctx.Pending -or [datetime]::UtcNow -lt $ctx.DueAt){return}
        $action=$ctx.Pending;$ctx.Pending=''
        if([string]::IsNullOrWhiteSpace($keyBox.Text)){$artStatus.Text='Paste your SteamGridDB key to load artwork automatically.';return}
        switch($action){
            'Search' {if([string]::IsNullOrWhiteSpace($query.Text)){$artStatus.Text='Enter a game title.'}else{Begin-AutomaticArtworkSearch}}
            'Match' {Begin-AutomaticArtworkMatch}
            'Category' {Begin-AutomaticArtworkCategory}
            'Image' {Begin-ArtworkImagePreview}
        }
    }
    $matches.Add_SelectedIndexChanged({if(-not $ctx.Loading -and $matches.SelectedIndex -ge 0){Queue-ArtworkRefresh 'Match'}})
    $query.Add_TextChanged({Queue-ArtworkRefresh 'Search' 450})
    $keyBox.Add_TextChanged({Queue-ArtworkRefresh 'Search' 650})
    $kindBox.Add_SelectedIndexChanged({ if (-not $ctx.Loading) { if($ctx.Pending -notin @('Search','Match') -and $ctx.Mode -ne 'Search'){Queue-ArtworkRefresh 'Category'} } })
    $assets.Add_SelectedIndexChanged({
        if ($ctx.Loading -or -not $assets.SelectedItems.Count) { return }
        Queue-ArtworkRefresh 'Image'
    })
    function Begin-ArtworkImagePreview {
        if(-not $assets.SelectedItems.Count){return}
        $ctx.CurrentAsset=$assets.SelectedItems[0].Tag
        $artStatus.Text='Downloading preview...'
        Start-ArtworkJob 'Image' @{Asset=$ctx.CurrentAsset;Cache=(Join-Path $script:dataDir 'artwork-cache')} {
            param($value)
            $ctx.CurrentPath=[string]$value
            $image=[Drawing.Image]::FromFile($ctx.CurrentPath)
            try { $picture.Image=New-Object Drawing.Bitmap($image) } finally { $image.Dispose() }
            $artStatus.Text='Preview: '+$ctx.ConfirmedMatch.name+' / '+$kindBox.SelectedItem+' / by '+$ctx.CurrentAsset.author.name+'. Click Use this image to select it.'
        }
    }
    $use.Add_Click({
        if (-not $ctx.CurrentPath) { return }
        $ctx.Selections[[string]$kindBox.SelectedItem]=[pscustomobject]@{Path=$ctx.CurrentPath;AssetId=$ctx.CurrentAsset.id;Url=$ctx.CurrentAsset.url;Author=$ctx.CurrentAsset.author.name}
        Update-ArtworkSelection
        $artStatus.Text='Image queued. Apply selections will add or replace only the categories you selected; originals are backed up.'
    })
    $profileBox.Add_SelectedIndexChanged({ Refresh-ArtworkContext })
    if($PreferredProfile){for($i=0;$i -lt $profiles.Count;$i++){if($profiles[$i].ShortcutPath -eq $PreferredProfile.ShortcutPath){$profileBox.SelectedIndex=$i;break}}}
    if($profileBox.SelectedIndex -lt 0 -and $profiles.Count -eq 1){$profileBox.SelectedIndex=0}
    function Complete-ArtworkApply {
            param([switch]$FillMissing)
            Remember-SteamAccount $ctx.Steam.Profile
            if(-not (Confirm-SteamClosed -Owner $window -Profile $ctx.Steam.Profile -Action ('save artwork for '+$Game.Title))){$artStatus.Text='Cancelled. Your artwork choices are still selected.';return}
            $freshContext=Get-SteamArtworkContext $ctx.Steam.Profile $Game
            if($freshContext.AppId -ne $ctx.Steam.AppId){throw 'The Steam shortcut changed while exiting. Reopen the artwork window to review it.'}
            $ctx.Steam=$freshContext
            $result=Save-SteamArtwork -Context $ctx.Steam -Selections $ctx.Selections -Replace:(-not $FillMissing)
            $ctx.Applied=$false; $applyArt.Enabled=$false
            $artStatus.Text='Added: '+($result.Added -join ', ')+'. Replaced: '+($result.Replaced -join ', ')+'. Reopen Steam to load artwork.'
            if($result.ArtworkBackupPath){$artStatus.Text+="`r`nPrevious artwork backup: "+$result.ArtworkBackupPath}
            if ($result.BackupPath) { $artStatus.Text+="`r`nIcon shortcut backup: "+$result.BackupPath }
            # Persist only confirmed public match/asset identifiers, never the API key.
            $record=@{GameId=$Game.Id;SteamAppId=$ctx.Steam.AppId;SgdbId=$ctx.ConfirmedMatch.id;SgdbTitle=$ctx.ConfirmedMatch.name;Assets=$ctx.Selections;AppliedAt=(Get-Date).ToString('o')}
            $record | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $script:dataDir ('artwork-'+$ctx.Steam.AppId+'.json')) -Encoding UTF8
            $ctx.Selections=@{}
            Refresh-ArtworkContext
    }
    $applyArt.Add_Click({
        try { Complete-ArtworkApply } catch { $artStatus.Text=$_.Exception.GetBaseException().Message }
    })
    $recommend.Add_Click({
        try {
            if(-not (Confirm-SteamClosed -Owner $window -Profile $ctx.Steam.Profile -Action ('apply recommended artwork for '+$Game.Title))){$artStatus.Text='Cancelled. No artwork was changed.';return}
            if ($remember.Checked) { Set-ArtworkApiKey $script:dataDir $keyBox.Text }
            $match=$ctx.MatchItems[$matches.SelectedIndex]
            if (-not $ctx.ConfirmedMatch -or $ctx.ConfirmedMatch.id -ne $match.id) { $ctx.Sets=@{} }
            $ctx.ConfirmedMatch=$match
            $artStatus.Text='Downloading recommended artwork for '+$match.name+'... Existing artwork will be preserved.'
            Start-ArtworkJob 'Recommended' @{Id=$match.id;Key=$keyBox.Text;Sets=$ctx.Sets;Context=$ctx.Steam;Cache=(Join-Path $script:dataDir 'artwork-cache')} {
                param($value)
                $ctx.Selections=$value.Selections
                if ($ctx.Selections.Count -eq 0) {
                    $artStatus.Text='No artwork to add. Existing slots: '+($value.Preserved -join ', ')+'. Unavailable: '+($value.Unavailable -join ', ')
                } else {
                    Complete-ArtworkApply -FillMissing
                    if ($value.Unavailable.Count) { $artStatus.Text+=' Unavailable: '+($value.Unavailable -join ', ')+'.' }
                }
                Update-ArtworkSelection
            }
        } catch { $artStatus.Text=$_.Exception.GetBaseException().Message }
    })
    $showCurrent.Add_Click({
        try{
            if(-not $ctx.Steam){return}
            Clear-ArtworkPreview
            $assets.SelectedItems.Clear()
            $kind=[string]$kindBox.SelectedItem
            $paths=@(Get-ExistingArtwork $ctx.Steam $kind)
            $path=if($paths.Count){$paths[0]}elseif($kind -eq 'Icon'){$ctx.Steam.Icon.Trim('"')}else{''}
            if(-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'No viewable current image is available for this category.'}
            $image=[Drawing.Image]::FromFile($path)
            try{if($picture.Image){$picture.Image.Dispose()};$picture.Image=New-Object Drawing.Bitmap($image)}finally{$image.Dispose()}
            $artStatus.Text='Current '+$kind+' artwork. Select a grid image and use Apply selections to replace it.'
        }catch{$artStatus.Text='Current artwork cannot be previewed: '+$_.Exception.GetBaseException().Message}
    })
    $clearArt.Add_Click({ $ctx.Selections=@{}; Update-ArtworkSelection; $artStatus.Text='Choices cleared. Steam artwork has not been changed.' })
    $keyLink.Add_Click({ Start-Process 'https://www.steamgriddb.com/profile/preferences/api' })
    $forget.Add_Click({ Remove-ArtworkApiKey $script:dataDir; $keyBox.Clear(); $remember.Checked=$false; $artStatus.Text='Saved API key removed. Enter a key to search again.' })
    $closeArt.Add_Click({ $window.Close() })
    $openSteam.Add_Click({try{Open-SteamClient $profiles[$profileBox.SelectedIndex]}catch{$artStatus.Text=$_.Exception.Message}})
    Set-SteamNiteTheme $window
    $artTimer.Start(); Update-ArtworkSelection
    $window.Add_Shown({Queue-ArtworkRefresh 'Search'})
    try {
        if ($SmokeTest) { 'Artwork UI construction passed.' }
        else { [void]$window.ShowDialog($form) }
    } finally {
        $artTimer.Stop(); $artTimer.Dispose()
        if($ctx.Cancellation){$ctx.Cancellation.Cancel()}
        if ($ctx.Worker) { $ctx.Worker.Stop(); $ctx.Worker.Dispose() }
        if($ctx.Cancellation){$ctx.Cancellation.Dispose()}
        if ($picture.Image) { $picture.Image.Dispose() }
        $thumbs.Dispose()
        $keyBox.Clear(); $window.Dispose()
    }
}
