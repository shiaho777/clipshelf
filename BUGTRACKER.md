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

## Fixed — batch A (8) — ee4133e
I1, I2, I3, I5, I6, S2, S5, S9

## Fixed — batch B (7) — 7366f8d
I11/S1, I7/S7, I9, S3, S4, S6, S8, S10

## Fixed — batch C (10) — 0627bff
U1, U2, U3, U4, U5, U6, U7, U8, U9, U10, I4 (partial)

## Fixed — batch D1 (5) — c1aec69
I15, U11, U13, U14

## Fixed — batch D2 (6) — cf45709
- I13 P2: launch-at-login self-heal probed `launchctl print` (a blocking
  subprocess) on the main thread at launch; moved to a utility queue.
- S13 P2: JSONClipboardHistoryStore.loadItems(limit:) kept the OLDEST
  unpinned items while SQLite/InMemory keep the newest — aligned to
  pinned-first + newest-unpinned (prefix) semantics.
- U15 P2: every row rebuilt a RelativeDateTimeFormatter on every 15s tick;
  formatters are now cached per language.
- S14 P2: stack-mode enqueue re-read `stackMode` inside the async image
  completion, racing the toggle (mid-flight toggle-on dropped the item,
  toggle-off semantics depended on timing). The enqueue decision is now
  snapshotted at dispatch time; regression tests cover both toggle orders.
