# POC validation — November 5, 2026

- Built `SteamNite.exe` using Windows PowerShell's built-in C# compiler; no SDK or downloaded dependencies.
- All 21 fixture checks passed (`tests/Run-Tests.ps1`). They cover Xbox helper selection, missing config IDs, package activation, ambiguous entry points, content/development exclusions, Epic identity/DLC/incomplete/missing-folder handling, Amazon installed-only filtering, Unicode, and SQLite read-only enforcement. Launch dispatch was checked without launching fixture executables.
- The native window scanned the actual current user's launcher records in the background and displayed 10 Xbox games on D:. Each resolved to a manifest-selected Xbox launch helper.
- The C: Forza Horizon 5 directory contained only a logo and was excluded. ARK DLC directories had no executable list and were excluded.
- Selected Valheim in the actual interface, clicked Launch game, and observed the Valheim game window reach the opening cinematic. This validates startup, not gameplay, overlay behavior, Steam Input, or playtime tracking.
- Epic's manifest directory contained no installed-game `.item` records. Amazon's installed-game database returned no installed games. Their real launch flows remain untested; adapters passed synthetic fixture checks.
- The actual scan reported an access error for the protected manifest of one ARK DLC package and continued. No ownership or permissions were changed.

Reports and settings live in the ignored `data/` directory. A terminal running inside the Codex sandbox sees redirected user paths and may fail package enumeration; the normal app runs in the user's Windows session and reads the real records.

## Manual Steam import

- All 25 Steam-specific fixture checks passed (`tests/Run-SteamTests.ps1`), alongside the original 21 discovery/launch checks. Steam tests exercise binary VDF handling, a known CRC32 vector, Unicode, field casing, malformed files, ID collisions, exact preservation, backups, running-client guards, stale previews, duplicate detection, and first-file creation. Real Steam files are not modified by these tests.
- Imported only Valheim into Steam account `<test-account>` after the user exited Steam. Existing shortcut count: 8; resulting count: 9. Verified every original byte before the two closing VDF terminators remained unchanged.
- Backup: `<Steam>\userdata\<test-account>\config\shortcuts.vdf.steamnite-<timestamp>.bak`.
- New shortcut ID: `2325823140`. Executable: `<Xbox library>\Valheim\Content\gamelaunchhelper.exe`. Working directory: `<Xbox library>\Valheim\Content`.
- Reopened Steam. Direct inspection of the Steam library and launch test could not complete because Computer Use app approval timed out. Steam launch and Big Picture behavior remain to be confirmed by the user.
- Reopened the updated SteamNite interface, selected Valheim, and verified the actual preview showed 9 existing entries, 0 additions, and **KEEP EXISTING Valheim**, with Apply disabled.
- The current discovery scan now finds 12 games, including Epic's Disco Elysium and Amazon's Squirrel with a Gun. The user reports tested games launch successfully from the discovery app. Steam imports for those clients are not yet validated.

## SteamGridDB artwork

- User subsequently confirmed that games added through manual sync launch successfully from Steam.
- All 39 artwork fixture checks passed, plus the existing 25 Steam sync and 21 discovery/launch checks (85 total). Main and artwork dialog construction smoke checks also passed.
- Artwork tests cover current-user DPAPI key storage/forgetting with synthetic credentials, approved image hosts, API query encoding and endpoint-specific MIME filters, image decoding/normalization, invalid and oversized payloads, correct unsigned Steam ID filenames, existing image/icon preservation, targeted icon-field editing with exact backups, stale shortcuts, Steam process guards, staged validation, and rollback of newly created files if icon registration is interrupted.
- Opened the actual Valheim artwork window. The user entered the key into its masked field and enabled Remember key. The key was never printed, copied by the agent, or put in source code, scan exports, or match records.
- Live search returned Valheim (`29531`) and Valheim Dedicated Server as distinct matches. Selected the game, fetched candidates for all five artwork slots, and displayed the downloaded 600x900 cover by Yamstreed (`645972`). The download was decoded, cached as PNG, and displayed in the app preview.
- Live integration exposed a SteamGridDB constraint: logos/icons reject JPEG in their MIME filters. Restricted those endpoints to PNG and added a regression check; grids/heroes continue to request PNG/JPEG.
- No real Steam artwork was applied by the agent during this validation. The window is left open for the user to choose images and apply them after exiting Steam. Actual Steam rendering of the artwork remains to be confirmed.

## Thumbnail grid and automatic recommendations

