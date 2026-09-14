# Security Policy

ClipShelf handles data you copy — including, occasionally, secrets. If you find a
vulnerability, please report it privately.

## Reporting a Vulnerability

- Preferred: open a report via
  [GitHub Security Advisories](https://github.com/shiaho777/clipshelf/security/advisories/new)
  for this repository.
- Do not file a public Issue for undisclosed vulnerabilities.

Please include steps to reproduce, affected versions, and whether the issue can
expose clipboard contents, stored history, or the script-rule sandbox.

## Supported Versions

Only the latest release receives security fixes.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Older releases | No |

## Scope Notes

ClipShelf is a local-only utility: no account, no cloud sync, no telemetry.
Sensitive items are stored AES-GCM-encrypted in the local database, password
managers are excluded from capture by default, and custom script rules run in a
sandboxed `JSContext` with no network or filesystem access.
