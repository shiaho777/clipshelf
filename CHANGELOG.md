# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.3] - 2026-09-14

### Fixed
- `MARKETING_VERSION` in `project.yml` is now the single version source of truth: `Info.plist` reads `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` instead of a hardcoded literal, so the documented "bump `MARKETING_VERSION`" release step actually changes the version the app reports
- Homebrew cask: the download URL 404'd (`version :latest` interpolated into a versioned asset name). The cask is now pinned to a real version + SHA256 with a `livecheck` block, and `zap` also removes the LaunchAgent fallback plist and saved-state data
- README test command pointed at the `ClipShelf` app scheme, which has no test action; both READMEs now use the `ClipShelfTests` scheme matching CI
- `docs/SCRIPTING.md` documented a fresh `JSContext` per invocation — contexts are actually cached per script (globals persist), and the doc now covers the timeout quarantine and the 50 KB script size cap
- Update checker: tapping "check" while a check was already in flight fired a second concurrent request
- Snippet expansion no longer captures keystrokes into its match buffer when Command or Control is held (e.g. ⌘V no longer appends "v"), ignores its own synthesized keystrokes, and stays out of secure input fields (passwords)
- CONTRIBUTING referenced a nonexistent `PasteAdapterManager.adapters`; adapters register via the `allAdapters` array
- Locked sensitive items could be read through Preview, Edit, the Space/E shortcuts, multi-select merge/queue/diff, drag previews, and the Quick Paste context menu — every path now goes through the same biometric unlock, and a successful paste unlock marks the item for the session
- Queue/stack paste could capture ClipShelf's own panel as the target app and simulate ⌘V into itself; the target is captured before the panel activates and the frontmost app is re-validated before the keystroke
- A timed-out JS script quarantined unrelated scripts that ran afterwards, and `JSContext` was configured on a different thread than it executed on — script contexts are per-script, single-queue, and quarantine is scoped to the script that actually timed out
- User-supplied rule regexes could stall capture indefinitely; matching/replacement now runs on a bounded queue with a 200 ms timeout that quarantines the pattern, and inputs over 4 MB are skipped
- `contentType` rules never matched file URLs, and `replaceRegex`/`trimWhitespace` on rich text left a stale RTF payload that disagreed with the new plain text — rich text is demoted to plain text when its text is rewritten
- Two identical file-URL copies compared unequal because `CapturedContent.==` had no `.fileURL` case
- Built-in rules merged by name, so renaming one spawned a duplicate on next launch; merging is now by stable built-in ID and retired built-ins are dropped
- Asynchronous persistence could resurrect deleted items and wiped the `embedding` column on every update — the SQLite upsert preserves embeddings, deletions record tombstones so late writes/import/sync can't recreate rows, `PRAGMA busy_timeout` is set, sensitive rows no longer persist plaintext `ocr_text`, and legacy unencrypted sensitive rows are migrated in place
- Replace-style history import never removed rows missing from the import file (save is merge-only); `replaceHistoryForImport` now deletes the absent IDs explicitly
- Deleting a hot item could remove an image file still referenced by cold-storage rows; image deletion now consults `allImageFileNames(excludingIDs:)` across the store and memory first
- Initializing encryption a second time overwrote the Keychain key and bricked the database — an existing key is reloaded instead of replaced
- The OCR watchdog could clear `isProcessing`/`currentOCRItem` state belonging to a newer item after a timeout
- Export now uses `exportableItems` so sensitive payloads are not written as plaintext
- Cold-storage deletions (expiry sweep, age cleanup, trim) now update tombstones, counts, OCR/embedding caches, image files, and Spotlight consistently instead of leaving ghosts
- The app-hosted test bundle launched the full app — touching the real history DB, `NSPasteboard.general`, global hotkeys, and login state — `applicationDidFinishLaunching` now returns early under XCTest and tests use uniquely named private pasteboards
- Two ordering tests sat outside the XCTestCase class and were silently never run
- Snippet expansion could overwrite a clipboard the user changed inside the 150 ms restore window; restore is skipped when `changeCount` has moved
- The hotkey recorder never became first responder, so recorded keys never reached it
- Rapid captures could be stored out of order when a slow rule/script ran; the ingest pipeline serializes rule processing in capture order
- Quick Paste re-ran a full history search on every render
- Launch at login could silently fail when more than one copy of the app was registered (e.g. a DerivedData debug build plus the `/Applications` install): both copies launched at login and the duplicate-instance check could make them terminate each other. Resolution is now deterministic — an exact-path duplicate exits, a development-build copy yields to a real install, and otherwise the earliest-launched instance wins, so exactly one instance survives

