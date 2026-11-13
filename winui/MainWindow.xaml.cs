using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using System.Diagnostics;
namespace SteamNite.WinUI;
public sealed partial class MainWindow : Window
{
    private readonly BackendClient backend;
    private readonly CancellationTokenSource lifetime = new();
    private LibrarySnapshot snapshot = new();
    private string filter = "All", platform = "All platforms";
    private bool busy, acting, restoringSelection;
    private readonly List<(MenuFlyoutItem Item, string Action)> selectionMenuItems = [];
    private readonly Dictionary<string, (long Stamp, long Length, BitmapImage Image)> covers = new(StringComparer.OrdinalIgnoreCase);
    private CancellationTokenSource? coverLoading;
    public MainWindow()
    {
        InitializeComponent();
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "oathgate.ico"));
        GameList.ContextFlyout = CreateSelectionMenu();
        SelectionMoreButton.Flyout = CreateSelectionMenu();
        ExtendsContentIntoTitleBar = true; SetTitleBar(DragRegion);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 900));
        if (AppWindow.Presenter is OverlappedPresenter presenter) { presenter.PreferredMinimumWidth = 1120; presenter.PreferredMinimumHeight = 680; }
        AppWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
        AppWindow.TitleBar.ButtonForegroundColor = Colors.White;
        backend = new BackendClient();
        Closed += (_, _) => { lifetime.Cancel(); coverLoading?.Cancel(); coverLoading?.Dispose(); };
        AppWindow.Closing += (_, args) => { if (acting) { args.Cancel = true; Footer.Text = "Finish or cancel the open workflow before closing Oathgate."; } };
        Root.Loaded += async (_, _) => {
            if (AppWindow.Presenter is OverlappedPresenter p) { p.PreferredMinimumWidth = (int)Math.Ceiling(1120 * Root.XamlRoot.RasterizationScale); p.PreferredMinimumHeight = (int)Math.Ceiling(680 * Root.XamlRoot.RasterizationScale); }
            await ScanAsync();
        };
    }
    private async Task ScanAsync()
    {
        if (busy) return;
        busy = true; RescanButton.IsEnabled = false; Loading.IsActive = true; UpdateActions();
        Summary.Text = "Finding installed games and checking Steam…";
        try
        {
            snapshot = await backend.ScanAsync(lifetime.Token);
            ApplyFilters();
            coverLoading?.Cancel(); coverLoading?.Dispose(); coverLoading = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            _ = LoadCoversAsync(snapshot.Games, coverLoading.Token);
            NoticeButton.Content = snapshot.Notices.Length == 0 ? "No scan notices" : $"{snapshot.Notices.Length} scan notices";
            Footer.Text = "Ready · select games to prepare, launch or update artwork";
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { Summary.Text = "Could not refresh the library"; Footer.Text = error.Message; }
        finally { busy = false; RescanButton.IsEnabled = !acting; Loading.IsActive = false; UpdateActions(); }
    }
    private async Task LoadCoversAsync(GameEntry[] games, CancellationToken cancellation)
    {
        using var throttle = new SemaphoreSlim(4);
        if (covers.Count > 256) covers.Clear();
        await Task.WhenAll(games.Select(async game => {
            if (string.IsNullOrWhiteSpace(game.CoverPath)) return;
            bool entered = false;
            try {
                await throttle.WaitAsync(cancellation); entered = true; cancellation.ThrowIfCancellationRequested();
                var info = new FileInfo(game.CoverPath); var stamp = info.LastWriteTimeUtc.Ticks; var length = info.Length;
                if (covers.TryGetValue(game.CoverPath, out var cached) && cached.Stamp == stamp && cached.Length == length) { game.Cover = cached.Image; return; }
                var file = await StorageFile.GetFileFromPathAsync(game.CoverPath); using var stream = await file.OpenReadAsync();
                var bitmap = new BitmapImage { DecodePixelWidth = 72 }; await bitmap.SetSourceAsync(stream); cancellation.ThrowIfCancellationRequested();
                covers[game.CoverPath] = (stamp, length, bitmap); game.Cover = bitmap;
            } catch (Exception) { /* Missing covers or a superseded scan must not block the library. */ }
            finally { if (entered) throttle.Release(); }
        }));
    }
    private void ApplyFilters()
    {
        if (GameList == null) return;
        var selectedIds = GameList.SelectedItems.Cast<GameEntry>().Select(g => g.Id).ToHashSet();
        var games = snapshot.Games.Where(g => string.IsNullOrWhiteSpace(Search.Text) || g.Title.Contains(Search.Text, StringComparison.OrdinalIgnoreCase))
            .Where(g => platform == "All platforms" || g.Platform == platform)
            .Where(g => filter switch { "Attention" => g.NeedsAttention, "Unsynced" => g.SteamSyncStatus == "Not synced" && !g.Ignored, "Artwork" => g.InstallState == "Installed" && g.MissingArtwork.Length > 0 && !g.Ignored, "Installed" => g.InstallState == "Installed", "Not installed" => g.InstallState == "Not installed", "Steam only" => g.InstallState != "Installed", "Needs repair" => g.SteamSyncStatus == "Needs repair" && !g.Ignored, "Ignored" => g.Ignored, _ => true }).ToArray();
        restoringSelection = true;
        try {
            GameList.ItemsSource = games;
            foreach (var game in games.Where(g => selectedIds.Contains(g.Id))) GameList.SelectedItems.Add(game);
        } finally { restoringSelection = false; }
        UpdateSelectionDetails(); UpdateActions();
        EmptyState.Visibility = games.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        Summary.Text = $"{snapshot.Games.Count(g => g.InstallState == "Installed")} installed  ·  {snapshot.Games.Count(g => g.NeedsAttention)} need attention  ·  {games.Length} shown";
    }
    private void Filter_Click(object sender, RoutedEventArgs e)
    {
        filter = (string)((ToggleButton)sender).Tag;
        foreach (var chip in new[] { AllChip, AttentionChip, UnsyncedChip, ArtworkChip }) chip.IsChecked = (string)chip.Tag == filter;
        ApplyFilters();
        UpdateFilterLabel();
    }
    private void State_Click(object sender, RoutedEventArgs e) { filter = (string)((MenuFlyoutItem)sender).Tag; foreach (var chip in new[] { AllChip, AttentionChip, UnsyncedChip, ArtworkChip }) chip.IsChecked = (string)chip.Tag == filter; ApplyFilters(); UpdateFilterLabel(); }
    private void UpdateFilterLabel() { var labels = new List<string>(); if (platform != "All platforms") labels.Add(platform); if (filter is not ("All" or "Attention" or "Unsynced" or "Artwork")) labels.Add(filter); PlatformButton.Content = labels.Count == 0 ? "More filters" : string.Join(" · ", labels); }
    private void Platform_Click(object sender, RoutedEventArgs e) { platform = ((MenuFlyoutItem)sender).Text; UpdateFilterLabel(); ApplyFilters(); }
    private void ClearFilters_Click(object sender, RoutedEventArgs e) { filter = "All"; platform = "All platforms"; Search.Text = ""; foreach (var chip in new[] { AllChip, AttentionChip, UnsyncedChip, ArtworkChip }) chip.IsChecked = chip == AllChip; ApplyFilters(); UpdateFilterLabel(); }
    private void Search_Changed(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => ApplyFilters();
    private void Game_Selected(object sender, SelectionChangedEventArgs e)
    {
        if (restoringSelection) return;
        UpdateSelectionDetails(); UpdateActions();
    }
    private GameEntry[] SelectedGames => GameList.SelectedItems.Cast<GameEntry>().ToArray();
    private void UpdateSelectionDetails()
    {
        var selected = SelectedGames;
        var selectedIds = selected.Select(g => g.Id).ToHashSet();
        foreach (var game in GameList.Items.Cast<GameEntry>()) game.IsSelected = selectedIds.Contains(game.Id);
        SelectionSummary.Text = $"{selected.Length} of {GameList.Items.Count} shown selected";
        SelectAllCheck.IsChecked = LibraryPresentation.SelectAllState(GameList.Items.Count, selected.Length);
    }
    private void Game_CheckClicked(object sender, RoutedEventArgs e)
    {
        if (busy || acting || sender is not CheckBox check || check.DataContext is not GameEntry game) return;
        if (check.IsChecked == true) { if (!GameList.SelectedItems.Contains(game)) GameList.SelectedItems.Add(game); }
        else GameList.SelectedItems.Remove(game);
        UpdateSelectionDetails(); UpdateActions();
    }
    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        if (busy || acting) return;
        restoringSelection = true;
        try { if (GameList.Items.Count > 0 && GameList.SelectedItems.Count == GameList.Items.Count) GameList.SelectedItems.Clear(); else GameList.SelectAll(); }
        finally { restoringSelection = false; }
        UpdateSelectionDetails(); UpdateActions();
    }
    private void UpdateActions()
    {
        if (PrepareButton == null || GameList == null) return;
        var selected = SelectedGames; var idle = !busy && !acting;
        var installed = selected.Length > 0 && selected.All(g => g.InstallState == "Installed");
        var one = selected.Length == 1; var game = one ? selected[0] : null;
        PrepareButton.IsEnabled = idle && installed;
        LaunchButton.IsEnabled = idle && one && installed && game!.Status == "Ready to test";
        ArtworkButton.IsEnabled = idle && one && installed && !game!.Ignored;
        var unignore = selected.Length > 0 && selected.All(g => g.Ignored);
        foreach (var (item, action) in selectionMenuItems) {
            item.IsEnabled = idle && (action switch {
                "EditLaunch" => one && installed,
                "Shortcuts" => installed && selected.All(g => !g.Ignored),
                "OpenFolder" => one && Directory.Exists(game!.InstallPath),
                "Copy" or "Details" => one,
                "Ignore" => selected.Length > 0 && selected.All(g => !string.IsNullOrEmpty(g.NativeGameId)),
                "Remove" => selected.Length > 0 && selected.All(g => g.CanRemoveExplicitly && !g.Ignored),
                _ => false
            });
            if (action == "Ignore") { item.Text = unignore ? "Unignore selected" : "Ignore selected"; item.Tag = unignore ? "Unignore" : "Ignore"; }
        }
        SelectionMoreButton.IsEnabled = idle && selected.Length > 0;
        SelectAllCheck.IsEnabled = idle && GameList.Items.Count > 0;
        MoreButton.IsEnabled = idle; GameList.IsEnabled = idle;
    }
    private MenuFlyout CreateSelectionMenu()
    {
        var menu = new MenuFlyout(); menu.Opening += GameMenu_Opening;
        foreach (var (label, action) in new[] { ("Game details…", "Details"), ("Edit launch…", "EditLaunch"), ("Open installation folder", "OpenFolder"), ("Copy details", "Copy"), ("Shortcuts only…", "Shortcuts"), ("Ignore selected", "Ignore"), ("Remove from Steam…", "Remove") }) {
            if (action == "Remove") menu.Items.Add(new MenuFlyoutSeparator());
            var item = new MenuFlyoutItem { Text = label, Tag = action };
            if (action == "Remove") item.Foreground = (SolidColorBrush)Application.Current.Resources["Danger"];
            if (action == "Details") item.Click += Details_Click;
            else if (action == "OpenFolder") item.Click += OpenFolder_Click;
            else if (action == "Copy") item.Click += Copy_Click;
            else item.Click += SelectionWorkflow_Click;
            selectionMenuItems.Add((item, action)); menu.Items.Add(item);
        }
        return menu;
    }
    private async void Details_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedGames.Length != 1) return; var game = SelectedGames[0];
        await MessageAsync(game.Title, $"{game.Platform} · {game.InstallState} · {game.SteamSyncStatus}\nArtwork: {game.ArtworkStatus}\n\n{game.AttentionDetail}\n\nLaunch: {game.Method}\n{game.Target}\n\nInstall folder: {game.InstallPath}\n\nSteam: {game.SteamSyncDetail}\n\nArtwork: {game.ArtworkDetail}");
    }
    private void GameMenu_Opening(object? sender, object e) => UpdateActions();
    private void Game_RightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        var node = e.OriginalSource as DependencyObject; GameEntry? game = null;
        while (node != null && node != GameList) { if (node is FrameworkElement element && element.DataContext is GameEntry entry) { game = entry; break; } node = VisualTreeHelper.GetParent(node); }
        if (game == null) { GameList.SelectedItems.Clear(); e.Handled = true; return; }
        if (!GameList.SelectedItems.Contains(game)) { GameList.SelectedItems.Clear(); GameList.SelectedItems.Add(game); }
        UpdateActions();
    }
    private async void Game_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        var node = e.OriginalSource as DependencyObject;
        GameEntry? clicked = null;
        while (node != null && node != GameList) {
            if (node is CheckBox) return;
            if (node is FrameworkElement element && element.DataContext is GameEntry game) clicked ??= game;
            node = VisualTreeHelper.GetParent(node);
        }
        if (clicked != null && LaunchButton.IsEnabled && SelectedGames[0].Id == clicked.Id) await RunWorkflowAsync("Launch", SelectedGames);
    }
    private async void SelectionWorkflow_Click(object sender, RoutedEventArgs e) => await RunWorkflowAsync((string)((FrameworkElement)sender).Tag, SelectedGames);
    private async void GlobalWorkflow_Click(object sender, RoutedEventArgs e) => await RunWorkflowAsync((string)((FrameworkElement)sender).Tag, []);
    private async Task RunWorkflowAsync(string action, GameEntry[] selected)
    {
        if (busy || acting) return;
        acting = true; RescanButton.IsEnabled = false; UpdateActions();
        Footer.Text = "Opening " + action + "… Finish or close its window to return here.";
        try {
            if (action is "Launch" or "Ignore" or "Unignore") {
                await using var service = new NativeBackend(backend.Workspace);
                await service.CallAsync("Setup", new { Profile = snapshot.ProfileShortcutPath });
                await service.CallAsync(action == "Launch" ? "Launch" : "Ignore", new { Ids = selected.Select(g => g.Id).ToArray(), Ignored = action == "Ignore" });
            } else await NativeWorkflowWindow.ShowAsync(backend.Workspace, action, selected.Select(g => g.Id).ToArray(), snapshot.ProfileShortcutPath);
        }
        catch (Exception error) { await MessageAsync("Workflow could not finish", error.Message); }
        finally { acting = false; await ScanAsync(); }
    }
    private async void OpenFolder_Click(object sender, RoutedEventArgs e) { try { if (SelectedGames.Length == 1 && Directory.Exists(SelectedGames[0].InstallPath)) Process.Start(new ProcessStartInfo(SelectedGames[0].InstallPath) { UseShellExecute = true }); } catch (Exception error) { await MessageAsync("Could not open folder", error.Message); } }
    private void Copy_Click(object sender, RoutedEventArgs e) { if (SelectedGames.Length != 1) return; var game = SelectedGames[0]; var data = new DataPackage(); data.SetText($"{game.Title}\n{game.Platform}\n{game.InstallState} | {game.SteamSyncStatus} | Artwork {game.ArtworkStatus}\n{game.Method}\n{game.InstallPath}\n{game.Target}\n{game.AttentionDetail}"); Clipboard.SetContent(data); }
    private async void Rescan_Click(object sender, RoutedEventArgs e) => await ScanAsync();
    private async void Classic_Click(object sender, RoutedEventArgs e) { try { backend.OpenClassic(); } catch (Exception error) { await MessageAsync("Could not open classic app", error.Message); } }
    private async void Notices_Click(object sender, RoutedEventArgs e) => await MessageAsync("Scan details", snapshot.Notices.Length == 0 ? "No scan notices." : string.Join("\n\n", snapshot.Notices));
    private async void About_Click(object sender, RoutedEventArgs e) => await MessageAsync("Oathgate", "Bring your games into Steam.\n\nDiscover games across your stores, prepare Steam shortcuts, and choose artwork for your library.\n\nPreviously SteamNite.\n\nVersion: " + FileVersionInfo.GetVersionInfo(typeof(App).Assembly.Location).ProductVersion + "\n\nAccount: " + snapshot.ProfileLabel);
    private async Task MessageAsync(string title, string text) { var dialog = new ContentDialog { Title = title, Content = new ScrollViewer { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }, MaxHeight = 450 }, CloseButtonText = "Close", XamlRoot = Root.XamlRoot, RequestedTheme = ElementTheme.Dark }; await dialog.ShowAsync(); }
}