- Replaced the artwork text list with a scrollable thumbnail grid. Verified live Valheim covers render in three columns at the current window size, with artist labels and the first provider-ranked result marked Recommended. Clicking that tile successfully loaded the larger preview. Thumbnail aspect ratios are preserved.
- Added Apply recommended, available after selecting a game match, without requiring Load artwork first. It downloads the first usable result per missing category and uses the existing validated apply flow. Existing artwork and custom icons are skipped; unavailable categories are reported. Real automatic application was left for user testing because Steam was running.
- Provider result order is now preserved; sorting locally by hidden/zero score fields previously scrambled it. Recommendations follow SteamGridDB's ranking, not a claimed exact raw-vote maximum.
- All 47 artwork checks passed. New checks cover provider-order preservation, download fallback, existing-slot preservation, unavailable categories, stopping at the first usable image, shared application/backup behavior, thumbnail failure isolation, and approved thumbnail URLs. Main and artwork-window construction smoke checks also passed.
- The current real profile shows an existing Valheim cover, which the new dialog correctly marks as preserved. No real Steam artwork was changed by the agent while validating these two UI changes.

## Separate per-game and all-games actions

- Renamed the individual game's action to **Apply all recommended art**, explicitly covering all five missing categories for that game.
- Added **Recommended art for all...** to the main window with Steam account selection, a masked key field, per-game status, and stop-after-current behavior. The batch is scoped to the discovered catalog and only applies to already synced shortcuts.
- All 16 batch checks passed: exact normalized title matching, edition/sequel distinction, ambiguous-title handling, saved identity reuse, no work while Steam runs, unsynced skips, complete-slot fast path, partial results, credential-free persistence, fresh per-game contexts, and stopping on rate limits. Tests use mocked APIs and do not modify the user's Steam files.
- Main, individual artwork, and batch dialog construction smoke checks passed. Real batch processing remains available for user testing; no full-library artwork writes were performed by the agent.

## Automatic artwork browsing

- Removed the Search games and Load artwork buttons. Opening the artwork window now queues a search, selects the most likely result, and loads that result's current category and thumbnails. Saved IDs are preferred; otherwise exact normalized titles win, followed by title overlap with penalties for unrequested demos, soundtracks, trailers and dedicated servers.
- Editing the query/pasting a key debounces a new search. Choosing another search result clears the old game choices and loads the new game's artwork. Category changes lazily fetch only that category and reuse already fetched category data. Apply all recommended art still fetches the complete set of categories if browsing has only populated one.
- Request generations suppress stale results. Match/category/query controls remain usable during preview loading; obsolete thumbnail batches stop before the next download. Existing artwork application still requires an explicit button press with Steam closed.
- Observed the updated native window showing Disco Elysium selected, the Hero category thumbnail grid populated, and no manual Search/Load controls. No Steam artwork was written during this check.
- All 55 artwork checks and 16 bulk checks passed, plus all three UI construction smoke checks. New tests cover exact/saved/edition/likely match selection, dedicated-server/demo downranking, empty searches, single-category API requests, and obsolete-thumbnail cancellation.

## Visible Steam sync status

- Added a color-coded Steam sync column, separate from launch status, with a Steam account selector above the list. Hover text and selected-game details explain missing/ambiguous shortcut states.
- Sync/artwork now share the same game identity/launch-target matcher. Title-only conflicts, duplicate matches, unresolved recipes, missing account selection, and unreadable shortcut data are distinct from Not synced.
- Indicators refresh after discovery and successful imports; a three-second check detects changes to the selected Steam shortcut file without repeatedly rebuilding unchanged lists. Selected games are retained during refreshes.
- All 33 Steam checks and 55 artwork checks passed. Eight new checks cover matched IDs, renamed targets, title conflicts, missing shortcuts, account selection, unresolved recipes, malformed files, and duplicate matches. All three UI construction smoke checks passed. Status checks do not write Steam files.

## Steam close-and-continue and sync-to-artwork handoff

