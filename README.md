# ClipboardManager

A simple and elegant clipboard manager for macOS.

[中文文档](README_CN.md)

## Features

- 📋 **Clipboard History** - Automatically saves text and images you copy
- 🔍 **Quick Search** - Find clipboard items instantly
- 📌 **Pin Items** - Keep important items at the top
- 🖼️ **Image Support** - Preview and manage copied images
- ⌨️ **Global Hotkey** - Quick access with `⌘⇧V`
- 🚀 **Launch at Login** - Start automatically with macOS
- 🌐 **Multi-language** - English and Chinese supported
- 🎯 **Drag & Drop** - Drag items to any application
- 💾 **Persistent Storage** - History survives app restarts

## Installation

### Download DMG

Download the latest release from [Releases](https://github.com/yourusername/ClipboardManager/releases) page.

### Build from Source

Requirements:
- macOS 13.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# Clone the repository
git clone https://github.com/yourusername/ClipboardManager.git
cd ClipboardManager

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme ClipboardManager -configuration Release build
```

## Usage

1. Launch the app - it will appear in the menu bar
2. Copy anything - it's automatically saved
3. Click the menu bar icon or press `⌘⇧V` to open
4. Click an item to copy and paste it
5. Hover to see pin/delete buttons

### Keyboard Shortcut

| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open/Close clipboard manager |

### Filters

- **All** - Show all items
- **Text** - Show text items only
- **Image** - Show image items only

## Settings

- **Launch at Login** - Start automatically when you log in
- **Language** - Switch between English and Chinese

## Permissions

The app requires **Accessibility** permission for the global hotkey to work properly.

Go to: System Settings → Privacy & Security → Accessibility → Enable ClipboardManager

## Tech Stack

- Swift 5.9
- SwiftUI
- AppKit
- Carbon (for global hotkey)

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