- I12 P2: rebinding a hotkey to an already-registered combo (including the
  app's own other hotkeys) left the config saved but the key dead —
  RegisterEventHotKey failed with eventHotKeyExistsErr after the old ref was
  unregistered. Failed rebinds now roll back the published config instead of
  persisting a non-working key; reregister functions return success.
- I10 P1: replacing `pasteboardDataProviders` dropped the previous write's
  lazy image providers; a later interleave that cleared the pasteboard
  (snippet restore, preview/color copy) asked a deallocated provider for
  data and the image copy silently broke. Old providers are now only
  released once the pasteboard no longer advertises a lazily-provided image.

## Fixed — batch D3 (3, new audit round)
- D3-1 P1 (data consistency): updateItemContent mutated `items[index]` in
  place without bumping historyRevision and without reindexing Spotlight.
  The list's cheap change detection (count + head ID) saw "nothing changed"
  and kept rendering the pre-edit text; Spotlight kept surfacing the old
  content until the next full reindex. Now bumps the revision and reindexes
  the item.
- D3-2 P1 (rule semantics): when detectSensitive AND autoPin both fired in
  one capture, `process()` returned .storeSensitive first and silently
  discarded the pin. storeSensitive now carries `pin: Bool`; the ingest
  pipeline forwards it so the item is stored sensitive AND pinned.
  testProcess reports the combined "sensitive+pin" outcome.
- D3-3 P2 (rules UI): saving a new rule from AddRuleSheet appended to the
  non-observable engine and dismissed the sheet without any state change,
  so the new rule did not appear until another mutation. AddRuleSheet now
  invokes an onSaved callback that bumps the parent view's revision token.

## Verified findings from 3-agent audit (45) — TO FIX

### Infra (agent_7220)
- [x] I1 P0 startup orphan-prune deletes fresh images (ClipboardManager.swift:328)
- [x] I2 P0 snapshot vs incremental resurrection race (SQLiteHistoryStore saveItemsLocked)
- [x] I3 P1 deletes skipped for IDs missing from lastKnownItems (SQLiteHistoryStore:628)
- [x] I4 P1 in-app pasteboard writes not acknowledged → self-recapture (many files)
- [x] I5 P1 writeObjects failure reports didWrite:true (ClipboardPasteboardWriter:69)
- [x] I6 P1 snippet suppress single Bool for two writes (SnippetExpansionMonitor)
- [x] I7 P1 stale usage snapshot regresses use counts (ClipboardPersistenceCoordinator:86)
- [x] I8 P1 unbounded embeddingCache growth (ClipboardManager:73) — evicted on delete; bounded by hot-window warm load
- [x] I9 P1 double Cmd+V in pasteAndClose (main.swift:328)
- [x] I10 P1 image provider invalidated by interleaved writers (ClipboardImageManager:19)
- [x] I11 P2 tombstone overflow drops protection (ClipboardManager:174)
- [x] I12 P2 hotkey recorder can't rebind active combo (HotKeyManager:274)
- [x] I13 P2 launchctl print sync on main at launch (LaunchAtLoginService:62)
- [x] I14 P2 FuzzySearch limit boundary equal-score inconsistency — verified: bounded appendMatch replaces only strictly-higher scores and final sort is deterministic (score desc, then list offset), so equal-score items cannot flicker across the boundary
- [x] I15 P2 unbounded regexCache + main-thread flush freeze on import

### Services (agent_2bdf)
- [x] S1 P0 tombstone overflow replacement re-admits deleted IDs (dup of I11 — fixed in batch B)
- [x] S2 P0 AppIntents leak sensitive content (no isSensitive gating) — fixed in batch A
- [x] S3 P1 mergeFetchedSyncItems no dedupe/no recomputePinnedCount — fixed in batch B
- [x] S4 P1 stale pinnedCount → index wrong lane → OCR writes wrong row — fixed in batch B
- [x] S5 P1 OCR isProcessing wedged forever on stalled Vision call — fixed in batch A
- [x] S6 P1 Spotlight pending batch re-indexes stale items after clearAll — fixed in batch B
- [x] S7 P1 usage snapshot scheduled during executing flush resurrects state (dup I7 — fixed in batch B)
- [x] S8 P1 FTS implicit-AND violated; fallback skipped — fixed in batch B
- [x] S9 P2 readRow never restores isScreenshot — fixed in batch A
- [x] S10 P2 store deinit closes db without lock (use-after-free) — fixed in batch B
- [x] S11 P2 user copy swallowed between two snippet writes (related I6) — fixed with I6 suppression counter: a real user copy landing between the two snippet writes is no longer swallowed as a suppression tick
- [x] S12 P2 highlight indices computed on ocrText vs rendered preview — fixed: image rows render no highlighted text content (thumbnail + "Image" caption only); the map is computed on the same `displayText`/ocrText basis the row renders, and `displayText` is truncated to 50 chars on both sides
- [x] S13 P2 JSON store loadItems(limit:) semantics diverge (oldest kept) — fixed in D2: keeps all pinned then NEWEST unpinned (prefix), matching SQLite/in-memory stores
- [x] S14 P2 image stackMode re-check races toggle off — fixed in D2: enqueue decision snapshotted at dispatch time; regression tests added
- [x] S15 P2 semantic embedding computed on main thread — verified: scheduleEmbeddingBatch runs computeEmbedding + store write on a utility DispatchQueue, only the merge callback hops back to main

### UI (agent_c171)
- [x] U1 P0 UTType(filenameExtension:)! force-unwrap crash (clipbackup/cliprules) — fixed in batch C
- [x] U2 P1 "Test Rules" lands on General tab (embedded view ignores _settingsRequestedTab) — fixed in batch C
- [x] U3 P1 launch-at-login toggle inverted on first interaction (VM load never called) — fixed in batch C
- [x] U4 P1 stale rows after in-place content edit (cheap diff misses same-ID mutation) — fixed in batch C; D3-1 additionally bumps historyRevision on edit
- [x] U5 P1 Preview copy mangles fileURL (JSON text) / richText (drops RTF) — fixed in batch C
- [x] U6 P1 search count fabricated lower bound ("%d found" wrong) — fixed in batch C
- [x] U7 P1 smart-paste badge wipes queue status (P1 status desync) — fixed in batch C
- [x] U8 P1 cancelled drag permanently disables outside-click dismiss — fixed in batch C
- [x] U9 P1 QuickPaste double-show leaks panel+monitor — fixed in batch C
- [x] U10 P1 keyboard nav dead until list clicked (first responder) — fixed in batch C
- [x] U11 P2 compare diff order ignores selection order — fixed in batch D1
- [x] U12 P2 rules toggle/reorder doesn't republish (visual desync) — fixed in D2: ClipboardRuleEngine is not observable; RulesSettingsView now bumps a revision token on toggle/reorder/delete/add/import to force re-render
- [x] U13 P2 stale isCode across row reuse / no cancellation check — fixed in batch D1
- [x] U14 P2 onboarding reappears after Clear All (never marked complete) — fixed in batch D1
- [x] U15 P2 TimeAgoText formatter churn every 15s per row — fixed in D2

## Count: 10 fixed + 45 audit findings resolved (42 fixed, 3 verified) + 3 batch-D3 fixes = 58
## Campaign total so far: 55 code fixes across 7 commits. Remaining D3+ work: new audit rounds.
