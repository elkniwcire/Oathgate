using System.Text.Json;
using SteamNite.WinUI;

var workspace = Path.GetFullPath(args[0]);
var fixture = Path.Combine(workspace, "tests", ".tmp", "workflow-client-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(fixture);
try
{
    File.Copy(Path.Combine(workspace, "SteamNite.Workflow.exe"), Path.Combine(fixture, "SteamNite.Workflow.exe"));
    File.WriteAllText(Path.Combine(fixture, "SteamNite.ps1"), "param([string]$WorkflowRequest)\n@{Path=$WorkflowRequest;Request=(Get-Content -LiteralPath $WorkflowRequest -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding UTF8");
    Environment.SetEnvironmentVariable("STEAMNITE_WORKSPACE", fixture);
    var backend = new BackendClient();
    await backend.RunWorkflowAsync("Prepare", ["gog:first", "ubisoft:second"], "fixture-account").WaitAsync(TimeSpan.FromSeconds(15));
    using var result = JsonDocument.Parse(File.ReadAllText(Path.Combine(fixture, "result.json")));
    var request = result.RootElement.GetProperty("Request");
    if (request.GetProperty("GameIds").GetArrayLength() != 2 || request.GetProperty("ProfileShortcutPath").GetString() != "fixture-account") throw new Exception("Workflow scope was not preserved.");
    if (File.Exists(result.RootElement.GetProperty("Path").GetString())) throw new Exception("Workflow request was not cleaned up after success.");
    File.WriteAllText(Path.Combine(fixture, "SteamNite.ps1"), "throw 'Synthetic client workflow failure'");
    var failed = false;
    try { await backend.RunWorkflowAsync("Artwork", ["gog:first"], "fixture-account").WaitAsync(TimeSpan.FromSeconds(15)); }
    catch (InvalidOperationException error) { failed = error.Message.Contains("Synthetic client workflow failure"); }
    if (!failed) throw new Exception("Workflow errors were not returned to the frontend.");
    Console.WriteLine("All 4 workflow client checks passed: process completion, selection/account scope, request cleanup and error propagation.");
}
finally { Directory.Delete(fixture, true); }

namespace SteamNite.WinUI { public sealed class GameEntry { public string Id { get; set; } = ""; } }
