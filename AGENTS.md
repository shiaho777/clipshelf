# AGENTS.md

Guidance for AI coding agents working in this repository. For the human-facing
contribution guide see [CONTRIBUTING.md](CONTRIBUTING.md). For the script-rule
API see [docs/SCRIPTING.md](docs/SCRIPTING.md).

## Project Overview

ClipShelf is a macOS menu-bar clipboard history manager (Swift 5.9,
SwiftUI/AppKit, macOS 13+). It captures what the user copies, applies
optional rules, stores history locally in SQLite (FTS5), and offers
app-aware paste, snippet expansion, OCR, and semantic search. Pure local
utility — no account, no cloud sync, no telemetry, no third-party
dependencies (system frameworks only).

## Commands

```bash
# Regenerate the Xcode project after adding/removing/moving source files
# (project.yml is the source of truth; CI regenerates on every run)
xcodegen generate

# Build
xcodebuild build \
  -project ClipShelf.xcodeproj \
  -scheme ClipShelf \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

# Run all tests (same invocation CI uses)
xcodebuild test \
  -project ClipShelf.xcodeproj \
  -scheme ClipShelfTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

# Run a single test class (build for testing first is implicit)
xcodebuild test \
  -project ClipShelf.xcodeproj \
  -scheme ClipShelfTests \
  -destination 'platform=macOS' \
  -only-testing:SQLiteHistoryStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Signing config lives in `Config/Signing.xcconfig` (see
`Signing.xcconfig.example`); CI builds with `CODE_SIGNING_ALLOWED=NO`.

## Golden Rule: Do Not Write Comments

**Never add comments to code in this repository.** The codebase is
deliberately comment-free: every `//`, `///`, `// MARK:`, and `/* */`
comment was removed on purpose from all Swift files and
`Localizable.strings` files, and the project intends to keep it that way.
When you touch a file, leave it as clean as you found it — do not
"helpfully" document it.

This applies to every kind of comment:

- No inline or trailing explanations (`x += 1  // bump the counter`).
- No doc comments (`/// ...`) on types, properties, or functions.
- No `// MARK:` section headers, even in new files.
- No file-header banners, copyright blocks, or `// Created by ...` lines.
- No `// TODO:` / `// FIXME:` notes — file an Issue instead.
- No commented-out code — delete it; git remembers it.
- No `/* section */` comments in `en.lproj` / `zh-Hans.lproj`
  `Localizable.strings`.

Markdown files (`README.md`, `CONTRIBUTING.md`, this file,
`docs/SCRIPTING.md`) are documentation, not code — they are exempt.

The only permitted `//` in Swift source is inside string literals: URLs
like `"https://..."`, `"file://"`, regex patterns, and the code-detection
keyword array in `PasteAdapter.swift`. Those are data, not comments — never
touch them when removing anything.

Instead of writing a comment, make the code say it:

- Rename the variable, function, or type so the intent is obvious.
- Extract a well-named helper instead of explaining a complex expression.
- Move constraints and rationale into tests — an assertion documents
  behavior better than a comment and cannot go stale.
- If something genuinely needs a persistent explanation, it belongs in
  `docs/` or a GitHub Issue, not the source file.

If a task seems impossible without comments, that is a signal the code
should be restructured, not annotated.

## Architecture

Data flow: copy → capture → rules → store → search → paste.

- `Sources/main.swift` — app entry, `AppDelegate`, floating panel lifecycle,
  global hotkeys (Carbon), the activate-then-simulate-Cmd+V paste flow.
- `Sources/ClipboardMonitor.swift` — polls `NSPasteboard.changeCount` with
  adaptive cadence; dedupes; detects screenshots; excludes password managers.
- `Sources/ClipboardIngestPipeline.swift` → `Sources/ClipboardRuleEngine.swift`
  — async rule pipeline (discard / strip URL tracking / detect sensitive /
  regex replace / trim / auto-pin / sandboxed JS scripts with timeout +
  quarantine in `ScriptRuleRunner.swift`).
