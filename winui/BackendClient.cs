using System.Diagnostics;
using System.Text.Json;
namespace SteamNite.WinUI;
public sealed class BackendClient
{
    public string Workspace { get; }
    public BackendClient()
    {
        var configured = Environment.GetEnvironmentVariable("STEAMNITE_WORKSPACE");
        if (!string.IsNullOrEmpty(configured) && File.Exists(Path.Combine(configured, "SteamNite.ps1"))) { Workspace = Path.GetFullPath(configured); return; }
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "SteamNite.ps1"))) { Workspace = dir.FullName; return; }
        throw new InvalidOperationException("Oathgate's support files are missing. Extract the complete release ZIP before starting the app.");
    }
    public async Task<LibrarySnapshot> ScanAsync(CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = System.Text.Encoding.UTF8 };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(Workspace, "winui", "Backend.Snapshot.ps1"), "-Workspace", Workspace }) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the game discovery backend.");
        using var registration = cancellationToken.Register(() => { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } });
        var output = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        if (process.ExitCode != 0) throw new InvalidOperationException(await error);
        return JsonSerializer.Deserialize<LibrarySnapshot>(await output, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new InvalidOperationException("Discovery returned an empty response.");
    }
    public void OpenClassic()
    {
        var executable = Path.Combine(Workspace, "SteamNite.exe");
        if (!File.Exists(executable)) throw new FileNotFoundException("Build the classic app with Build.ps1 first.");
        Process.Start(new ProcessStartInfo(executable) { Arguments = "--classic", UseShellExecute = true, WorkingDirectory = Workspace });
    }
    public async Task RunWorkflowAsync(string action, IEnumerable<string> gameIds, string profilePath)
    {
        // Only identities cross this boundary. The host rescans, resolves current
        // overrides, validates ownership and presents the existing apply prompts.
        var path = Path.Combine(Path.GetTempPath(), "steamnite-workflow-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { Action = action, GameIds = gameIds.ToArray(), ProfileShortcutPath = profilePath }));
            var host = Path.Combine(Workspace, "SteamNite.Workflow.exe");
            if (!File.Exists(host)) throw new FileNotFoundException("Build the workflow host with Build-WinUI.ps1 first.");
            var start = new ProcessStartInfo(host)
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, WorkingDirectory = Workspace };
            foreach (var arg in new[] { "--workflow-request", path }) start.ArgumentList.Add(arg);
            using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not open the selected workflow.");
            var error = process.StandardError.ReadToEndAsync();
            // Never kill a workflow process: it may be committing a Steam change.
            await Task.Run(() => process.WaitForExit());
            if (process.ExitCode != 0) {
                string message;
                try { message = await error.WaitAsync(TimeSpan.FromSeconds(3)); } catch (TimeoutException) { message = ""; }
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(message) ? "The workflow host could not finish. Check the selection and try again." : message);
            }
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
public sealed class LibrarySnapshot
{
    public GameEntry[] Games { get; set; } = [];
    public string[] Notices { get; set; } = [];
    public string ProfileLabel { get; set; } = "";
    public string ProfileShortcutPath { get; set; } = "";
}
