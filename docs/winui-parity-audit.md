# Native WinUI parity audit

Baseline: `milestone-v0.2` (`cfe7336`). The native library now opens native workflow windows and calls a headless service. It does not invoke the classic workflow host. The classic interface remains an explicit rollback option through `SteamNite.exe --classic`.

| Capability | Native implementation / preserved backend behavior |
|---|---|
| Six-store discovery, installed and Steam-only games | Existing adapters and conservative evidence; native unified library |
| Covers, readiness, artwork coverage, scan notices | Full-width native list, independent colored status columns, tooltips and on-demand details |
| Search, common chips and overflow filters | Native, composable state and platform filters |
| Ctrl/Shift multiple selection | Row checkboxes plus Ctrl/Shift; tri-state select-all for filtered rows; visible IDs restored through refresh |
| Prepare in Steam / shortcut-only sync | Native selected-game/account preview; current/proposed repairs; existing guarded preparation backend |
| Progress and stopping | Native per-game results; shared queue; cooperative stop; close blocked during active work |
| Retry and interrupted operations | Native history and original-account/current-installation replanning |
| Artwork browsing | Native gallery-first layout, compact category tabs with coverage/queue markers, current-art preview, automatic search/likely or saved match and category refresh; match correction/settings are on demand |
| Thumbnail loading | Progressive, current category/match/query supersedes remaining work after the current bounded HTTP request |
| Artwork replacement | Native queue, current-art preview and coverage; selected categories only; existing backup/rollback backend |
| Recommended artwork | Selected-game or explicit whole-library missing-art fill; existing art is preserved; uncertain matches remain manual |
| Executable overrides | Native executable/arguments/working folder editor, Windows pickers and reset; existing identity-based validation |
| Open folder / copy details | Shared right-click / bottom More menus, single selection and folder availability checks |
| Ignore/unignore | Native context action; fresh identity resolution; exclusions retained across all writes |
| Uninstalled shortcut removal | Native named review of explicit selections, including manual shortcuts with explicit consent; automatic cleanup retains ownership/uninstall rules; both retain duplicate/hash/process checks and backup |
| Scan folders | Native added/automatic/launcher source list; availability; add/remove/save; game files are untouched |
| Steam account preference | Native settings; explicit account shown in every Steam workflow; unavailable preference requires a new choice |
| Steam shutdown/reopen | Native Cancel-default confirmation; normal exit request, cancellable wait, stable closed state; no force kill |
| Concurrency and backups | Existing staging/atomic replacement/hash guards; client sends identities, never client-built plans or provider URLs |
| Shared visual language | Palette tokens, native controls, dark windows, rounded actions, focus/disabled states and overflow actions |
| Default launch | SteamNite.exe / Start-SteamNite.cmd open the native app; classic host is not part of normal navigation |

## Boundary and validation

`NativeBackend` serializes requests over a private UTF-8 pipe. The service keeps plans, provider assets, cached paths and keys in memory; keys never appear in command-line arguments, request files or responses. It resolves current installations and overrides before launch or writes. Account changes invalidate outstanding plans and artwork/removal contexts. The server retains the existing module safeguards instead of duplicating Steam-file logic in the UI.

Only one workflow runs from the main library at a time. Active operations prevent window closure. EOF requests cooperative cancellation and waits for a worker to finish rather than killing it. The library refreshes and restores visible selections after workflow completion.

Validation includes Release compilation, the existing fixture suites, native service boundary tests, actual C# pipe/lifecycle tests and live read-only preparation/artwork inspection. The final full run passed all 21 suites (415 checks), including the isolated native worker lifecycle. No user Steam changes were applied during visual verification.

Real-world acceptance remains user-driven: selected unsynced games, repaired overrides, artwork replacement and backup paths, partial results/retry, uninstall removal, multiple accounts, offline drives, high DPI and keyboard navigation. Native implementation and passing fixtures do not prove game entitlement or gameplay launch success.
