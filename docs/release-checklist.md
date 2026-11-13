# First public preview

## Automated locally

- Run `Run-Checks.ps1` after closing the app. Tests must use isolated storage.
- Run `Build-Release.ps1`; review `files.sha256.json` and the ZIP contents. Never zip the workspace itself.
- Run `Export-Source.ps1`. The export includes current source changes, excludes local data/builds and omits `.git` entirely.
- Run the distribution checks after packaging, so they inspect the staged release as well as source.

## First GitHub publication

- The development repository starts from sanitized source with a fresh initial commit. Continue working here with normal commits and pushes; a repeated source export is unnecessary.
- Older milestone history is a private rollback archive under ignored `artifacts/`. It contains historical account/path details. Never publish that archive, import its old branches/tags into the public repository, or attach its bundle. Editing today's files does not sanitize older commits.
- Inspect staged changes and run the source leak checks before pushing. Keep local state and archives ignored.
- Confirm the MIT license choice and contributor identity. Enable private vulnerability reporting if available. Review repository permissions and issue templates.
- Run the Windows GitHub Actions workflow from that clean repository. Local checks are not a substitute for a successful clean-host build.
- Publish the resulting ZIP and SHA-256 file as a prerelease. Keep the source and binary versions aligned. Do not upload `data`, `.tools`, test fixtures' output, or staging directories.

## Manual validation still required

- Fresh Windows user or VM, outside a source checkout; no developer SDK on PATH. Extract the portable ZIP into a path containing spaces and non-ASCII characters and start it.
- No Steam installed; Steam with one account; Steam with several accounts; a previously saved account that has disappeared. No writes should happen until a valid account is selected.
- Empty libraries, inaccessible/offline drives, games on another drive, no SteamGridDB key, an invalid key, and network failure.
- Add one chosen game to Steam, launch it from Steam, replace artwork, then uninstall it and review removal. Confirm unrelated/manual shortcuts are preserved unless explicitly selected for removal.
- Update into a different app directory and confirm settings/ownership/history survive. Check backup restoration with a disposable Steam profile.
- Open the app twice; only one instance should remain. Confirm an active preparation cannot be closed halfway through a write.

The release is an unsigned Windows x64 preview. Code signing, an installer, an updater, and an onboarding flow can follow later.