### Removed
- Dead `SUFeedURL` from `Info.plist` (no Sparkle feed exists; updates are handled by the GitHub-releases checker)
- Unused `evaluateScriptSetup` helper in `ScriptRuleRunner`

### Added
- `SECURITY.md` with a private vulnerability-reporting channel (promised since 1.1.0 but never shipped)
- `type:file` search filter in Quick Paste / history search
- Launch-at-login now surfaces the "pending approval" state: when macOS holds the login item for user approval, Settings shows a hint and opens System Settings → Login Items directly

## [1.2.2] - 2026-09-10

### Removed
- All comments from Swift sources, tests, and Localizable.strings — the codebase is now comment-free by policy (see AGENTS.md); the only remaining `//` occurrences are inside string literals such as URLs and regex patterns

### Added
- AGENTS.md: guidance for AI coding agents covering build/test commands, the architecture map, project conventions (including the no-comments rule), and the Issue-first PR delivery loop with the CI `build-and-test` job as the merge gate

## [1.2.1] - 2026-09-07

### Changed
- Smoother scrolling in the history list: image rows resolve already-cached thumbnails synchronously on their first frame instead of swapping a placeholder for the photo a beat later, and thumbnails for the visible page are prefetched whenever the list updates
- The code badge on text rows is computed synchronously (cached per content) instead of popping in a frame after the row appears
- Image rows, Quick Paste, and drag previews only show OCR text when it contains at least 3 usable words — screenshots of music players, games, and other stylized UI no longer show glyph soup next to the thumbnail; the full OCR text stays searchable and visible in Preview
- New OCR results drop low-confidence (< 0.5) Vision observations before storing, so stylized fonts stop polluting saved OCR text

### Fixed
- The version string shown in Settings now matches the release version (the 1.2.0 build still reported 1.1.2)

## [1.2.0] - 2026-09-03

### Added
- Status bar right-click menu: Open ClipShelf, Settings (`⌘,`), Quit (`⌘Q`)
- Preview sheet "Open with Default App" button: images open in Preview, text/RTF in TextEdit, files with their default app; sensitive items require Touch ID first
- List rows show the source app icon + name and use count next to the timestamp
- Secret-looking tokens (API keys, private keys, card numbers) are auto-masked in list and Quick Paste rows with a per-row reveal button
- Quick Paste footer hint for keyboard shortcuts

### Changed
- Removed the main-panel `⌘1-9` quick-paste shortcuts and row badges: they often failed to fire and conflicted with frontmost-app shortcuts
- Filter bar collapsed from two rows into a single scrollable strip
- Footer buttons now show text labels instead of icon-only
- Settings tab switches animate with a directional slide matching the filter chips (was a hard cut)
- Image rows show a larger thumbnail plus the OCR first line instead of a bare `[Image]` label
- Popup sheets open beside the main panel instead of covering it
- Body text contrast raised for the HUD vibrancy background

## [1.1.2] - 2026-09-01

### Added
- Check for Updates on the About page: checks GitHub Releases, downloads the DMG with a progress bar and live download speed, then installs by opening the disk image in Finder (drag ClipShelf into Applications)
- Settings now open inside the main panel instead of a separate window, with the same HUD vibrancy as the panel

### Fixed
- Settings: the selected tab and export format no longer reset when re-entering the settings page
- Settings UI: control rows are now aligned and the colored warning icons are gone
- A batch of audit fixes across persistence, rules and panel lifecycle: double-paste, tombstone overflow, sync merge drift, stale flush, database close race, FTS AND semantics, Spotlight resurrection, UTType crash, test-rules page switching, hotkey rebind rollback, sensitive+pin handling, image provider lifetime, JSON import limits, and a duplicate panel-monitor leak

## [1.1.1] - 2026-08-30

### Fixed
- The panel's traffic-light close button (✕) rendered but was disabled: the window mixed `.titled` with `.borderless` in its style mask, which makes NSPanel display non-functional buttons. The close button is now enabled and clicking it hides the panel while ClipShelf keeps running in the menu bar (`windowShouldClose` → `hidePanel`). Zoom and miniaturize stay disabled; Esc / hotkey / outside-click closures unchanged

## [1.1.0] - 2026-08-29

