using Microsoft.UI.Xaml;
namespace SteamNite.WinUI;
public partial class App : Application
{
    private Window? window;
    private InstanceLease? instance;
    public App()
    {
        UnhandledException += (_, e) => LogError(e.Exception);
        try { InitializeComponent(); }
        catch (Exception error) { LogError(error); throw; }
    }
    private static void LogError(Exception error) => System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "SteamNite.WinUI-error.txt"), error.ToString());
    private void LoadTheme()
    {
        var path = System.IO.Path.Combine(new BackendClient().Workspace, "design", "tokens.json");
        using var tokens = System.Text.Json.JsonDocument.Parse(System.IO.File.ReadAllText(path));
        foreach (var pair in new System.Collections.Generic.Dictionary<string, string>
        {
            ["AppSurface"] = "background", ["PanelSurface"] = "surface", ["InputSurface"] = "input",
            ["HoverSurface"] = "hover", ["SelectionSurface"] = "selection", ["QuietText"] = "muted",
            ["PrimaryText"] = "text", ["Accent"] = "accent", ["ThemeBorder"] = "border",
            ["Success"] = "success", ["Warning"] = "warning", ["Danger"] = "danger",
            ["ToggleButtonBackgroundChecked"] = "accent", ["ToggleButtonForegroundChecked"] = "background"
        })
        {
            var hex = tokens.RootElement.GetProperty(pair.Value).GetString()!.TrimStart('#');
            var color = Windows.UI.Color.FromArgb(255, Convert.ToByte(hex[..2], 16), Convert.ToByte(hex[2..4], 16), Convert.ToByte(hex[4..6], 16));
            Resources[pair.Key] = new Microsoft.UI.Xaml.Media.SolidColorBrush(color);
        }
    }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        instance = new InstanceLease();
        if (!instance.Acquired) { instance.Dispose(); instance = null; Exit(); return; }
        LoadTheme(); window = new MainWindow();
        window.Closed += (_, _) => { instance?.Dispose(); instance = null; };
        window.Activate();
    }
}
