using System.Diagnostics;
using System.Text;
using System.Text.Json;
namespace SteamNite.WinUI;

// A private pipe, not command lines or temporary request files, carries secrets.
// The backend retains plans/assets and independently resolves every game identity.
public sealed class NativeBackend : IAsyncDisposable
{
    readonly Process process;
    readonly SemaphoreSlim gate = new(1, 1);
    readonly Task<string> errors;
    bool disposed;
    public NativeBackend(string workspace)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
          StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = workspace };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(workspace, "winui", "Native.Service.ps1"), "-Workspace", workspace }) start.ArgumentList.Add(arg);
        process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the library service.");
        errors = process.StandardError.ReadToEndAsync();
    }
    public async Task<JsonElement> CallAsync(string operation, object? data = null)
    {
        await gate.WaitAsync();
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { Operation = operation, Data = data ?? new { } }));
            await process.StandardInput.FlushAsync();
            var line = await process.StandardOutput.ReadLineAsync();
            if (line == null) throw new InvalidOperationException("The library service exited. Reopen this screen; check Activity history before retrying writes.");
            using var document = JsonDocument.Parse(line);
            if (!document.RootElement.GetProperty("Ok").GetBoolean()) throw new InvalidOperationException(document.RootElement.S("Error"));
            return document.RootElement.GetProperty("Data").Clone();
        }
        finally { gate.Release(); }
    }
    public async ValueTask DisposeAsync()
    {
        await gate.WaitAsync();
        try { if (disposed) return; disposed = true; process.StandardInput.Close(); }
        finally { gate.Release(); }
        // EOF requests a safe stop. Never kill a process that may be committing.
        await Task.Run(() => process.WaitForExit());
        try { await errors.WaitAsync(TimeSpan.FromSeconds(3)); } catch (TimeoutException) { /* A launched client may inherit a pipe; never hold the window open for it. */ }
        process.Dispose();
    }
}
public static class NativeJson
{
    public static JsonElement P(this JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var result) ? result : default;
    public static string S(this JsonElement value, string name) { var p = value.P(name); return p.ValueKind is JsonValueKind.String ? p.GetString() ?? "" : p.ValueKind is JsonValueKind.Number ? p.ToString() : ""; }
    public static bool B(this JsonElement value, string name) => value.P(name).ValueKind == JsonValueKind.True;
    public static long N(this JsonElement value, string name) => value.P(name).ValueKind == JsonValueKind.Number ? value.P(name).GetInt64() : 0;
    public static JsonElement[] A(this JsonElement value, string name) => value.P(name).ValueKind == JsonValueKind.Array ? value.P(name).EnumerateArray().ToArray() : [];
}
