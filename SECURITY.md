# Reporting security issues

Do not post credentials or an exploit containing personal Steam files in a public issue. Once hosted on GitHub, use the repository's private vulnerability reporting feature if enabled. If it is unavailable, open an issue asking for a private contact without publishing the vulnerability details.

This preview has no telemetry or credential-sharing service. Saved SteamGridDB keys use Windows current-user DPAPI protection; unremembered keys stay in process memory. Settings, history, caches and local error reports can reveal library names, account identifiers and local paths. Review and redact files before sharing them.

All Steam changes must preserve preview, confirmation, stale-file validation, backup and ownership safeguards. The Windows user account and local scripts are part of the trust boundary; Oathgate is not a sandbox for untrusted executables or modified support files.
