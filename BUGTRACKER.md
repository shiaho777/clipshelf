# Bug Tracker — 100-bug campaign

## Fixed (10) — commit 5e7e66b
1. Import corrupts pinned invariant → trim deletes pinned (replaceHistoryForImport)
2. Script first-eval deadlock hangs capture (detached setup thread)
3. Keychain failure → ephemeral key → sensitive items unrecoverable (refuse nil)
4. SymmetricKey torn read (fast path under lock)
5. QuickPaste bypasses biometric for sensitive items (gated)
6. Snippet expansion destroys non-text clipboard (save/restore all types)
7. Paste fires Cmd+V on failed clipboard write (copyToClipboard returns Bool)
8. Duplicate UUID traps Dictionary(uniqueKeysWithValues:) (manual dedupe)
9. Shrinking copy within 3s silently dropped (captured)
10. imageFileName path traversal in export/import (isSafeImageFileName)
10b. CI flake: trim test raced async persistence (flushPendingWrites) — 190f313

## Verified findings from 3-agent audit (45) — TO FIX

### Infra (agent_7220)
- [ ] I1 P0 startup orphan-prune deletes fresh images (ClipboardManager.swift:328)
- [ ] I2 P0 snapshot vs incremental resurrection race (SQLiteHistoryStore saveItemsLocked)
- [ ] I3 P1 deletes skipped for IDs missing from lastKnownItems (SQLiteHistoryStore:628)
- [ ] I4 P1 in-app pasteboard writes not acknowledged → self-recapture (many files)
- [ ] I5 P1 writeObjects failure reports didWrite:true (ClipboardPasteboardWriter:69)
- [ ] I6 P1 snippet suppress single Bool for two writes (SnippetExpansionMonitor)
- [ ] I7 P1 stale usage snapshot regresses use counts (ClipboardPersistenceCoordinator:86)
- [ ] I8 P1 unbounded embeddingCache growth (ClipboardManager:73)
- [ ] I9 P1 double Cmd+V in pasteAndClose (main.swift:328)
- [ ] I10 P1 image provider invalidated by interleaved writers (ClipboardImageManager:19)
- [ ] I11 P2 tombstone overflow drops protection (ClipboardManager:174)
- [ ] I12 P2 hotkey recorder can't rebind active combo (HotKeyManager:274)
- [ ] I13 P2 launchctl print sync on main at launch (LaunchAtLoginService:62)
- [ ] I14 P2 FuzzySearch limit boundary equal-score inconsistency
- [ ] I15 P2 unbounded regexCache + main-thread flush freeze on import

### Services (agent_2bdf)
- [ ] S1 P0 tombstone overflow replacement re-admits deleted IDs (dup of I11)
- [ ] S2 P0 AppIntents leak sensitive content (no isSensitive gating)
- [ ] S3 P1 mergeFetchedSyncItems no dedupe/no recomputePinnedCount
- [ ] S4 P1 stale pinnedCount → index wrong lane → OCR writes wrong row
- [ ] S5 P1 OCR isProcessing wedged forever on stalled Vision call
- [ ] S6 P1 Spotlight pending batch re-indexes stale items after clearAll
- [ ] S7 P1 usage snapshot scheduled during executing flush resurrects state (dup I7)
- [ ] S8 P1 FTS implicit-AND violated; fallback skipped
- [ ] S9 P2 readRow never restores isScreenshot
- [ ] S10 P2 store deinit closes db without lock (use-after-free)
- [ ] S11 P2 user copy swallowed between two snippet writes (related I6)
- [ ] S12 P2 highlight indices computed on ocrText vs rendered preview
- [ ] S13 P2 JSON store loadItems(limit:) semantics diverge (oldest kept)
- [ ] S14 P2 image stackMode re-check races toggle off
- [ ] S15 P2 semantic embedding computed on main thread

### UI (agent_c171)
- [ ] U1 P0 UTType(filenameExtension:)! force-unwrap crash (clipbackup/cliprules)
- [ ] U2 P1 "Test Rules" lands on General tab (embedded view ignores _settingsRequestedTab)
- [ ] U3 P1 launch-at-login toggle inverted on first interaction (VM load never called)
- [ ] U4 P1 stale rows after in-place content edit (cheap diff misses same-ID mutation)
- [ ] U5 P1 Preview copy mangles fileURL (JSON text) / richText (drops RTF)
- [ ] U6 P1 search count fabricated lower bound ("%d found" wrong)
- [ ] U7 P1 smart-paste badge wipes queue status (P1 status desync)
- [ ] U8 P1 cancelled drag permanently disables outside-click dismiss
- [ ] U9 P1 QuickPaste double-show leaks panel+monitor
- [ ] U10 P1 keyboard nav dead until list clicked (first responder)
- [ ] U11 P2 compare diff order ignores selection order
- [ ] U12 P2 rules toggle/reorder doesn't republish (visual desync)
- [ ] U13 P2 stale isCode across row reuse / no cancellation check
- [ ] U14 P2 onboarding reappears after Clear All (never marked complete)
- [ ] U15 P2 TimeAgoText formatter churn every 15s per row

## Count: 10 fixed + 44 unique pending (S1=I11, S7=I7 dup) = 54
## Need 46 more findings → more audit rounds after fixing these
