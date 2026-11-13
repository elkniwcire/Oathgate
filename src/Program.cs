using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

namespace SteamNite {
    internal static class Program {
        [STAThread]
        private static void Main(string[] args) {
            Application.EnableVisualStyles();
            try {
                if (args.Length == 0 && !string.Equals(Path.GetFileNameWithoutExtension(Application.ExecutablePath), "SteamNite.Workflow", StringComparison.OrdinalIgnoreCase)) {
                    string native = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, @"winui\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\Oathgate.exe");
                    if (!File.Exists(native)) throw new FileNotFoundException("Build the native app with Build-WinUI.ps1, or run Start-SteamNite.cmd.", native);
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(native) { UseShellExecute = true, WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory });
                    return;
                }
                if (args.Length == 1 && args[0] == "--classic") args = new string[0];
                string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SteamNite.ps1");
                if (!File.Exists(script)) throw new FileNotFoundException("Keep SteamNite.exe beside SteamNite.ps1 and the src folder.", script);
                if (args.Length != 0 && (args.Length != 2 || args[0] != "--workflow-request")) throw new ArgumentException("Unsupported SteamNite launch arguments.");
                var state = InitialSessionState.CreateDefault();
                state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                using (var runspace = RunspaceFactory.CreateRunspace(state)) {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                    runspace.Open();
                    using (var shell = PowerShell.Create()) {
                        shell.Runspace = runspace;
                        shell.AddCommand(script);
                        if (args.Length == 2) shell.AddParameter("WorkflowRequest", Path.GetFullPath(args[1]));
                        shell.Invoke();
                        if (shell.HadErrors) throw new InvalidOperationException(string.Join(Environment.NewLine, shell.Streams.Error.Select(e => e.ToString())));
                    }
                }
            } catch (Exception error) {
                Environment.ExitCode = 1;
                if (args.Length == 2 && args[0] == "--workflow-request") Console.Error.WriteLine(error.Message);
                else MessageBox.Show(error.Message, "SteamNite could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
