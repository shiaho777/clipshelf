# Security Policy

## Supported Versions

| Version | Supported          |
|---------|-------------------|
| 1.x     | ✅ Active support  |


## Local builds and Gatekeeper

Unsigned or ad-hoc builds may be reported as damaged after download. This is a local quarantine attribute:

```bash
xattr -cr /Applications/ClipShelf.app
```

ClipShelf does not phone home; clearing quarantine only affects the local file flags.

## Reporting a Vulnerability

If you discover a security vulnerability, **please do NOT open a public issue**.

Instead, email **security@nicebro.dev** with:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide an initial assessment within 7 days.

## Data Handling

### Local Storage

- All clipboard data is stored locally in `~/Library/Application Support/ClipShelf/`
- History is persisted in a SQLite database (`history.db`) with WAL journaling
- Images are stored as individual files in the `images/` subdirectory
- Preferences are stored as JSON files in the same directory

### Sensitive Content

- ClipShelf automatically detects potentially sensitive content (credit card numbers, API keys, SSH private keys, access tokens) using pattern matching
- Detected sensitive items are marked with `isSensitive` and auto-expire after 60 seconds by default
- When sensitive items expire or are cleared, content is zero-filled in memory before removal
- The `clearSensitiveItems()` function overwrites content with null bytes before deleting

### Password Manager Exclusion

The following password manager apps are excluded from clipboard monitoring by default:

- 1Password
- Apple Keychain Access
- Bitwarden
- KeePassXC
- LastPass
- Dashlane

Users can add additional excluded apps in Settings.


### Network

- ClipShelf keeps clipboard history local; no account or cloud sync is required
- No telemetry, no analytics, no crash reporting
- OCR is performed entirely on-device using Apple Vision framework

### Sandboxing

- The app requires Accessibility permission for global hotkey and auto-paste functionality
- App Sandbox is disabled to support Accessibility features; Hardened Runtime is enabled

## Custom Script Rules

- User-defined JavaScript rules execute in a sandboxed `JSContext`
- `setTimeout` and `setInterval` are removed from the JS environment
- Scripts have a 3-second execution timeout
- Scripts cannot access the filesystem, network, or any system APIs