- `Sources/ClipboardManager.swift` — @MainActor facade coordinating the
  in-memory hot window, cold storage, indexes, tombstones, OCR queue.
- `Sources/SQLiteHistoryStore.swift` — SQLite + FTS5 (trigram tokenizer)
  persistence, migrations, AES-GCM columns for sensitive items
  (`EncryptionService.swift`); images live on disk via
  `ClipboardImageStore.swift` / `ClipboardImageManager.swift`.
- `Sources/MenuBarView.swift` + `Sources/ClipboardItemRow.swift` — main panel
  UI; `QuickPastePanel.swift` — cursor-anchored quick paste;
  `SettingsEmbeddedView.swift` / `SettingsView.swift` / `RulesSettingsView.swift`
  — settings; `WindowLayout.swift` — shared design system + popup plumbing.
- `Sources/PasteAdapter.swift` — app-aware paste adapters keyed by bundle ID,
  dispatched through `PasteAdapterManager`; `PasteQueue.swift` — sequential /
  stack-mode paste queue.
- `Sources/FuzzySearch.swift`, `ClipboardSearchService.swift`,
  `SemanticSearchService.swift` — fuzzy, FTS, and NLEmbedding search.
- `Sources/OCRService.swift` + `ClipboardOCRQueue.swift` + `OCRTextQuality`
  — Vision OCR with confidence filtering.

Persistence is debounced via `ClipboardPersistenceCoordinator.swift` /
`PersistenceScheduler.swift`; every store is behind a protocol
(`ClipboardHistoryStore`, `ClipboardImageStore`, `AppPreferencesStore`, …)
with in-memory doubles in `Tests/Mocks/TestMocks.swift`.

## Conventions

- **Localization**: all user-facing strings go through
  `LanguageManager.shared.l("key")` with keys in
  `Sources/en.lproj/Localizable.strings` and
  `Sources/zh-Hans.lproj/Localizable.strings` (both files, no section
  comments in them). Assert messages in tests are plain strings.
- **New files**: run `xcodegen generate` after adding/removing files, or
  builds will silently miss them.
- **Concurrency**: UI-facing services are `@MainActor`; background work
  (OCR, embeddings, persistence) happens on dedicated queues/`Task.detached`.
- **Logging**: `os.Logger` with the `ClipShelf` subsystem, never `print`.
- **Versioning**: bump `MARKETING_VERSION` in `project.yml`; update
  `CHANGELOG.md` (Keep a Changelog format) under `[Unreleased]`.
- Tests: every behavioral change should come with tests using the existing
  in-memory doubles; tests never touch `NSPasteboard.general` or real user
  data (`ClipboardMonitorTests` uses a uniquely named private pasteboard).

## Delivery Workflow

Base branch is `main`. CI is the merge gate.

1. **Issue first** — every intentional change starts from (or links) a GitHub
   Issue describing the problem and acceptance criteria.
2. **Branch** from an up-to-date `main` (feature branches only; no direct
   pushes to `main` for normal work).
3. **Commit** only intended files — no secrets, IDE caches, or
   `default.profraw` / `.DS_Store` junk.
4. **Open a PR into `main`** using the template in
   `.github/PULL_REQUEST_TEMPLATE.md`; the body must include `Fixes #N` (or
   `Closes #N`) for the primary Issue. One primary Issue per PR.
5. **CI must be green before merge.** The required check is the
   `build-and-test` job in the `CI` workflow (`.github/workflows/ci.yml`):
   it runs `xcodegen generate`, then build and test with
   `CODE_SIGNING_ALLOWED=NO`. Fix and push on red; never merge red.
6. **The Issue closes on merge** via the `Fixes #N` link — never close it
   when the PR is merely opened or while CI is running.
7. Releases: pushing a `v*` tag triggers the `Release` workflow
   (`.github/workflows/release.yml`), which builds and attaches the DMG.
   Don't tag unless asked.

If you lack merge or Issue permissions: open the PR, comment on the Issue
with the PR link, leave the Issue open, and hand off to a maintainer.

User overrides (skip Issue, direct push, ignore red CI) apply only for that
turn and should be stated in the PR/Issue comment.
