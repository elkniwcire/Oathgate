# Milestone v0.2 — complete preparation workflow and streamlined controls

Rollback checkpoint: `milestone-v0.2`. The original `milestone-v0.1` checkpoint is also retained.

This milestone includes:

- Windows game discovery and launching for Xbox / Microsoft Store, Epic, Amazon, GOG, Ubisoft Connect and EA. User-confirmed launches for all three new sources.
- Manual Steam shortcut import with preview, duplicate protection and backups.
- A unified installed/Steam-only library with installation states and sync indicators.
- Manual removal of confirmed-uninstalled SteamNite shortcuts with revalidation and backups.
- SteamGridDB artwork thumbnails, automatic search/matching, recommended artwork and batch application.
- Graceful Steam-close consent and a sync-to-artwork handoff.
- Prepare selected games in one workflow: add/repair shortcuts, fill missing artwork, report results and optionally reopen Steam.
- Durable preparation activity history, interrupted-session reporting and retries based on current installations.
- Shortcut health/repair, artwork completeness, saved per-game exclusions and executable/argument/working-folder overrides.
- Explicit manual artwork replacement with previous-image backups and rollback; automatic recommendations remain fill-only.
- Three essential bottom actions, secondary game actions in right-click, and selection-safe multi-game context menus.
- A Rescan/More header, search and common filter chips beside the library, overflow filters, folder management and remembered Steam-account settings.
- Standalone regression checks and local Windows PowerShell build/run scripts.

Validation at checkpoint: all 14 test suites passed (347 checks), plus UI construction smoke tests. No real Steam library changes were performed by the tests. Steam overlay, Steam Input and running-state tracking still need dedicated validation; history does not provide in-app undo.

An initial full run hit a preparation assertion failure; the isolated rerun and subsequent complete run passed. Error diagnostics were added to that check. The initial failure's cause was not reproduced.

## Rebuild and run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
.\SteamNite.exe
```

The executable is generated and is not committed. Keep the source scripts and `src` folder beside the rebuilt executable.

## Restore the code checkpoint

From a clean working tree, create a new branch at the milestone:

```powershell
git switch -c restore/milestone-v0.2 milestone-v0.2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

This preserves the existing branch and its later commits. Close SteamNite before replacing its executable.

Git versions the application source, documentation and tests. Local `data/`, API credentials, generated binaries and scan reports are excluded. Steam shortcut files and artwork live outside this repository; restoring application code does not restore them. Use the timestamped Steam shortcut backups described in README.md to undo external library edits.
