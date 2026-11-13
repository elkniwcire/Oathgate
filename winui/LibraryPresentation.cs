namespace SteamNite.WinUI;

// Keep each column independent: an uninstalled but still-synced game should
// visibly disagree across columns rather than acquire one overall green state.
public static class LibraryPresentation
{
    public static string InstallationTone(string state, bool ignored) => ignored ? "QuietText" : state switch
    { "Installed" => "Success", "Not installed" => "Danger", "Not detected" or "Unverified" => "Warning", _ => "QuietText" };
    public static string SteamTone(string state, bool ignored) => ignored || state == "Ignored" ? "QuietText" : state == "Synced" ? "Success" : "Warning";
    public static string ArtworkTone(string state, bool ignored) => ignored ? "QuietText" : state == "5/5" ? "Success" : "Warning";
    public static bool? SelectAllState(int visible, int selected) => visible == 0 || selected == 0 ? false : selected == visible ? true : null;
}