- All UI apply paths (shortcut sync, manually selected artwork, recommended artwork and bulk artwork) now share a close-and-continue prompt. Only consent dispatches `steam.exe -shutdown`. A timer-driven modal waits for the client to exit, allows cancelling the wait, and times out after 45 seconds without force-killing processes or authorizing writes.
- Shortcut sync rebases onto the file Steam saves while exiting. If the selected-game action signature changes, the preview is refreshed for another review. Artwork refreshes its shortcut context after closure and checks that the app ID remains the same. Existing final running-client/stale-data guards remain active in the writers.
- The checked-by-default Choose artwork after syncing option hands one newly added game to its artwork window or multiple new games to a scoped batch, carrying the selected Steam profile. Individual and batch artwork windows now offer Open Steam, so the client can remain closed throughout the workflow.
- All 39 Steam checks and 8 session-flow checks passed. New tests validate graceful shutdown command construction, missing executable handling, rebase preservation, changed-action detection, already-closed behavior, declined consent, cancelled waiting and timeouts. Session tests use stubs and never control the user's real Steam processes. All three UI construction smoke checks passed.
- Actual shutdown prompts and sync-to-artwork handoff are implemented for user testing; the agent did not close the user's Steam or write additional real shortcuts/artwork while validating this change.

## Manual uninstalled-game removal testing

- Added Review removals with a background read-only preview, Steam account selection, unchecked candidate rows, explicit removal confirmation, the existing graceful Steam-close flow, revalidation and Open Steam. Only explicit SteamNite ownership markers can authorize a removal; manual shortcuts and artwork are preserved.
- Retained install history is seeded from previous scan data and merged on subsequent scans without deleting missing game records. Candidate detection requires both a missing recorded path on an available drive and readable authoritative platform records no longer listing that identity. Failed/missing sources, inaccessible paths, unknown history, active registrations, residual content and duplicate IDs prevent removal.
- Binary removal reindexes survivor container keys for Steam but copies every surviving property byte. The selected IDs must be unique managed entries. Save rechecks the selected candidates and file hash, then uses atomic replacement with an exact `steamnite-remove` backup. No game or artwork deletion is implemented.
- All 33 removal checks passed, covering history retention, unavailable drives, unknown paths, all three platforms, manual preservation, active registration, missing history, failed scans, native writer restrictions, reindexing, empty selection, running Steam, reinstalls/content reappearing, selection restrictions, backups, unchecked entries, stale previews and temporary-file cleanup. All 39 Steam and 55 artwork regression checks passed. All four UI construction smoke checks passed.
- Ran the actual read-only preview against the current user profile: 11 shortcuts, all Keep, zero removal candidates, no platform notices. The managed games still had their recorded installations; manual entries were explicitly preserved. The agent did not uninstall games or remove real Steam shortcuts. A user-controlled uninstall/removal test remains next.

## Removal checkbox event fix

- The user's Squirrel with a Gun uninstall was detected, but checking the candidate raised an array-index-null exception. The ItemCheck handler used `$args` as a parameter name, conflicting with PowerShell's automatic argument variable.
- Replaced it with an explicitly captured event handler using `$eventArgs`, bounds/metadata guards, and counting based on the proposed new check state. Protected entries remain uncheckable without interfering with other checked candidates.
- All 11 new tests passed against an actual hidden native ListView and the production event delegate, including the first checkbox click, unchecking, multiple selection, manual/unverifiable entries, missing metadata, and busy-preview state. All 33 removal checks and all four UI construction smoke checks also passed. No real shortcuts were removed.

## Unified installed and Steam-only library

- The main Game library merges detected installed games with the selected account's non-Steam shortcuts. Matching installs/shortcuts appear once. Separate Install state and Steam sync columns can show Not installed + Synced. All games / Installed / Not installed / Steam only filters use the same list; manual shortcuts are included but protected.
- Confirmed uninstalled managed rows can be selected directly and removed with Remove from Steam. The confirmation names those games; the existing shutdown, revalidation, backup and removal guards are reused. Unverified, not-detected and manual rows cannot authorize removal. Installed-game launch/sync/artwork actions are disabled for Steam-only entries.
- Steam-only inventory checks and merging run in a background runspace. Generation checks prevent an older account/scan result from replacing the latest library. Counts, row state and removal eligibility refresh after writes.
- All 13 new merge checks and all 33 removal checks passed. The merge tests cover deduplication, separate installation/sync states, actual shortcut IDs/history, absent launch recipes, uncertain/offline entries, manual protection, profile-less operation, unresolved detected games, legacy target matching and an empty installed catalog. All four UI construction smoke checks passed.
- Opened the updated native window and verified the live combined list: 13 installed games and 15 total entries, including two protected manual shortcuts, without duplicate installed/synced entries. No confirmed-uninstalled shortcut remained in the current profile at validation time. No real removals or game uninstalls were performed by the agent.
