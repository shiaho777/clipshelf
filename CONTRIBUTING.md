# Contributing to ClipboardManager

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

**Requirements:**
- macOS 13.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# Clone
git clone https://github.com/nicebro/ClipboardManager.git
cd ClipboardManager

# Generate Xcode project
brew install xcodegen
xcodegen generate

# Open in Xcode
open ClipboardManager.xcodeproj
```

## Project Structure

```
Sources/
├── main.swift                # App entry point, AppDelegate
├── ClipboardManager.swift    # Core coordinator
├── ClipboardMonitor.swift    # Pasteboard polling
├── ClipboardRuleEngine.swift # Rules processing pipeline
├── PasteAdapter.swift        # Smart Paste adapters
├── SQLiteHistoryStore.swift  # Primary persistence
├── FuzzySearch.swift         # Search algorithm
├── MenuBarView.swift         # Main panel UI
└── ...
Tests/
├── Mocks/TestMocks.swift     # Shared test doubles
└── *Tests.swift
```

## How to Contribute

1. **Open an issue first** — Discuss what you'd like to change before writing code.
2. **Fork & branch** — Create a feature branch from `main`.
3. **Write tests** — All new logic should have corresponding tests.
4. **Run tests** before submitting:
   ```bash
   xcodebuild test \
     -project ClipboardManager.xcodeproj \
     -scheme ClipboardManagerTests \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO
   ```
5. **Update CHANGELOG.md** with your changes under `[Unreleased]`.
6. **Submit a PR** — Fill out the PR template.

## Code Style

- Swift 5.9, no third-party dependencies
- Use `os.Logger` for logging (not `print`)
- All persistence layers use protocol abstractions for testability
- UI follows existing SwiftUI patterns in the codebase

## Adding a Smart Paste Adapter

1. Create a struct conforming to `PasteAdapter` in `Sources/PasteAdapter.swift`
2. Add target bundle IDs and implement `adapt(_:type:)`
3. Register it in `PasteAdapterManager.adapters`
4. Add tests

## Adding a Clipboard Rule Action

1. Add a new case to `RuleAction` in `Sources/ClipboardRule.swift`
2. Handle it in `ClipboardRuleEngine.process()`
3. Add UI in `RulesSettingsView` and localization strings
4. Add tests

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
