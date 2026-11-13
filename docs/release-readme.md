# Oathgate

Bring your games into Steam.

Extract the entire ZIP into a folder you control, then open **Oathgate.exe**. Do not run it inside the ZIP or copy just the executable. Keep all support files together. This preview targets Windows x64 and uses Windows PowerShell 5.1, included with Windows. No SDK or separate .NET installation is needed for the self-contained release.

Rescan to discover installed games. Use Settings to choose a Steam account if more than one is found. Select games and choose **Prepare in Steam**. Changes are previewed, Steam must close normally before writes, and backups are saved. Artwork is optional and requires your own SteamGridDB API key, entered in the masked artwork settings field. Store clients and game entitlements are still required.

Settings, saved credentials, history, and cache are in `%LOCALAPPDATA%\Oathgate`. Updating the app folder preserves that data. An old `data` folder beside the app is copied once without overwriting destination files; originals remain. Saved keys are encrypted for the Windows user and are not portable between users/computers. An unavailable key prompts for re-entry. Invalid settings are preserved as `settings.json.invalid-*` before defaults are used.

Only one native app instance runs per Windows user/session. Close the app before replacing its files. Installation scanning and sync are manual in this preview. Removing a shortcut does not uninstall a game. Explicitly removing a manually added shortcut requires confirmation; automatic uninstall cleanup does not own manual entries.

The preview is unsigned. Launch only archives from the project's release page; a SHA-256 file accompanies each archive. No telemetry, automatic updater, or background service is included. Artwork requests contact SteamGridDB; launching games invokes their installed store/client.

For recovery, shortcut and artwork backups are written alongside the Steam files they protect; preparation history records relevant backup paths. Close Steam and Oathgate before manually restoring a backup. Do not include your entire data folder, saved keys, Steam files, or unredacted logs in public bug reports. Review screenshots for account IDs, usernames, and paths.

See `LICENSE`, `THIRD-PARTY-NOTICES.md`, and bundled `notices/` for license information.
