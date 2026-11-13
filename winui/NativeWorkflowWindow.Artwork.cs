using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
namespace SteamNite.WinUI;

public sealed partial class NativeWorkflowWindow
{
    readonly ContentControl artHeaderHost = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch, Visibility = Visibility.Collapsed };
    readonly ComboBox matches = new() { Header = "Game match", DisplayMemberPath = "Name", HorizontalAlignment = HorizontalAlignment.Stretch };
    readonly ComboBox category = new() { ItemsSource = new[] { "Cover", "Wide", "Hero", "Logo", "Icon" }, SelectedIndex = 0 };
    readonly TextBox query = new() { Header = "Search title", HorizontalAlignment = HorizontalAlignment.Stretch };
    readonly GridView artwork = new() { SelectionMode = ListViewSelectionMode.Single };
    readonly Image previewImage = new() { Stretch = Stretch.Uniform, MaxHeight = 480, HorizontalAlignment = HorizontalAlignment.Stretch };
    readonly TextBlock artCoverage = new() { Foreground = Brush("QuietText"), FontSize = 11 };
    readonly TextBlock queued = new() { Foreground = Brush("Accent"), FontSize = 12, TextWrapping = TextWrapping.Wrap };
    readonly TextBlock matchSummary = new() { Foreground = Brush("QuietText"), FontSize = 12, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 240 };
    readonly TextBlock previewNote = new() { Foreground = Brush("QuietText"), FontSize = 12, TextWrapping = TextWrapping.Wrap };
    readonly TextBlock artAccount = new() { Foreground = Brush("QuietText"), FontSize = 11 };
    readonly StackPanel artKeyPrompt = new() { Orientation = Orientation.Horizontal, Spacing = 12 };
    readonly List<ToggleButton> artTabs = [];
    readonly List<MenuFlyoutItem> recommendedItems = [];
    readonly List<MenuFlyoutItem> replaceRecommendedItems = [];
    Button? changeMatch, useImage, applyImages, applyRecommended;
    Flyout? matchFlyout;
    long artVersion;
    bool artEventsAttached, hasArtKey, artKeyRequired, editingArtSettings;
    string pendingArtRefresh = "";

    async Task BuildArtworkAsync()
    {
        Header("Artwork", ""); heading.Visibility = Visibility.Collapsed; root.RowSpacing = 12;
        if (artHeaderHost.Parent == null) Place(artHeaderHost, 1);
        artHeaderHost.Visibility = Visibility.Visible;
        Detach(query); Detach(matches); Detach(matchSummary);
        matchFlyout = new Flyout { Content = new StackPanel { Width = 380, Spacing = 12, Children = { query, matches } } };
        changeMatch = new Button { Content = "Change match", Flyout = matchFlyout };
        var overflow = new Button { Content = "⋯", MinWidth = 40 }; AutomationProperties.SetName(overflow, "Artwork options");
        recommendedItems.Clear(); replaceRecommendedItems.Clear(); overflow.Flyout = CreateArtworkMenu();
        var title = new TextBlock { Text = "Artwork", FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        var top = new Grid { ColumnSpacing = 16 };
        top.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        foreach (var _ in Enumerable.Range(0, 3)) top.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        top.Children.Add(title); Grid.SetColumn(matchSummary, 1); top.Children.Add(matchSummary); Grid.SetColumn(changeMatch, 2); top.Children.Add(changeMatch); Grid.SetColumn(overflow, 3); top.Children.Add(overflow); artHeaderHost.Content = top;
        matchSummary.Text = "Finding game match…"; matchSummary.Foreground = Brush("QuietText");

        artTabs.Clear(); var tabs = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var kind in new[] { "Cover", "Wide", "Hero", "Logo", "Icon" }) {
            var tab = new ToggleButton { Tag = kind, Padding = new Thickness(16, 10, 16, 10) };
            tab.Click += (_, _) => { category.SelectedItem = (string)tab.Tag; UpdateArtTabs(); };
            artTabs.Add(tab); tabs.Children.Add(tab);
        }
        options.Children.Add(tabs);
        artwork.ItemsPanel = (ItemsPanelTemplate)XamlReader.Load("<ItemsPanelTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><ItemsWrapGrid Orientation='Horizontal'/></ItemsPanelTemplate>");
        Detach(artwork); Detach(previewImage); Detach(artCoverage); Detach(queued); Detach(previewNote); Detach(artAccount);
        var gallery = new Grid { ColumnSpacing = 24 };
        gallery.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); gallery.ColumnDefinitions.Add(new() { Width = new GridLength(220) });
        gallery.Children.Add(artwork);
        var previewHeader = new Grid { ColumnSpacing = 8 }; previewHeader.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); previewHeader.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); previewHeader.Children.Add(artCoverage); Grid.SetColumn(artAccount, 1); previewHeader.Children.Add(artAccount);
        var side = new ScrollViewer { Content = Stack(previewHeader, previewImage, previewNote, queued), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(side, 1); gallery.Children.Add(side); SetBody(gallery);
        useImage = Action("Use image", async () => {
            if (artwork.SelectedItem is not GridViewItem item || item.Tag is not JsonElement asset) throw new InvalidOperationException("Select an image from the gallery.");
            var result = await service.CallAsync("ArtImage", new { Kind = (string)category.SelectedItem, AssetId = asset.N("Id"), Queue = true });
            UpdateArtState(result.P("State")); status.Text = "Image queued. Apply selections adds or replaces only the categories you chose.";
        }); useImage.IsEnabled = false;
        applyImages = Action("Apply selections", async () => await ApplyArtworkAsync(false), true);
        applyRecommended = new Button { Content = "Apply recommended", IsEnabled = false };
        applyRecommended.Click += async (_, _) => await Run(async () => await ApplyRecommendedAsync(!artState.A("Categories").Any(c => !c.B("Exists"))));
        actions.Children.Add(applyRecommended);
        var more = new Button { Content = "More", Flyout = CreateArtworkMenu() }; actions.Children.Add(more);

        if (!artEventsAttached) {
            artEventsAttached = true;
            query.TextChanged += async (_, _) => { if (!loading) await DebouncedSearchAsync(); };
            key.PasswordChanged += async (_, _) => { if (!loading && !editingArtSettings) await DebouncedSearchAsync(); };
            matches.SelectionChanged += async (_, _) => { if (loading) return; matchFlyout?.Hide(); if (busy) { ++artVersion; pendingArtRefresh = "Category"; } else await Run(LoadCategoryAsync); };
            category.SelectionChanged += async (_, _) => { if (loading) return; UpdateArtTabs(); if (busy) { ++artVersion; pendingArtRefresh = "Category"; } else await Run(LoadCategoryAsync); };
            artwork.SelectionChanged += async (_, _) => { if (loading) return; if (busy) { ++artVersion; pendingArtRefresh = "Image"; } else await Run(PreviewArtImageAsync); };
        }
        if (account.SelectedItem == null) {
            matchSummary.Text = "Choose a Steam account"; status.Text = "Choose the destination account in Artwork settings.";
            var choose = new Button { Content = "Artwork settings…" }; choose.Click += async (_, _) => await Run(ShowArtworkSettingsAsync); options.Children.Add(choose); return;
        }
        artState = await service.CallAsync("ArtContext", new { Ids = ids });
        title.Text = artState.S("Title"); Title = artState.S("Title") + " · Artwork · Oathgate";
        loading = true; query.Text = artState.S("Title"); matches.ItemsSource = null; loading = false;
        UpdateArtState(artState); await ShowCurrentArtworkAsync();
        SetArtKeyRequired(!hasArtKey && key.Password.Length == 0);
        if (!artKeyRequired) await SearchArtworkAsync(); else { matchSummary.Text = "SteamGridDB key needed"; status.Text = "Enter a key to browse artwork. Your current artwork is shown on the right."; }
    }
    MenuFlyout CreateArtworkMenu()
    {
        var menu = new MenuFlyout();
        void Add(string label, Func<Task> callback, bool recommendation = false, bool replacement = false) {
            var item = new MenuFlyoutItem { Text = label, IsEnabled = !recommendation && !replacement }; item.Click += async (_, _) => await Run(callback); menu.Items.Add(item);
            if (recommendation) recommendedItems.Add(item);
            if (replacement) replaceRecommendedItems.Add(item);
        }
        Add("Fill missing recommended", async () => await ApplyArtworkAsync(true), true);
        Add("Replace all with recommended…", async () => await ApplyRecommendedAsync(true), replacement: true);
        Add("Show current artwork", ShowCurrentArtworkAsync);
        Add("Clear choices", async () => UpdateArtState(await service.CallAsync("ArtClear")));
        menu.Items.Add(new MenuFlyoutSeparator());
        Add("Artwork settings…", ShowArtworkSettingsAsync); Add("Open Steam", OpenSteamAsync); Add("Close", () => { CloseIdle(); return Task.CompletedTask; });
        return menu;
    }
    void SetArtKeyRequired(bool required)
    {
        artKeyRequired = required;
        if (editingArtSettings) return;
        if (!required) { options.Children.Remove(artKeyPrompt); Detach(key); Detach(remember); return; }
        Detach(key); Detach(remember); artKeyPrompt.Children.Clear();
        key.Header = "SteamGridDB API key"; key.Width = 280; artKeyPrompt.Children.Add(key); artKeyPrompt.Children.Add(remember);
        var link = new HyperlinkButton { Content = "Get API key", NavigateUri = new Uri("https://www.steamgriddb.com/profile/preferences/api"), VerticalAlignment = VerticalAlignment.Bottom }; artKeyPrompt.Children.Add(link);
        if (!options.Children.Contains(artKeyPrompt)) options.Children.Add(artKeyPrompt);
    }
    async Task ShowArtworkSettingsAsync()
    {
        var originalAccount = account.SelectedIndex; var originalKey = key.Password; var originalRemember = remember.IsChecked; var originalKeyRequired = artKeyRequired;
        bool forgotten = false; editingArtSettings = true;
        Detach(account); Detach(key); Detach(remember); key.Header = "SteamGridDB API key"; key.Width = double.NaN;
        var saved = Text(hasArtKey ? "A saved key is available. Leave the field empty to keep it." : "Enter your API key to browse artwork.", true);
        var content = Stack(account, saved, key, remember);
        content.Children.Add(new HyperlinkButton { Content = "Get a SteamGridDB API key", NavigateUri = new Uri("https://www.steamgriddb.com/profile/preferences/api") });
        var forget = new Button { Content = "Forget saved key" }; content.Children.Add(forget);
        forget.Click += async (_, _) => {
            forget.IsEnabled = false;
            try { await service.CallAsync("Key", new { Forget = true }); forgotten = true; hasArtKey = false; key.Password = ""; key.PlaceholderText = "Paste your API key"; remember.IsChecked = false; saved.Text = "Saved key removed."; }
            catch (Exception error) { saved.Text = error.Message; }
            finally { forget.IsEnabled = true; }
        };
        var dialog = new ContentDialog { Title = "Artwork settings", Content = content, PrimaryButtonText = "Save settings", CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close, XamlRoot = root.XamlRoot, RequestedTheme = ElementTheme.Dark };
        ContentDialogResult result;
        try { result = await dialog.ShowAsync(); }
        finally { Detach(account); Detach(key); Detach(remember); editingArtSettings = false; }
        if (result != ContentDialogResult.Primary) {
            loading = true; account.SelectedIndex = originalAccount; if (!forgotten) { key.Password = originalKey; remember.IsChecked = originalRemember; } loading = false;
            SetArtKeyRequired(forgotten || originalKeyRequired); return;
        }
        if (account.SelectedItem is not ProfileChoice choice) { SetArtKeyRequired(!hasArtKey); throw new InvalidOperationException("Choose a Steam account."); }
        var changedAccount = originalAccount != account.SelectedIndex;
        if (changedAccount) await service.CallAsync("Profile", new { Profile = choice.Path });
        await SaveKeyAsync(); if (key.Password.Length > 0) hasArtKey = true;
        SetArtKeyRequired(!hasArtKey);
        if (changedAccount) await BuildArtworkAsync(); else if (hasArtKey) await SearchArtworkAsync();
    }
    async Task DebouncedSearchAsync()
    {
        var version = ++artVersion; await Task.Delay(500);
        if (version != artVersion || closed || editingArtSettings) return;
        if (busy) { pendingArtRefresh = "Search"; return; } await Run(SearchArtworkAsync);
    }
    async Task SearchArtworkAsync()
    {
        await SaveKeyAsync(); loading = true; matches.ItemsSource = null; loading = false;
        matchSummary.Text = "Searching SteamGridDB…"; matchSummary.Foreground = Brush("QuietText");
        UpdateArtState(await service.CallAsync("ArtClear")); if (useImage != null) useImage.IsEnabled = false; artwork.Items.Clear(); status.Text = "Searching SteamGridDB…";
        var result = await service.CallAsync("ArtSearch", new { Query = query.Text }); hasArtKey = true; SetArtKeyRequired(false);
        loading = true; matches.ItemsSource = result.A("Matches").Select(m => new MatchChoice(m.S("name"), m.N("id"))).ToArray(); matches.SelectedIndex = (int)result.N("Index"); loading = false;
        UpdateArtState(result.P("State"));
        if (matches.SelectedIndex >= 0) await LoadCategoryAsync();
        else { await ShowCurrentArtworkAsync(); matchSummary.Text = "No match found"; matchSummary.Foreground = Brush("Warning"); status.Text = "Edit the search title or choose a different game match."; if (changeMatch != null) matchFlyout?.ShowAt(changeMatch); }
    }
    async Task LoadCategoryAsync()
    {
        if (matches.SelectedItem is not MatchChoice match) return;
        matchSummary.Text = "✓ SteamGridDB · " + match.Name; matchSummary.Foreground = Brush("Success"); ToolTipService.SetToolTip(matchSummary, "Matched to " + match.Name + " on SteamGridDB. Use Change match to correct it.");
        var version = ++artVersion; var kind = (string)category.SelectedItem;
        status.Text = "Loading " + kind + " artwork…";
        var result = await service.CallAsync("ArtCandidates", new { MatchId = match.Id, Kind = kind });
        loading = true; artwork.Items.Clear();
        var rank = 0; var thumbnails = new List<(Image Image, long Id)>();
        foreach (var asset in result.A("Assets")) {
            rank++; var image = new Image { Width = 140, Height = kind == "Cover" ? 210 : kind is "Wide" or "Hero" ? 90 : 120, Stretch = Stretch.Uniform }; thumbnails.Add((image, asset.N("Id")));
            var label = Text(rank == 1 ? "Recommended" : "Rank " + rank); label.FontSize = 13;
            var author = Text(asset.S("Author"), true); author.FontSize = 12; author.TextTrimming = TextTrimming.CharacterEllipsis; author.MaxLines = 1;
            var tile = new Border { Width = 156, Padding = new Thickness(8), Background = Brush("PanelSurface"), CornerRadius = new CornerRadius(8), Child = new StackPanel { Spacing = 8, Children = { image, label, author } } };
            var item = new GridViewItem { Content = tile, Tag = asset, Padding = new Thickness(0), Margin = new Thickness(0, 0, 12, 12) }; AutomationProperties.SetName(item, (rank == 1 ? "Recommended" : "Rank " + rank) + " by " + asset.S("Author")); artwork.Items.Add(item);
        }
        loading = false; if (useImage != null) useImage.IsEnabled = false; UpdateArtState(result.P("State")); await ShowCurrentArtworkAsync();
        optionsHost.IsEnabled = true; artHeaderHost.IsEnabled = true; account.IsEnabled = false; body.IsEnabled = true;
        foreach (var thumbnail in thumbnails) {
            if (version != artVersion) return; status.Text = "Loading previews…";
            var image = await service.CallAsync("ArtThumbnail", new { Kind = kind, AssetId = thumbnail.Id }); if (version != artVersion) return;
            thumbnail.Image.Source = await LoadImageAsync(image.S("Path"));
        }
        status.Text = rank == 0 ? "No supported images for this category. Try another category or match." : "";
    }
    async Task ShowCurrentArtworkAsync()
    {
        loading = true; artwork.SelectedItem = null; loading = false;
        if (useImage != null) useImage.IsEnabled = false;
        var kind = (string)category.SelectedItem; var current = artState.A("Categories").FirstOrDefault(c => c.S("Kind") == kind);
        artCoverage.Text = "CURRENT " + kind.ToUpperInvariant(); previewImage.Source = await LoadImageAsync(current.S("Path"));
        previewNote.Text = previewImage.Source != null ? "Choose a gallery image to compare and replace this artwork." : current.B("Exists") ? "Current artwork exists, but this format cannot be previewed." : "No current artwork. Choose an image from the gallery.";
    }
    async Task PreviewArtImageAsync()
    {
        if (artwork.SelectedItem is not GridViewItem item || item.Tag is not JsonElement asset) return;
        var image = await service.CallAsync("ArtImage", new { Kind = (string)category.SelectedItem, AssetId = asset.N("Id") });
        previewImage.Source = await LoadImageAsync(image.S("Path")); if (useImage != null) useImage.IsEnabled = true;
        artCoverage.Text = "CANDIDATE " + ((string)category.SelectedItem).ToUpperInvariant(); previewNote.Text = asset.S("Author") + " · " + asset.N("Width") + " × " + asset.N("Height"); status.Text = "Use image to queue this choice.";
    }
    void UpdateArtTabs()
    {
        foreach (var tab in artTabs) {
            var kind = (string)tab.Tag; var state = artState.A("Categories").FirstOrDefault(c => c.S("Kind") == kind); var isQueued = state.B("Queued"); var active = (string)category.SelectedItem == kind;
            var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            line.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 6, Height = 6, Fill = Brush(active ? "AppSurface" : isQueued ? "Accent" : state.B("Exists") ? "Success" : "Warning") }); line.Children.Add(new TextBlock { Text = kind });
            if (isQueued) line.Children.Add(new TextBlock { Text = "Queued", FontSize = 10, Foreground = Brush(active ? "AppSurface" : "Accent"), VerticalAlignment = VerticalAlignment.Center });
            tab.Content = line; tab.IsChecked = active;
            AutomationProperties.SetName(tab, kind + (state.B("Exists") ? ", current artwork" : ", missing artwork") + (isQueued ? ", queued" : ""));
            ToolTipService.SetToolTip(tab, kind + (state.B("Exists") ? " · current artwork" : " · missing artwork") + (isQueued ? " · queued for apply" : ""));
        }
    }
    void UpdateArtState(JsonElement state)
    {
        artState = state; UpdateArtTabs(); var count = state.A("Queued").Length;
        queued.Text = count == 0 ? "" : count + " " + (count == 1 ? "category queued" : "categories queued");
        artAccount.Text = "Steam · " + state.S("AccountId"); ToolTipService.SetToolTip(artAccount, state.S("ProfileLabel"));
        if (applyImages != null) { applyImages.IsEnabled = count > 0; applyImages.Content = count > 0 ? $"Apply selections ({count})" : "Apply selections"; }
        foreach (var item in recommendedItems) item.IsEnabled = matches.SelectedItem != null && state.A("Categories").Any(c => !c.B("Exists"));
        foreach (var item in replaceRecommendedItems) item.IsEnabled = matches.SelectedItem != null;
        if (applyRecommended != null) {
            applyRecommended.IsEnabled = matches.SelectedItem != null;
            ToolTipService.SetToolTip(applyRecommended, state.A("Categories").Any(c => !c.B("Exists")) ? "Fill missing categories with SteamGridDB’s highest-ranked available art. Existing artwork is preserved." : "All categories are filled. Review replacement with recommended artwork; originals are backed up.");
        }
    }
    async Task ApplyRecommendedAsync(bool replaceAll)
    {
        if (replaceAll && !await ConfirmAsync("Replace with recommended artwork?", "Use SteamGridDB’s highest-ranked available image for each of the five categories?\n\nCurrent artwork will be backed up before replacement. Categories without a usable recommendation will be preserved.\n\n" + artState.S("ProfileLabel"), "Apply recommended")) return;
        await ApplyArtworkAsync(!replaceAll, replaceAll);
    }
    async Task ApplyArtworkAsync(bool missingOnly, bool recommendAll = false)
    {
        await SaveKeyAsync(); if (!await EnsureSteamClosedAsync()) return;
        var result = await service.CallAsync("ArtApply", new { Fill = missingOnly, RecommendAll = recommendAll, ConfirmRecommended = recommendAll }); UpdateArtState(result.P("State")); await ShowCurrentArtworkAsync();
        var saved = result.P("Result"); status.Text = "Added: " + string.Join(", ", saved.A("Added").Select(x => x.GetString())) + ". Replaced: " + string.Join(", ", saved.A("Replaced").Select(x => x.GetString())) + ". Reopen Steam to load artwork.";
        if (saved.S("ArtworkBackupPath") != "") status.Text += "\nArtwork backup: " + saved.S("ArtworkBackupPath");
        if (saved.S("BackupPath") != "") status.Text += "\nShortcut backup: " + saved.S("BackupPath");
        if (result.A("Unavailable").Length > 0) status.Text += "\nUnavailable: " + string.Join(", ", result.A("Unavailable").Select(x => x.GetString()));
    }
    static async Task<BitmapImage?> LoadImageAsync(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        try { var file = await StorageFile.GetFileFromPathAsync(path); using var stream = await file.OpenReadAsync(); var image = new BitmapImage(); await image.SetSourceAsync(stream); return image; } catch { return null; }
    }
    sealed record MatchChoice(string Name, long Id);
}
