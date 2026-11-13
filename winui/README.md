# Oathgate native Windows app

Run `Start-SteamNite.cmd` or `SteamNite.exe`. Rebuild changes with `Build-WinUI.ps1` after closing the app. The default launcher opens the unpackaged, self-contained x64 WinUI application. Builds use the local .NET 8 SDK when present and pinned Windows App SDK packages. Build outputs and toolchain downloads are ignored by Git.

## Native workflows

The library retains search, filters, local covers, unified installed/Steam-only entries, row checkboxes, Ctrl/Shift selection and the Prepare / Launch / Artwork / More action bar. A tri-state header checkbox selects or clears only the filtered, visible games; hidden selections are dropped. The full-width list replaces the right detail panel; Game details remains available in both selection menus. The bottom More menu and right-click share the same actions and eligibility rules. Context actions and More open native WinUI windows for preparation, artwork, executable overrides, scan folders, accounts, activity history and reviewed removal. There is no classic workflow process in the normal app flow.

Preparation previews the exact selection and Steam account, shows current/proposed repair fields, optionally fills missing art and reports durable per-game progress. Stop is cooperative. History and retry use the original account and currently installed unfinished games. Whole-library recommended art includes only eligible, installed games already synced to the account; existing art is preserved.

Artwork automatically searches, chooses the likely or saved game match and loads each category. The grid follows SteamGridDB rank. Thumbnails load progressively; a changed query, match or category supersedes remaining work. Queue images across categories, then Apply selections to add or replace them with backups. Fill missing recommended never replaces existing art. Current art, queued categories and missing/current status are visible. The header is two compact rows: game/match/actions, then category tabs with current/missing and queued indicators. Search and match correction live under Change match; account and masked credentials live in Artwork settings, with a key prompt shown only when needed. The gallery fills the remaining space, and the side preview starts with current artwork. Apply selections shows its queued category count. The saved key is never sent back to the UI.

Folders distinguish added and automatic sources and availability. Launch settings retain explicit executable, arguments and working folder overrides plus reset to detected launch. File/folder selectors are Windows pickers owned by the native window. Remove from Steam reviews exactly the selected uniquely linked shortcuts, whether managed or manually added, and requires a named confirmation. Manual entries are labeled and require explicit manual-removal consent. Automatic uninstall cleanup still protects manual shortcuts. Both paths retain process/hash guards and backups.

## Backend boundary

`NativeBackend.cs` starts `Native.Service.ps1` without a console and communicates over redirected UTF-8 stdin/stdout. Requests contain an operation and typed data. Secrets use this private pipe, never command-line arguments or request files. Operations are serialized; failures return a bounded public error message. Game identities are resolved against fresh discovery before launch or writes. Plans, provider assets and downloaded paths stay server-side.

The service reuses the existing Core, Steam, Artwork, Removal, Library, Settings and Preparation modules. All existing process, ownership, exclusion, hash, backup, staging and atomic replacement guards remain. Preparation uses its existing worker, durable intent/history and progress queue. EOF requests a cooperative stop and waits for the worker rather than killing it. Windows cannot close while an active native operation may be writing. Steam shutdown is requested only after a native confirmation whose default is Cancel; there is no force kill. A changed preview after shutdown must be refreshed and reviewed.

The snapshot bridge remains separate and does not write Steam files. It initializes per-user storage and can recover malformed app settings. The frontend locates support files beside the extracted release, through parent directories in a source checkout, or through the development override `STEAMNITE_WORKSPACE`. Shared palette tokens live in `design/tokens.json`. App state uses `%LOCALAPPDATA%\Oathgate`, with isolated `OATHGATE_DATA_DIR` overrides for tests. The old host and `--classic` launcher remain available in source builds for rollback comparisons, but the native library does not invoke them. A named user/session mutex prevents concurrent native app instances; the classic app uses the same lease.

## Validation

- Release compilation, existing backend regression suites and UI construction smoke checks.
- `Run-NativeServiceTests.ps1`: identity, scope, account, plan, exclusion, cancellation and single/multi-selection boundaries using isolated settings.
- `Run-NativeClientTests.ps1`: actual private-pipe client, Unicode, concurrent request serialization, errors and graceful lifecycle.
- Live read-only preparation and artwork inspection with the real library; no Steam changes applied during those checks.
- Real Steam add/repair/removal and artwork replacement should be exercised by the user on chosen test games after migration; fixture checks do not substitute for game entitlement or launch verification.

Installation and Steam sync use the same green readiness color; missing/uncertain states are amber and confirmed uninstalls are red. Artwork is green at 5/5 and amber when incomplete. Text labels and tooltips remain available. Covers load after the list is usable, with bounded concurrency and timestamp/length-aware reuse on rescans.

Apply recommended is always visible once a game match is loaded. It fills missing categories while preserving existing art; if all slots are filled, it offers confirmed replacement with recommendations. More also exposes separate fill-missing and replace-all commands. Replacement uses provider rank, backs up originals and preserves categories with no usable recommendation.
