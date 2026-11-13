# Oathgate

**Bring your games into Steam.**

A minimal Windows app that discovers installed games from Xbox / Microsoft Store, Epic, Amazon, GOG, Ubisoft Connect and EA, then helps you add and maintain non-Steam shortcuts and artwork in Steam. Previously called SteamNite.

## Download and run

Download the Windows x64 ZIP from this repository's Releases page, extract the entire archive, and open **Oathgate.exe**. Keep the support files together. The release is self-contained: users do not need the .NET SDK or a separate .NET installation. Windows PowerShell 5.1 must be available. The current build is unsigned.

The build targets Windows 10 version 1809 or later on x64; a clean Windows VM and additional Windows configurations still need manual release validation. ARM64 and x86 packages are not provided. Store clients and the appropriate game licenses/subscriptions remain necessary.

1. Rescan your games. Add nonstandard libraries using **More > Manage folders**.
2. Choose your Steam account in **More > Settings** when necessary. The app does not silently choose between multiple accounts.
3. Check games and choose **Prepare in Steam**. Review additions/repairs, then allow Steam to close normally before applying.
4. Use **Artwork** to apply recommendations or browse replacements. Artwork is optional and uses your own [SteamGridDB API key](https://www.steamgriddb.com/profile/preferences/api), entered in a masked field.

The bottom **More** menu and right-click menu expose the same secondary actions. Search and filters work with checkbox selection; select-all selects the currently shown games.

## Features and boundaries

- Unified installed games and Steam shortcuts, with separate installation, Steam sync, and artwork statuses.
- Launcher-aware launch recipes, including manifest-selected Xbox launch helpers, Windows package activation, and store protocols. Launch overrides let you choose another executable, arguments and working folder.
- Reviewed shortcut additions and repairs. Existing managed shortcut IDs and customized Steam fields are preserved during repair.
- SteamGridDB search, automatic matching, covers/wide/hero/logo/icon galleries, recommended artwork, and explicit replacement with backups.
- Ignored games, custom scan folders, Steam account selection, preparation history and unfinished-operation review.
- Reviewed removal of selected Steam shortcuts, including explicit confirmation for manual shortcuts. Automatic uninstall eligibility protects manual entries and treats unavailable/ambiguous sources conservatively.

Scanning and synchronization are **manual** in this preview. No background watcher, automatic updater, telemetry, IGDB metadata, or full onboarding flow is included. Game launch acceptance does not prove gameplay, Steam Input, overlay support, entitlement, or playtime tracking. The app does not uninstall games or bypass store authentication.

## Data, privacy and recovery

App state is stored in `%LOCALAPPDATA%\Oathgate`: settings, exclusions, launch overrides, install history, artwork matches/cache, and preparation history. An old `data` directory beside the app is copied once without overwriting destination files; the originals remain available for rollback. New installation directories reuse your per-user state.

Remembering the SteamGridDB key is optional. Saved keys use Windows current-user DPAPI encryption. A copied or unreadable key is treated as missing so you can enter a new one. Keys travel through a private backend pipe, not command-line arguments, and are sent only to SteamGridDB's API. Artwork downloads use approved HTTPS hosts without the key. No credentials or game artwork are bundled.

Invalid settings are preserved as `settings.json.invalid-*` before defaults are used; `settings-recovery.txt` explains the recovery. Permission failures are not treated as malformed JSON. Other state files are retained. One app instance runs per Windows user/session; close it before replacing app files.

Steam shortcut and artwork changes retain preview/confirmation, Steam-process checks, stale-file validation, backups and transactional write safeguards. Backups stay beside the Steam files they protect; preparation history records backup paths. For manual restore, close Steam and Oathgate first. There is no automatic undo UI.

Reports and screenshots can reveal Steam account IDs, game names, usernames, and local paths. Review and redact them before submitting an issue. Never attach a saved key, whole data directory, or Steam profile. See [security reporting](SECURITY.md).

## Build and check

Use Windows x64, Windows PowerShell 5.1 (`powershell.exe`), and the .NET 8 SDK. NuGet access is needed for the pinned Windows App SDK dependencies. `global.json` selects the .NET 8 SDK family; `NuGet.Config` uses the public NuGet feed. The build uses `.tools/dotnet/dotnet.exe` when present, otherwise the SDK on PATH.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Build-WinUI.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Run-Checks.ps1 -SkipBuild
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Build-Release.ps1 -SkipBuild
```

Close the running app before rebuilding. The development launcher remains `SteamNite.exe` / `Start-SteamNite.cmd`; internal filenames, namespaces and ownership markers retain SteamNite names for compatibility. The release launches directly through `Oathgate.exe`. The previous interface is available from a source build with `SteamNite.exe --classic`.

`Run-Checks.ps1` runs fixture suites in child Windows PowerShell processes with isolated data, followed by UI construction checks. It does not modify a real Steam library or launch real games. GitHub Actions runs the Windows build/check/package workflow; a successful remote run is required before trusting a release. `OATHGATE_DATA_DIR` can override storage with an absolute development/test path and disables legacy migration. Leave it unset for normal use. `STEAMNITE_WORKSPACE` is an optional development override for support-file discovery.

`Build-Release.ps1` writes a portable ZIP, SHA-256 checksum, and staged app under ignored `artifacts/`. It includes dependency license notices and a file-hash manifest, excluding personal data and debug symbols. The repository starts from a sanitized source snapshot; ongoing development uses normal commits and pushes. `Export-Source.ps1` is an optional source-only archive tool, excluding Git history, SDKs, binaries, credentials, caches and local data. Re-exporting is not required for normal GitHub updates.

See [contribution guidelines](CONTRIBUTING.md), [native architecture and parity](winui/README.md), [launcher discovery details](docs/launcher-adapters.md), and [release checklist](docs/release-checklist.md).

## License

Original code and the original gateway icon are available under the [MIT license](LICENSE). Dependencies retain their own licenses; see [third-party notices](THIRD-PARTY-NOTICES.md). Oathgate is an independent community project and is not affiliated with Valve, SteamGridDB, the supported stores, or Stormlight's creators.