### Fixed
- Hotkey customizations were silently reset on every relaunch: assigning the stored main hotkey during load fired `didSet`, whose `saveConfig()` persisted the not-yet-loaded default queue/quick-paste keys over the user's saved values (`HotKeyManager`)
- Sensitive items became unrecoverable when AES-GCM encryption failed at write time: the plaintext was replaced by the `[🔒 Sensitive]` placeholder without storing any ciphertext. Writes now keep plaintext as a fallback instead of destroying content
- A failed image copy no longer clears the pasteboard while writing nothing, and no longer increments use counts or acknowledges the pasteboard change (`ClipboardPasteboardWriter`)
- Paste fallback: if the target app failed to activate within the timeout, ClipShelf injected ⌘V into whatever window had focus, potentially inserting sensitive clipboard content into the wrong app. It now verifies frontmost identity before simulating the keystroke
- `SearchClipboardHistoryIntent` crashed the process when Shortcuts passed a negative Limit (`prefix(_:)` precondition)
- Crash in `applicationWillTerminate` when termination happens before launch setup completes
- Out-of-range crash in fuzzy scoring when a query matched at the first character of the content (`subsequenceScore`)
- Panel now force-refreshes clipboard on show (no stale content after ⌘C → ⌘⇧V)
- Potential deadlock in `PersistenceScheduler.flush()` when called from main thread
- `DataPortService` in Settings now uses SQLite store (consistent with runtime)
- Bundle identifier updated from placeholder to `com.nicebro.ClipboardManager` (superseded by the `com.nicebro.ClipShelf` rename in this release)

### Security
- Script rules that never return (infinite loop) are quarantined after the timeout and the evaluation queue is rotated, so one bad script can no longer disable all script rules until relaunch; quarantined scripts are skipped without spending another timeout window (`ScriptRuleRunner`)
- CSV export neutralizes spreadsheet formula injection for cells beginning with `=`, `+`, `-`, `@`, tab, or CR
- Added a single-instance guard: two menu-bar instances would fight over the pasteboard and status item. This also covers the LaunchAgent fallback, whose `launchctl bootstrap` starts the job immediately (`RunAtLoad`)

### Performance
- Panel rendering: skip per-row image-URL construction and file-path parsing for text rows; content detection (regex + filesystem stat) runs only for text/richText rows; search highlighting builds contiguous styled runs instead of one `Text` per matched character; history-revision change detection compares item IDs directly instead of building a joined UUID string on every copy
- Search: fuzzy matching and scoring operate on Unicode scalar arrays (scoring ~1.9× faster in micro-benchmarks, subsequence gate ~20× faster); `matchedIndices` reuses one scalar array across query tokens; the semantic-search query embedding is cached so repeated keystroke searches stop recomputing the NLEmbedding vector
- Persistence: SQLite prepared statements for the incremental write path (upsert, delete, use-count updates) are compiled once and cached; the legacy-directory migration check in `AppStoragePaths.defaultStorageDirectory()` is memoized to one run per process

### Changed
- `EncryptionService` key initialization is now thread-safe; the persistence and incremental-persistence queues can reach it concurrently on first use
- Image cache: shared image data is inserted with a byte cost so entries actually count against `totalCostLimit` and get evicted under memory pressure
- `PersistenceScheduler` guards its pending work item with a lock (mutated from both the caller thread and the scheduler queue)
- FTS LIKE-fallback search escapes `%`/`_` wildcards so queries like `100%` match literally
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
- PasteAdapter code deduplicated — shared `looksLikeCode()` and shell escape utilities
- FuzzySearch performance: subsequence early filter, length pre-check, debounce 0.15s
- Clipboard monitor idle interval increased from 1.5s to 3.0s (saves CPU in background)
- Image cache memory budget reduced from ~320MB to ~128MB total
- OCR and CloudSync migrated to async/await (Swift concurrency)
- SQLite `TRANSIENT` destructor extracted to a named constant for clarity

### Added
- Smart Paste expanded to 30+ apps (Email, Messaging, Notes, iWork, plain text editors, extended terminals)
- Database migration framework with `user_version` PRAGMA tracking
- Rules Engine test/preview UI — test rules against sample text before deploying
- Accessibility labels throughout main UI (VoiceOver support)
- ClipboardManager facade split: ImageManager, PreferencesManager, SyncCoordinator
- Rules import/export (`.cliprules` format) for sharing rule sets
- Advanced search syntax (`app:bundleID`, `type:image|text|rich`)
- Settings reorganized into tabbed interface (General / Rules / Sync / About)
- First-launch onboarding overlay (3-step guide)
- Snippet text expansion — type shortcut anywhere to auto-expand
- Script API documentation (`docs/SCRIPTING.md`)
- SECURITY.md with vulnerability reporting policy
- Homebrew Cask formula
- CHANGELOG, CONTRIBUTING guide, issue/PR templates
- Release CI workflow with conditional code signing and notarization

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
