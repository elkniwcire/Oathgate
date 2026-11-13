using SteamNite.WinUI;
[assembly: System.Runtime.Versioning.SupportedOSPlatform("windows")]
var workspace = Path.GetFullPath(args[0]);
var root = Path.Combine(workspace, "tests", ".tmp", "native-pipe-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(Path.Combine(root, "winui"));
var passed = 0;
void Assert(bool value, string message) { if (!value) throw new Exception(message); Console.WriteLine("PASS: " + message); passed++; }
try
{
    var instanceName = @"Local\Oathgate-fixture-" + Guid.NewGuid().ToString("N");
    using (var first = new InstanceLease(instanceName))
    {
        Assert(first.Acquired, "First app instance owns the lease");
        var duplicateAcquired = true;
        var other = new Thread(() => { using var duplicate = new InstanceLease(instanceName); duplicateAcquired = duplicate.Acquired; });
        other.Start(); other.Join();
        Assert(!duplicateAcquired, "Another app instance cannot acquire the same lease");
    }
    using (var reopened = new InstanceLease(instanceName)) Assert(reopened.Acquired, "Closing the app releases its instance lease");
    Assert(LibraryPresentation.InstallationTone("Installed", false) == LibraryPresentation.SteamTone("Synced", false), "Installed and synced share the same readiness color");
    Assert(LibraryPresentation.InstallationTone("Not installed", false) != LibraryPresentation.SteamTone("Synced", false), "Uninstalled but synced games visibly disagree across columns");
    Assert(LibraryPresentation.SteamTone("Not synced", false) == "Warning" && LibraryPresentation.SteamTone("Needs repair", false) == "Warning", "Missing sync and repairs use attention colors");
    Assert(LibraryPresentation.ArtworkTone("4/5", false) == "Warning" && LibraryPresentation.ArtworkTone("5/5", false) == "Success", "Artwork completeness follows the same status palette");
    Assert(LibraryPresentation.InstallationTone("Installed", true) == "QuietText", "Excluded games remain visually muted");
    Assert(LibraryPresentation.SelectAllState(5, 0) == false && LibraryPresentation.SelectAllState(5, 3) == null && LibraryPresentation.SelectAllState(5, 5) == true && LibraryPresentation.SelectAllState(0, 0) == false, "Select-all represents empty, partial and fully selected visible lists");
    await File.WriteAllTextAsync(Path.Combine(root, "winui", "Native.Service.ps1"), """
    param([string]$Workspace)
    [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    [Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
    while($null -ne ($line=[Console]::ReadLine())){
        $r=$line|ConvertFrom-Json
        if($r.Operation -eq 'Failure'){$reply=@{Ok=$false;Error='Expected failure'}}
        else{$reply=@{Ok=$true;Data=@{Echo=$r.Data.Text;Ids=@($r.Data.Ids);Operation=$r.Operation}}}
        [Console]::WriteLine(($reply|ConvertTo-Json -Depth 8 -Compress));[Console]::Out.Flush()
    }
    """);
    var client = new NativeBackend(root);
    var echo = await client.CallAsync("Echo", new { Text = "Disco élysium · 日本語", Ids = new[] { "one", "two" } });
    Assert(echo.S("Echo") == "Disco élysium · 日本語", "Private pipe preserves Unicode");
    Assert(echo.A("Ids").Length == 2, "Selection scope crosses the pipe intact");
    try { await client.CallAsync("Failure"); throw new Exception("Failure was accepted"); } catch (InvalidOperationException error) { Assert(error.Message == "Expected failure", "Backend failures stay actionable"); }
    var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(i => client.CallAsync("Echo", new { Text = i.ToString() })));
    Assert(results.Select(x => x.S("Echo")).SequenceEqual(Enumerable.Range(0, 8).Select(x => x.ToString())), "Concurrent requests cannot consume each other's replies");
    await client.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(10));
    Assert(true, "Closing the pipe lets the backend exit without killing it");
    try { await client.CallAsync("Echo"); throw new Exception("Disposed client was accepted"); } catch (ObjectDisposedException) { Assert(true, "Closed sessions reject further requests"); }
    Console.WriteLine($"All {passed} native pipe checks passed.");
}
finally { Directory.Delete(root, true); }
