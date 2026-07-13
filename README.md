<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="ClipboardManager">
</p>

<h1 align="center">ClipboardManager</h1>

<p align="center">
  <strong>The clipboard manager that thinks for you.</strong><br>
  Auto-strips tracking URLs · Detects sensitive data · Smart-pastes for your target app
</p>

<p align="center">
  <a href="https://github.com/nicebro/ClipboardManager/actions"><img src="https://github.com/nicebro/ClipboardManager/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/nicebro/ClipboardManager" alt="License"></a>
  <a href="https://github.com/nicebro/ClipboardManager/releases"><img src="https://img.shields.io/github/v/release/nicebro/ClipboardManager" alt="Release"></a>
  <a href="https://github.com/nicebro/ClipboardManager/stargazers"><img src="https://img.shields.io/github/stars/nicebro/ClipboardManager?style=social" alt="Stars"></a>
</p>

<p align="center">
  <a href="README_CN.md">中文文档</a>
</p>

<!-- Replace with actual screen recording: open panel → search → URL auto-cleaned → smart paste into VSCode -->
<p align="center">
  <img src="assets/demo.gif" width="600" alt="ClipboardManager Demo">
</p>

---

## Why ClipboardManager?

Most clipboard managers just **record**. ClipboardManager **processes**.

Every time you copy, a rules engine evaluates the content in real time — stripping tracking params from URLs, detecting API keys and credit card numbers, or auto-pinning content from specific apps. When you paste, Smart Paste adapts the format to the target app automatically.

### Feature Comparison

```
                        ClipboardManager    Maccy    Raycast Clipboard
Rules Engine                 ✅              ❌         ❌
Smart Paste                  ✅              ❌         ❌
URL Tracking Removal         ✅              ❌         ❌
Sensitive Data Detection     ✅              ❌         ❌
Regex Transform              ✅              ❌         ❌
OCR (Image → Text)           ✅              ❌         ✅
Fuzzy Search                 ✅              ✅         ✅
Rich Text / Image            ✅              ❌         ✅
iCloud Sync                  ✅              ❌         ❌
Code Syntax Highlighting     ✅              ❌         ❌
Quick Paste (cursor-anchored)✅              ❌         ❌
Paste Stack Mode             ✅              ❌         ❌
Screenshot Auto-Capture      ✅              ❌         ❌
Filter by Current App        ✅              ❌         ❌
100% Open Source             ✅              ✅         ❌
```

---

## ✨ Core Features

### 🔧 Clipboard Rules Engine

Rules run automatically on every copy. Built-in rules (enabled by default):

- **Strip URL Tracking** — Removes `utm_source`, `fbclid`, `gclid`, and 10+ tracking parameters
- **Detect Sensitive Content** — Identifies credit card numbers, AWS keys, SSH private keys; auto-expires in 60s
- **Trim Trailing Whitespace** — Cleans up trailing spaces (off by default)

Create custom rules with regex triggers, app-specific triggers, or content-type triggers. Chain multiple actions per rule.

### 🎯 Smart Paste

Pasting into **VSCode / Obsidian**? URLs become `[domain](url)`, code blocks get fenced.
Pasting into **Terminal / iTerm2 / Warp**? Dangerous characters are escaped automatically.
Pasting into **Slack**? Code is wrapped in backticks.

Smart Paste detects the target app and adapts — no manual formatting needed.

### 📋 Clipboard History

- Text, rich text, and image support
- Fuzzy search with match highlighting
- Pin important items to the top
- Multi-select merge & paste
- Drag & drop to any app

### 🛡️ Privacy First

- Sensitive content auto-detected and auto-expired
- Password manager apps excluded by default
- All data stored locally (iCloud sync is opt-in)
- No telemetry, no analytics, no network calls

### 🔍 OCR

Copy an image → text is extracted automatically via on-device Vision. Search by OCR text.

### ⚡ More

- Global hotkey (`⌘⇧V`, customizable)
- Text transforms: uppercase, lowercase, URL encode/decode, Base64, JSON format
- Export/import backups
- iCloud sync
- Launch at login
- English + 中文

---

## Quick Start

```bash
# Homebrew (coming soon)
brew install --cask clipboardmanager

# — or download the latest .dmg from Releases:
# https://github.com/nicebro/ClipboardManager/releases
```

1. Open ClipboardManager — it lives in your menu bar
2. Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility)
3. Press `⌘⇧V` anywhere to open the clipboard panel
4. Copy something — rules run automatically. Paste — Smart Paste adapts.

### Build from Source

Requirements: macOS 13.0+, Xcode 15.0+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/nicebro/ClipboardManager.git
cd ClipboardManager
xcodegen generate
xcodebuild -scheme ClipboardManager -configuration Release build
```

---

## Architecture

```
Sources/
├── main.swift                    # AppDelegate, panel, hotkey setup
├── ClipboardManager.swift        # Facade — coordinates sub-managers
├── ClipboardImageManager.swift   # Image persistence, cache, OCR
├── ClipboardPreferencesManager.swift # Preference I/O
├── ClipboardSyncCoordinator.swift    # iCloud sync delegation
├── ClipboardMonitor.swift        # NSPasteboard polling
├── ClipboardRuleEngine.swift     # Rules engine (regex, JS, built-in)
├── PasteAdapter.swift            # Smart Paste per-app adapters (30+ apps)
├── FuzzySearch.swift             # Subsequence + scoring search
├── SQLiteHistoryStore.swift      # SQLite storage with migration framework
├── MenuBarView.swift             # Main panel UI
├── SettingsView.swift            # Preferences UI
└── ...                           # Models, cache, utilities
```

Key design decisions:
- **Facade pattern**: `ClipboardManager` delegates to `ImageManager`, `PreferencesManager`, `SyncCoordinator`
- **Rules engine**: Supports regex, JavaScript, and content-type triggers; processes every copy in real time
- **DB migrations**: `user_version` PRAGMA + ordered migration array — safe schema evolution
- **Zero external runtime deps**: only Sparkle (auto-update) as optional dependency

---

## Security

See [SECURITY.md](SECURITY.md) for our security policy, data handling practices, and vulnerability reporting.

---

## Contributing

Contributions welcome! Please open an issue first to discuss what you'd like to change.

See [SECURITY.md](SECURITY.md) for security-related contributions.

## License

[MIT](LICENSE)
