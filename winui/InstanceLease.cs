using System.Security.Principal;
namespace SteamNite.WinUI;

// Held for the lifetime of the native app, across all workflow windows.
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
public sealed class InstanceLease : IDisposable
{
    private readonly Mutex mutex;
    public bool Acquired { get; }
    public InstanceLease(string? name = null)
    {
        name ??= @"Local\Oathgate-" + WindowsIdentity.GetCurrent().User!.Value;
        mutex = new Mutex(false, name);
        try { Acquired = mutex.WaitOne(0); }
        catch (AbandonedMutexException) { Acquired = true; }
    }
    public void Dispose() { if (Acquired) mutex.ReleaseMutex(); mutex.Dispose(); }
}
