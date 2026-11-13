# Shared visual language

## Oathgate branding preview

Oathgate uses the tagline “Bring your games into Steam.” The original gateway-and-arrow mark is in `oathgate.svg`; `Build-Icon.ps1` regenerates the PNG and multi-resolution Windows ICO (16–256px). The native title bars, window icons and About dialog use this preview. Internal SteamNite names and storage identities stay stable for compatibility.

`tokens.json` defines the palette for both the WinUI library and the classic-hosted workflow dialogs. WinUI loads these tokens on launch, before constructing the library. `src/Theme.ps1` loads the same tokens into `src/DialogTheme.cs` for each workflow host.

Use charcoal backgrounds, slightly raised input surfaces, off-white body text, muted supporting text and blue primary actions. Success, warning and removal colors are deliberately quiet. Segoe UI, rounded action buttons, subdued menus and generous list rows keep the workflows consistent with the library. Preserve visible keyboard focus and disabled states.

Every app-owned workflow applies the shared theme before display, including preparation, artwork, batch artwork, launch overrides, folders, accounts, removal, activity history, Steam shutdown and confirmations/errors. Newly added controls inherit it. Windows file/folder pickers remain system dialogs.

The normal app now implements all workflow screens with native WinUI controls in `winui/NativeWorkflowWindow.cs`. The classic visual layer remains for explicit rollback comparisons through `--classic`. Keep launch identities, selection scope, credential masking, confirmation defaults and write safeguards independent of appearance. The native service retains saved keys server-side; the password field shows a saved-key placeholder rather than receiving the secret.

Validate changes with `tests/Run-ThemeTests.ps1`, the UI construction smoke test, and live inspection. Shared style changes must preserve the conservative No default for Steam-close confirmations.
