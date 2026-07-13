# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Release distribution is DMG-only via GitHub Releases
- Install docs list only the DMG channel
- Removed iCloud/CloudKit sync; ClipShelf is fully local-only
- Renamed product to **ClipShelf** (bundle id `com.nicebro.ClipShelf`, app `ClipShelf.app`)
- Storage directory is now `~/Library/Application Support/ClipShelf/`
- URL scheme is now `clipshelf://`
- Docs and UI copy: removed marketing comparison table and “smart/thinking” positioning; paste feature described as app-aware paste
- One-time migration from `~/Library/Application Support/ClipboardManager` to `ClipShelf` when the new folder is empty or missing files
- Hot/cold history loading: startup keeps a hot window (~2000 items + pinned); full corpus remains searchable via FTS
- Hot window size is user-configurable in Settings (500–10,000)
- SQLite limited load prefers all pinned items, then fills remaining slots with newest unpinned
- FTS5 query alias fixed (`bm25(clipboard_fts)`), restoring full-text ranking path
- MenuBar auxiliary preview/edit sheets extracted to `MenuBarAuxiliaryViews.swift`
- Index/insert safety guards and thread-safe in-memory history store for tests
- Extracted `ClipboardOCRQueue` and `ClipboardHistoryIndex` from `ClipboardManager` facade
- Extracted `ClipboardPersistenceCoordinator` for snapshot/incremental/use-count writes
- Extracted `ClipboardHistoryOrdering` for pin reorder, hot-window enforce, trim and merge helpers
- Extracted `ClipboardHistoryMaintenance` for expiry wipe / sensitive / auto-cleanup selection
- Extracted `ClipboardPasteboardWriter` for Smart Paste and type-specific pasteboard writes
- Unified history insert path via `insertNewHistoryItem` (dedupe + index + persist + OCR/embedding hooks)
- Cold-store cleanup: `deleteExpired` and `deleteUnpinnedOlderThan` on SQLite/JSON/in-memory stores
- Extracted `ClipboardCaptureDispatcher` for capture→history dispatch + paste-queue enqueue
- Extracted `ClipboardHistoryQueries` for AppIntents content projection helpers
- `ClipboardHistoryOrdering.mergeFetched` centralizes cloud sync merge lanes
- Extended `ClipboardHistoryMaintenance` with unpinned/OCR-candidate helpers
- Split Manager bootstrap wiring into OCR/capture/runtime/cloud-delete helpers
- Added `ClipboardContentCodec` for file-path history content encoding
- `planClearUnpinned` pure helper for clear-all planning
- SQLite cold cleanup unit tests (`deleteExpired` / `deleteUnpinnedOlderThan`)
- Extracted `ClipboardEmbeddingPolicy` for embedding eligibility and startup warm selection
- `reorderedAfterTogglingPin` / `maxUnpinnedCapacity` pure helpers for pin toggle and trim
- Added trim-to-limit manager tests (unpinned eviction + pinned retention)
- Added hot-window unit tests (limit / expand / shrink / pinned retention)
- `saveItems` no longer deletes rows absent from the in-memory snapshot (prevents wiping cold history)
- List UI rebuilds on `historyRevision` instead of every `items` mutation (useCount thrash reduced)
- Search extracted to `ClipboardSearchService` with fuzzy scan cap and cold-item FTS hydration
- Clipboard ingest path extracted to `ClipboardIngestPipeline`
- Monitor idle cadence deepened (`idle` 5s, `deepIdle` 12s) to cut background CPU
- Sparkle import wrapped in `#if canImport(Sparkle)` for local builds without the package
- Script rules harden JS sandbox (block network globals, size limit)

### Added
- Smart Paste expanded to 30+ apps (Email, Messaging, Notes, iWork, plain text editors, extended terminals)
- Database migration framework with `user_version` PRAGMA tracking
- Rules Engine test/preview UI — test rules against sample text before deploying
- Accessibility labels throughout main UI (VoiceOver support)
- ClipboardManager facade split: ImageManager, PreferencesManager, SyncCoordinator
- Sparkle auto-update framework integration
- Rules import/export (`.cliprules` format) for sharing rule sets
- Advanced search syntax (`app:bundleID`, `type:image|text|rich`)
- Settings reorganized into tabbed interface (General / Rules / Sync / About)
- First-launch onboarding overlay (3-step guide)
- Snippet text expansion — type shortcut anywhere to auto-expand
- iCloud image sync via CKAsset
- Script API documentation (`docs/SCRIPTING.md`)
- SECURITY.md with vulnerability reporting policy
- Homebrew Cask formula
- CHANGELOG, CONTRIBUTING guide, issue/PR templates
- Release CI workflow with conditional code signing and notarization

### Fixed
- Panel now force-refreshes clipboard on show (no stale content after ⌘C → ⌘⇧V)
- Potential deadlock in `PersistenceScheduler.flush()` when called from main thread
- `DataPortService` in Settings now uses SQLite store (consistent with runtime)
- Bundle identifier updated from placeholder to `com.nicebro.ClipboardManager`

### Changed
- PasteAdapter code deduplicated — shared `looksLikeCode()` and shell escape utilities
- FuzzySearch performance: subsequence early filter, length pre-check, debounce 0.15s
- Clipboard monitor idle interval increased from 1.5s to 3.0s (saves CPU in background)
- Image cache memory budget reduced from ~320MB to ~128MB total
- OCR and CloudSync migrated to async/await (Swift concurrency)
- SQLite `TRANSIENT` destructor extracted to a named constant for clarity

## [1.0.0] - 2026-02-05

### Added
- Clipboard history with text, rich text, and image support
- Fuzzy search with match highlighting
- Pin, delete, multi-select merge & paste, drag & drop
- Clipboard Rules Engine (strip URL tracking, detect sensitive content, trim whitespace)
- Custom rules with regex triggers, app triggers, content-type triggers
- JavaScript scripting support for custom rule actions
- Smart Paste (adapts format for VSCode, Obsidian, Terminal, iTerm2, Warp, Slack)
- OCR via on-device Vision framework
- Text transforms (uppercase, lowercase, URL encode/decode, Base64, JSON format)
- Global hotkey (⌘⇧V, customizable) and queue paste hotkey (⌘⇧B)
- Snippet manager with text expansion shortcuts
- iCloud sync via CloudKit
- Export/import backups
- SQLite storage with migration from JSON
- Launch at login
- English + Chinese localization
- Zero third-party dependencies
