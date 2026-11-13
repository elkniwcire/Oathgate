# GOG, Ubisoft Connect and EA adapter decisions

Researched and implemented November 6, 2026. These are independently implemented local adapters; no Playnite code, account integration or runtime dependency was added.

## Sources examined

- [GOG installation/launch implementation](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/GogLibrary/GogLibrary.cs): local uninstall registrations, `goggame-<id>.info`, primary tasks, root-game/DLC identity and Galaxy command parameters.
- [GOG client registration](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/GogLibrary/Gog.cs): Galaxy client path registry views.
- [Ubisoft installed-game records](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/UplayLibrary/UplayLibrary.cs) and [launch dispatch](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/UplayLibrary/Uplay.cs): numeric installed product IDs and launcher URI activation.
- [Lutris EA adapter](https://github.com/lutris/lutris/blob/master/lutris/services/ea_app.py): installer manifest content IDs and EA app launch dispatch.
- [EA content-ID/offer-ID interoperability report](https://github.com/lutris/lutris/issues/4996): useful confirmation of a format mismatch, not the sole basis for the implementation.

These interfaces are observed launcher formats, not a promise of vendor API stability. Failures are exposed in scan details. No external game-account authentication is needed.

## Launch policy

GOG prefers Galaxy when its registered executable exists. This preserves the client's normal launch flow. Offline installations can launch directly using their primary manifest task. Multiple distinct primary tasks require an override without Galaxy. Direct launch does not initiate Galaxy cloud sync or overlay.

Ubisoft launches the installed numeric product ID through Connect. Choosing among DX/Vulkan, anti-cheat, edition or bootstrap executables by filename would be brittle. Connect owns those choices; saved executable overrides remain available for intentional exceptions. No claim is made that every title exposes the same renderer-selection dialog.

EA uses the base installer manifest's content IDs, including regional aliases, and retains their order for the launcher. A canonical ID is chosen independently of alias order so reordering alone does not create a different SteamNite identity. Added or removed aliases can still change the canonical ID; cross-release identity reconciliation is not implemented. Games without usable installer metadata are not assigned a guessed EXE or a store ID.

Registry views and repeated folder discovery merge by source identity. Multiple different installation paths remain unresolved. Native Steam manifest matches are excluded before merging, so a separate standalone copy can still be discovered. Saved launch overrides, exclusions, shortcut repair and artwork use the existing shared flows.

## Uninstall safety

A missing recorded path on an available drive is necessary but insufficient. New sources also require readable installation registrations that no longer report the recorded identity. EA must have a previously corroborated registry/content-ID association. Missing keys, inaccessible sources, residual folders or retained registrations preserve the Steam shortcut. Removal remains a reviewed action with a backup.

## Validation

The launcher fixture suite covers manifest parsing, DLC/support-task filtering, ambiguous EXEs, launch arguments, path containment, unsafe XML/URI rejection, stale registrations, regional aliases, registry-view duplicates, conflicting paths, native Steam exclusions, sync/artwork integration and removal protections.

Read-only validation against the user's actual machine detected Othercide via GOG Galaxy and Assassin's Creed II via Ubisoft Connect. Neither game was launched by the validation. No currently installed EA game with a usable base installer manifest was found; EA launch behavior still needs a real installed-title test. Existing EA cache directories were not treated as installed games.

Steam overlay, Steam Input and accurate running-state tracking for these client handoffs remain unverified. The existing script-host executable loads these adapters on the next app start; no host change is required.
