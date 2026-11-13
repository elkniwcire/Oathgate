using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
namespace SteamNite.WinUI;

// Real WinUI controls throughout; the PowerShell service has no windows.
public sealed partial class NativeWorkflowWindow : Window
{
    readonly NativeBackend service;
    readonly string initialAction;
    readonly string[] ids;
    readonly string profilePath;
    readonly Grid root = new() { Padding = new Thickness(28), RowSpacing = 18, RequestedTheme = ElementTheme.Dark };
    readonly TextBlock heading = new() { FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
    readonly StackPanel options = new() { Spacing = 12 };
    readonly ContentControl body = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, MaxHeight = 120 };
    readonly ProgressRing working = new() { Width = 18, Height = 18, IsActive = true, VerticalAlignment = VerticalAlignment.Top };
    readonly StackPanel actions = new() { Orientation = Orientation.Horizontal, Spacing = 10 };
    readonly ContentControl optionsHost = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch };
    readonly ContentControl actionsHost = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch };
    readonly ComboBox account = new() { Header = "Steam account", PlaceholderText = "Choose a Steam account", HorizontalAlignment = HorizontalAlignment.Stretch, DisplayMemberPath = "Label" };
    readonly PasswordBox key = new() { Header = "SteamGridDB API key", Width = 300, PasswordRevealMode = PasswordRevealMode.Hidden };
    readonly CheckBox remember = new() { Content = "Remember key" };
    readonly CheckBox fill = new() { Content = "Fill missing recommended artwork", IsChecked = true };
    readonly CheckBox reopen = new() { Content = "Reopen Steam when finished", IsChecked = true };
    readonly Button stop = new() { Content = "Stop after current step", IsEnabled = false, Visibility = Visibility.Collapsed };
    readonly TaskCompletionSource completion = new();
    JsonElement setup, plan, activity, artState;
    bool busy, running, loading, cancelWait, closed;
    string action;
    Button? apply;
    ListView? rows;
    string[] retryIds = [];
    public static Task ShowAsync(string workspace, string action, string[] ids, string profile)
    {
        var window = new NativeWorkflowWindow(workspace, action, ids, profile);
        window.Activate();
        return window.completion.Task;
    }
    NativeWorkflowWindow(string workspace, string requestedAction, string[] selected, string profile)
    {
        service = new NativeBackend(workspace); initialAction = requestedAction; action = requestedAction; ids = selected; profilePath = profile;
        fill.IsChecked = requestedAction != "Shortcuts";
        heading.Text = requestedAction switch { "ManageFolders" => "Scan folders", "EditLaunch" => "Launch settings", "AllArtwork" => "Recommended artwork", _ => requestedAction };
        status.Text = "Loading the current library…";
        root.Background = Brush("AppSurface"); status.Foreground = Brush("QuietText");
        root.Padding = new Thickness(28, 8, 28, 24);
        foreach (var size in new[] { new GridLength(24), GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto }) root.RowDefinitions.Add(new RowDefinition { Height = size });
        optionsHost.Content = options; actionsHost.Content = new ScrollViewer { Content = actions, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollMode = ScrollMode.Enabled, VerticalScrollMode = ScrollMode.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
        var titleRegion = new Grid { Margin = new Thickness(0, 0, 140, 0) }; titleRegion.Children.Add(new TextBlock { Text = "Oathgate", FontSize = 12, Foreground = Brush("QuietText"), VerticalAlignment = VerticalAlignment.Center }); root.Children.Add(titleRegion);
        Place(heading, 1); Place(optionsHost, 2); Place(body, 3);
        var statusRow = new Grid { ColumnSpacing = 12 }; statusRow.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); statusRow.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); statusRow.Children.Add(working); Grid.SetColumn(status, 1); statusRow.Children.Add(status); Place(statusRow, 4);
        var footer = new Grid { ColumnSpacing = 10 }; footer.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); footer.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        footer.Children.Add(actionsHost); Grid.SetColumn(stop, 1); footer.Children.Add(stop); Place(footer, 5);
        Content = root; Title = "Oathgate"; ExtendsContentIntoTitleBar = true; SetTitleBar(titleRegion);
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "oathgate.ico"));
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1280, 900));
        if (AppWindow.Presenter is OverlappedPresenter presenter) { presenter.PreferredMinimumWidth = 960; presenter.PreferredMinimumHeight = 680; }
        AppWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent; AppWindow.TitleBar.ButtonForegroundColor = Colors.White;
        AppWindow.Closing += (_, args) => { if (busy || running) { args.Cancel = true; status.Text = "Finish the current step, or use Stop to request a safe stop, before closing."; } };
        Closed += async (_, _) => {
            closed = true;
            // The close guard already prevents closing during an operation.
            // Re-enable the library immediately; pipe cleanup is not UI work.
            var cleanup = service.DisposeAsync(); completion.TrySetResult();
            try { await cleanup; } catch (Exception error) { System.Diagnostics.Debug.WriteLine("Workflow cleanup: " + error.Message); }
        };
        stop.Click += async (_, _) => { cancelWait = true; stop.IsEnabled = false; if (running) { try { status.Text = (await service.CallAsync("Stop")).S("Detail"); } catch (Exception error) { status.Text = error.Message; } } };
        root.Loaded += async (_, _) => await Run(async () =>
        {
            if (AppWindow.Presenter is OverlappedPresenter p) { p.PreferredMinimumWidth = (int)Math.Ceiling(960 * root.XamlRoot.RasterizationScale); p.PreferredMinimumHeight = (int)Math.Ceiling(680 * root.XamlRoot.RasterizationScale); }
            setup = await service.CallAsync("Setup", new { Profile = profilePath });
            loading = true; account.ItemsSource = setup.A("Profiles").Select(p => new ProfileChoice(p.S("Label"), p.S("ShortcutPath"))).ToArray();
            account.SelectedIndex = Array.FindIndex(setup.A("Profiles"), p => p.S("ShortcutPath") == setup.S("Profile"));
            key.PlaceholderText = setup.B("HasKey") ? "Saved key available" : "Paste your API key"; remember.IsChecked = setup.B("HasKey"); loading = false;
            hasArtKey = setup.B("HasKey");
            await BuildAsync();
        });
        account.SelectionChanged += async (_, _) => { if (loading || busy || editingArtSettings) return; await Run(async () => { await service.CallAsync("Profile", new { Profile = ((ProfileChoice)account.SelectedItem).Path }); await BuildAsync(); }); };
        fill.Checked += async (_, _) => { if (!loading && !busy && action is "Prepare" or "Shortcuts" or "AllArtwork") await Run(PreviewAsync); };
        fill.Unchecked += async (_, _) => { if (!loading && !busy && action is "Prepare" or "Shortcuts" or "AllArtwork") await Run(PreviewAsync); };
    }
    void Place(FrameworkElement item, int row) { Grid.SetRow(item, row); root.Children.Add(item); }
    static SolidColorBrush Brush(string key) => (SolidColorBrush)Application.Current.Resources[key];
    static TextBlock Text(string text, bool quiet = false) => new() { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = Brush(quiet ? "QuietText" : "PrimaryText") };
    static StackPanel Stack(params UIElement[] items) { var panel = new StackPanel { Spacing = 12 }; foreach (var item in items) panel.Children.Add(item); return panel; }
    void SetBody(UIElement content) => body.Content = content;
    Button Action(string label, Func<Task> callback, bool primary = false)
    {
        var button = new Button { Content = label };
        if (primary) { button.Background = Brush("Accent"); button.Foreground = Brush("AppSurface"); }
        button.Click += async (_, _) => await Run(callback);
        var more = actions.Children.OfType<Button>().FirstOrDefault(b => b.Tag as string == "MoreActions");
        if (label is "Close" or "Cancel" || actions.Children.Count < 3) actions.Children.Add(button);
        else {
            if (more == null) { more = new Button { Content = "More", Tag = "MoreActions", Flyout = new MenuFlyout() }; actions.Children.Add(more); }
            var item = new MenuFlyoutItem { Text = label }; item.Click += async (_, _) => await Run(callback); ((MenuFlyout)more.Flyout).Items.Add(item);
        }
        return button;
    }
    void Header(string title, string description, bool withAccount = false, bool withKey = false)
    {
        foreach (var control in new UIElement[] { account, key, remember, fill, reopen, query, category, matches, artwork, previewImage, artCoverage, queued }) Detach(control);
        heading.Text = title; Title = title + " · Oathgate"; options.Children.Clear(); actions.Children.Clear();
        root.RowSpacing = 18;
        heading.Visibility = Visibility.Visible; artHeaderHost.Visibility = Visibility.Collapsed;
        if (!string.IsNullOrWhiteSpace(description)) options.Children.Add(Text(description, true));
        if (withAccount) options.Children.Add(account);
        if (withKey)
        {
            var credentials = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
            credentials.Children.Add(key); credentials.Children.Add(remember);
            var get = new HyperlinkButton { Content = "Get API key", NavigateUri = new Uri("https://www.steamgriddb.com/profile/preferences/api"), VerticalAlignment = VerticalAlignment.Bottom }; credentials.Children.Add(get);
            var forget = new Button { Content = "Forget key", VerticalAlignment = VerticalAlignment.Bottom }; forget.Click += async (_, _) => await Run(async () => { await service.CallAsync("Key", new { Forget = true }); key.Password = ""; key.PlaceholderText = "Paste your API key"; remember.IsChecked = false; status.Text = "Saved key removed."; }); credentials.Children.Add(forget);
            options.Children.Add(new Expander { Header = setup.B("HasKey") ? "SteamGridDB · saved key available" : "SteamGridDB API key", IsExpanded = !setup.B("HasKey"), Content = credentials, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        }
    }
    static void Detach(UIElement control)
    {
        if (control is not FrameworkElement element) return;
        if (element.Parent is Panel panel) panel.Children.Remove(control);
        else if (element.Parent is ContentControl content) content.Content = null;
        else if (element.Parent is Border border) border.Child = null;
    }
    void CloseIdle() { busy = false; Close(); }
    async Task Run(Func<Task> callback)
    {
        if (busy || closed) return; busy = true; working.IsActive = true; working.Visibility = Visibility.Visible; optionsHost.IsEnabled = false; artHeaderHost.IsEnabled = false; actionsHost.IsEnabled = false; body.IsEnabled = false;
        try { await callback(); }
        catch (Exception error) { status.Text = error.Message; if (action == "Artwork" && (error.Message.Contains("API key", StringComparison.OrdinalIgnoreCase) || error.Message.Contains("rejected the request", StringComparison.OrdinalIgnoreCase))) SetArtKeyRequired(true); }
        finally {
            busy = false; working.IsActive = false; working.Visibility = Visibility.Collapsed; optionsHost.IsEnabled = true; artHeaderHost.IsEnabled = true; account.IsEnabled = true; actionsHost.IsEnabled = true; body.IsEnabled = true;
            if (!running) { stop.IsEnabled = false; stop.Visibility = Visibility.Collapsed; }
            if (!closed && pendingArtRefresh != "") { var pending = pendingArtRefresh; pendingArtRefresh = ""; DispatcherQueue.TryEnqueue(async () => await Run(pending == "Search" ? SearchArtworkAsync : pending == "Image" ? PreviewArtImageAsync : LoadCategoryAsync)); }
        }
    }
    async Task BuildAsync()
    {
        status.Text = "";
        switch (action)
        {
            case "Prepare": case "Shortcuts": case "AllArtwork":
                Header(action == "AllArtwork" ? "Recommended artwork for your library" : "Prepare in Steam", action == "AllArtwork" ? "Fill missing artwork for every eligible installed game already synced to this account. Existing artwork is preserved." : "Review the selected games. Add missing shortcuts, repair launch fields and optionally fill missing artwork. Existing images are preserved.", true, true);
                var preparationOptions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 22 };
                if (action != "AllArtwork") preparationOptions.Children.Add(fill); preparationOptions.Children.Add(reopen); options.Children.Add(preparationOptions);
                apply = Action(action == "AllArtwork" ? "Fill missing artwork" : "Prepare in Steam", PrepareAsync, true);
                Action("Refresh preview", PreviewAsync); Action("Open Steam", OpenSteamAsync); Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
                await PreviewAsync(); break;
            case "Artwork": await BuildArtworkAsync(); break;
            case "ManageFolders": BuildFolders(); break;
            case "Settings":
                Header("Settings", "Choose the Steam account used for library status and future actions. Every write preview shows its destination.", true);
                SetBody(Text("Your scan folders are managed separately under More → Manage folders.", true));
                Action("Save settings", async () => { if (account.SelectedItem is not ProfileChoice choice) throw new InvalidOperationException("Choose an account."); await service.CallAsync("SaveSettings", new { Profile = choice.Path }); status.Text = "Preferred Steam account saved."; }, true);
                Action("Close", () => { CloseIdle(); return Task.CompletedTask; }); break;
            case "EditLaunch": await BuildLaunchAsync(); break;
            case "History": await BuildHistoryAsync(); break;
            case "Remove": await BuildRemovalAsync(); break;
            case "Launch": await service.CallAsync("Launch", new { Ids = ids }); busy = false; Close(); break;
            case "Ignore": case "Unignore": await service.CallAsync("Ignore", new { Ids = ids, Ignored = action == "Ignore" }); busy = false; Close(); break;
        }
    }
    async Task SaveKeyAsync() { if (!string.IsNullOrWhiteSpace(key.Password)) await service.CallAsync("Key", new { Key = key.Password, Remember = remember.IsChecked == true }); }
    async Task OpenSteamAsync() { status.Text = (await service.CallAsync("OpenSteam")).S("Detail"); }
    async Task<bool> ConfirmAsync(string title, string text, string affirmative)
    {
        var dialog = new ContentDialog { Title = title, Content = new ScrollViewer { Content = Text(text), MaxHeight = 430 }, PrimaryButtonText = affirmative, CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close, RequestedTheme = ElementTheme.Dark, XamlRoot = root.XamlRoot };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
    async Task<bool> EnsureSteamClosedAsync()
    {
        if (!(await service.CallAsync("SteamState")).B("Running")) return true;
        if (!await ConfirmAsync("Close Steam to continue?", "Save any game progress first. Oathgate will request Steam’s normal exit and wait until it is fully closed.\n\nSteam will stay closed while you make changes.", "Close Steam")) return false;
        await service.CallAsync("ShutdownSteam"); cancelWait = false; stop.Content = "Cancel waiting"; stop.IsEnabled = true; stop.Visibility = Visibility.Visible;
        var deadline = DateTime.UtcNow.AddSeconds(45); DateTime? quietSince = null;
        while (DateTime.UtcNow < deadline && !cancelWait)
        {
            status.Text = "Waiting for Steam to close. Respond to any running-game prompts in Steam.";
            var steam = (await service.CallAsync("SteamState")).B("Running");
            if (!steam) { quietSince ??= DateTime.UtcNow; if ((DateTime.UtcNow - quietSince.Value).TotalMilliseconds >= 600) { stop.IsEnabled = false; stop.Content = "Stop after current step"; return true; } } else quietSince = null;
            await Task.Delay(300);
        }
        stop.Content = "Stop after current step"; stop.IsEnabled = false;
        status.Text = cancelWait ? "Cancelled. No changes applied." : "Steam has not exited yet. No changes applied; finish closing it and try again."; return false;
    }
    ListView CreateRows(JsonElement[] data, bool activityRows = false)
    {
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single, HorizontalContentAlignment = HorizontalAlignment.Stretch };
        foreach (var row in data)
        {
            var grid = new Grid { Padding = new Thickness(12), ColumnSpacing = 18 };
            foreach (var width in new[] { 2.0, 1.0, 1.0, 3.0 }) grid.ColumnDefinitions.Add(new() { Width = new GridLength(width, GridUnitType.Star) });
            var values = new[] { row.S("Title"), row.S(activityRows ? "Shortcut" : "Action"), row.S("Artwork"), (activityRows ? row.S("Status") + ": " : "") + row.S("Detail") };
            for (var i = 0; i < values.Length; i++) { var text = Text(values[i], i > 0); if (i == 0) text.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold; Grid.SetColumn(text, i); grid.Children.Add(text); }
            var item = new ListViewItem { Content = grid, Tag = row, HorizontalContentAlignment = HorizontalAlignment.Stretch };
            AutomationProperties.SetName(item, string.Join(" · ", values)); list.Items.Add(item);
        }
        list.SelectionChanged += (_, _) => { if (list.SelectedItem is ListViewItem item && item.Tag is JsonElement row) status.Text = row.S("Detail") + (row.S("Action") == "Repair" ? "\nCurrent: " + row.S("Current") + "\nProposed: " + row.S("Proposed") : ""); };
        return list;
    }
    async Task PreviewAsync()
    {
        status.Text = "Checking the current library and Steam shortcuts…";
        plan = await service.CallAsync("Preview", new { Ids = retryIds.Length > 0 ? retryIds : ids, All = action == "AllArtwork", Artwork = fill.IsChecked == true });
        rows = CreateRows(plan.A("Rows")); SetBody(rows);
        status.Text = $"{plan.S("Profile")}\n{plan.A("Rows").Length} selected · {plan.N("AddCount")} additions · {plan.N("RepairCount")} repairs · {plan.N("ArtworkCount")} games need artwork. Select a repair to inspect its changes.";
        if (apply != null) apply.IsEnabled = plan.A("Rows").Any(r => r.B("Eligible"));
    }
    async Task PrepareAsync()
    {
        await SaveKeyAsync(); if (!await EnsureSteamClosedAsync()) return;
        await service.CallAsync("StartPrepare"); running = true; stop.IsEnabled = true; stop.Visibility = Visibility.Visible;
        try
        {
            while (true)
            {
                var progress = await service.CallAsync("Poll"); activity = progress.P("Activity");
                if (activity.ValueKind == JsonValueKind.Object) { rows = CreateRows(activity.A("Rows"), true); SetBody(rows); status.Text = activity.S("Status") + ": " + activity.S("Detail") + (activity.S("BackupPath") == "" ? "" : "\nBackup: " + activity.S("BackupPath")); }
                if (!progress.B("Running")) break;
                await Task.Delay(200);
            }
        }
        finally { running = false; stop.IsEnabled = false; }
        actions.Children.Clear();
        apply = Action("Review preparation", async () => { await PreviewAsync(); ShowRetryPlan(); }, true);
        Action("Retry unfinished", async () => { plan = await service.CallAsync("Retry", new { Id = activity.S("Id") }); action = "Prepare"; retryIds = plan.A("Rows").Select(r => r.S("GameId")).ToArray(); ShowRetryPlan(); });
        Action("Choose artwork", async () => { if (rows?.SelectedItem is not ListViewItem item || item.Tag is not JsonElement row) throw new InvalidOperationException("Select a game row first."); await ShowAsync(new BackendClient().Workspace, "Artwork", [row.S("GameId")], ((ProfileChoice)account.SelectedItem).Path); });
        Action("Open Steam", OpenSteamAsync); Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
        if (reopen.IsChecked == true) { try { await service.CallAsync("OpenSteam"); } catch (Exception error) { status.Text += "\nCould not reopen Steam: " + error.Message; } }
    }
    void ShowRetryPlan()
    {
        Header("Review preparation", "Only the games listed below will be prepared. Review their current shortcut and artwork state before applying.", true, true);
        loading = true; fill.IsChecked = plan.B("IncludeArtwork"); loading = false; options.Children.Add(Stack(fill, reopen));
        rows = CreateRows(plan.A("Rows")); SetBody(rows);
        apply = Action("Prepare in Steam", PrepareAsync, true); Action("Refresh preview", PreviewAsync); Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
        status.Text = plan.S("Profile") + "\nRetry uses current installation and shortcut state, preserving completed work.";
    }
    void BuildFolders()
    {
        Header("Scan folders", "Added folders supplement launcher records and automatic discovery. Removing a scan folder leaves its game files intact.");
        var extra = setup.A("ExtraRoots").Select(x => x.GetString()!).ToList();
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single };
        void Refresh()
        {
            list.Items.Clear(); foreach (var path in extra) list.Items.Add(new ListViewItem { Content = Stack(Text(path), Text("Added by you · " + (Directory.Exists(path) ? "Available" : "Unavailable"), true)), Tag = path });
            foreach (var folder in setup.A("AutomaticRoots")) { var path = folder.GetString()!; list.Items.Add(new ListViewItem { Content = Stack(Text(path), Text("Automatic · " + (Directory.Exists(path) ? "Available" : "Not present"), true)) }); }
            list.Items.Add(new ListViewItem { Content = Text("Launcher records: Xbox / Microsoft Store, Epic, Amazon, GOG, Ubisoft Connect, EA / Origin", true) });
        }
        Refresh(); SetBody(list);
        Action("Add folder…", async () => { var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this)); var folder = await picker.PickSingleFolderAsync(); if (folder != null) { if (extra.Contains(folder.Path, StringComparer.OrdinalIgnoreCase) || setup.A("AutomaticRoots").Any(x => string.Equals(x.GetString(), folder.Path, StringComparison.OrdinalIgnoreCase))) status.Text = "This folder is already listed."; else { extra.Add(folder.Path); Refresh(); } } });
        Action("Remove added folder", () => { if (list.SelectedItem is not ListViewItem item || item.Tag is not string path) throw new InvalidOperationException("Select a folder added by you."); extra.Remove(path); Refresh(); return Task.CompletedTask; });
        Action("Save and rescan", async () => { await service.CallAsync("SaveSettings", new { ExtraRoots = extra }); busy = false; Close(); }, true);
        Action("Cancel", () => { CloseIdle(); return Task.CompletedTask; });
    }
    async Task BuildLaunchAsync()
    {
        var info = await service.CallAsync("LaunchInfo", new { Ids = ids });
        Header("Launch settings", info.S("Title") + "\nDetected: " + info.S("DetectedMethod") + " · " + info.S("DetectedTarget"));
        var executable = new TextBox { Header = "Executable", Text = info.S("Executable"), PlaceholderText = "Choose an .exe" };
        var folder = new TextBox { Header = "Working folder", Text = info.S("WorkingDirectory") };
        var arguments = new TextBox { Header = "Arguments", Text = info.S("Arguments") };
        var browse = new Button { Content = "Choose executable…" }; browse.Click += async (_, _) => await Run(async () => { var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".exe"); WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this)); var file = await picker.PickSingleFileAsync(); if (file != null) { executable.Text = file.Path; folder.Text = Path.GetDirectoryName(file.Path) ?? ""; } });
        var browseFolder = new Button { Content = "Choose working folder…" }; browseFolder.Click += async (_, _) => await Run(async () => { var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this)); var picked = await picker.PickSingleFolderAsync(); if (picked != null) folder.Text = picked.Path; });
        SetBody(new ScrollViewer { Content = Stack(executable, browse, folder, browseFolder, arguments, Text("Save an override, test it from the library, then Prepare in Steam to review its shortcut changes.", true)) });
        Action("Save override", async () => { status.Text = (await service.CallAsync("SaveLaunch", new { Ids = ids, Executable = executable.Text.Trim().Trim('"'), WorkingDirectory = folder.Text.Trim().Trim('"'), Arguments = arguments.Text })).S("Detail"); }, true);
        Action("Use detected launch", async () => { await service.CallAsync("SaveLaunch", new { Ids = ids, Reset = true }); await BuildLaunchAsync(); status.Text = "Detected launch restored. Prepare in Steam to review its shortcut update."; });
        Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
    }
    async Task BuildHistoryAsync()
    {
        Header("Activity history", "Preparation records include backups and unfinished work. Retry replans against current installations and the original Steam account; history is not undo.");
        var history = await service.CallAsync("History"); var list = new ListView { HorizontalContentAlignment = HorizontalAlignment.Stretch };
        foreach (var record in history.A("Activities"))
        {
            var item = new ListViewItem { Content = Stack(Text(record.S("StartedAt") + " · " + record.S("Status")), Text(record.S("Detail") + "\nAccount " + record.P("Profile").S("AccountId"), true)), Tag = record }; list.Items.Add(item);
        }
        var detail = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        list.SelectionChanged += (_, _) => { if (list.SelectedItem is ListViewItem item && item.Tag is JsonElement record) detail.Text = "Shortcut backup: " + record.S("BackupPath") + "\n\n" + string.Join("\n\n", record.A("Rows").Select(r => r.S("Title") + " · " + r.S("Status") + "\nShortcut: " + r.S("Shortcut") + " · Artwork: " + r.S("Artwork") + "\n" + r.S("Detail"))); };
        var columns = new Grid { ColumnSpacing = 24 }; columns.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); columns.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); columns.Children.Add(list); var scroll = new ScrollViewer { Content = detail }; Grid.SetColumn(scroll, 1); columns.Children.Add(scroll); SetBody(columns);
        if (list.Items.Count == 0) status.Text = "No preparation operations recorded yet.";
        Action("Review unfinished…", async () =>
        {
            if (list.SelectedItem is not ListViewItem item || item.Tag is not JsonElement record) throw new InvalidOperationException("Choose an activity.");
            plan = await service.CallAsync("Retry", new { Id = record.S("Id") }); action = "Prepare"; retryIds = plan.A("Rows").Select(r => r.S("GameId")).ToArray();
            loading = true; var path = record.P("Profile").S("ShortcutPath"); account.SelectedIndex = Array.FindIndex(setup.A("Profiles"), p => p.S("ShortcutPath") == path); fill.IsChecked = plan.B("IncludeArtwork"); loading = false;
            ShowRetryPlan();
        }, true);
        Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
    }
    async Task BuildRemovalAsync()
    {
        var preview = await service.CallAsync("RemovalPreview", new { Ids = ids });
        Header("Remove selected Steam shortcuts", "Review exactly the selected shortcuts, including any manually added entries. Only Steam shortcuts are removed; game files and artwork stay intact. A backup is saved first.", true);
        SetBody(new ScrollViewer { Content = Stack(preview.A("Rows").Select(r => (UIElement)new Border { Padding = new Thickness(16), Background = Brush("PanelSurface"), CornerRadius = new CornerRadius(10), Child = Stack(Text(r.S("Title")), Text(r.S("Reason"), true)) }).ToArray()) });
        status.Text = preview.S("Profile");
        Action("Remove reviewed shortcuts", async () =>
        {
            var names = string.Join("\n", preview.A("Rows").Select(r => r.S("Title")));
            var manualWarning = preview.N("ManualCount") > 0 ? $"\n\nThis includes {preview.N("ManualCount")} manually added shortcut(s). Confirming explicitly authorizes their removal too." : "";
            if (!await ConfirmAsync("Remove these Steam shortcuts?", preview.S("Profile") + "\n\n" + names + manualWarning + "\n\nA shortcut backup will be saved. Game files and artwork are preserved.", "Remove shortcuts")) return;
            if (!await EnsureSteamClosedAsync()) return;
            var result = await service.CallAsync("Remove", new { Confirmed = true, ConfirmManual = preview.N("ManualCount") > 0 }); status.Text = $"Removed {result.N("Removed")} shortcut(s).\nBackup: {result.S("BackupPath")}"; actions.Children.Clear(); Action("Open Steam", OpenSteamAsync); Action("Close", () => { CloseIdle(); return Task.CompletedTask; });
        });
        Action("Cancel", () => { CloseIdle(); return Task.CompletedTask; });
    }
    sealed record ProfileChoice(string Label, string Path);

}
