# Contributing

Use Windows x64 with Windows PowerShell 5.1 and the .NET 8 SDK. Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Run-Checks.ps1` before submitting a change. Checks use isolated app state under ignored `tests/.tmp`; fixture tests must not write to a real Steam profile or launch real games.

Keep API keys, scan exports, account IDs, local settings, caches and game artwork out of commits. Use synthetic fixtures. Preserve manual-shortcut ownership, explicit removal confirmation, backups, Steam-close checks, stale-preview checks, cancellation, and per-account scope.

The public app name is Oathgate. Internal SteamNite identifiers remain compatible with existing shortcuts and saved state. Do not rename ownership tags as a cosmetic change.

For bugs, include Windows version, Oathgate version, game store, expected behavior, and reproduction steps. Redact usernames, account IDs and local paths. Never attach saved keys or the entire data directory.
