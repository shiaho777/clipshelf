import SwiftUI
import AppKit

enum FilterType: Equatable, Hashable {
    case all, text, image
    case app(bundleID: String, name: String)

    static var staticCases: [FilterType] { [.all, .text, .image] }

    var key: String {
        switch self {
        case .all: return "filter.all"
        case .text: return "filter.text"
        case .image: return "filter.image"
        case .app(_, let name): return name
        }
    }

    var isAppFilter: Bool {
        if case .app = self { return true }
        return false
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text || item.type == .richText || item.type == .fileURL
        case .image: return item.type == .image
        case .app(let bundleID, _): return item.sourceBundleID == bundleID
        }
    }
}

private struct DiffPair: Identifiable {
    let id = UUID()
    let itemA: ClipboardItem
    let itemB: ClipboardItem
}

struct ClipboardListPage {
    let items: [ClipboardItem]
    let hasMore: Bool
}

enum ClipboardListPaginator {
    static func page(
        from items: [ClipboardItem],
        visibleCount: Int,
        where predicate: (ClipboardItem) -> Bool
    ) -> ClipboardListPage {
        guard visibleCount > 0 else {
            return ClipboardListPage(items: [], hasMore: items.contains(where: predicate))
        }
        var page: [ClipboardItem] = []
        page.reserveCapacity(visibleCount)
        for item in items where predicate(item) {
            if page.count == visibleCount {
                return ClipboardListPage(items: page, hasMore: true)
            }
            page.append(item)
        }
        return ClipboardListPage(items: page, hasMore: false)
    }
}

struct MenuBarView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject var lang = LanguageManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var hoveredItemId: UUID?
    @State private var focusedIndex: Int?
    @State private var filterType: FilterType = .all
    @State private var previewItem: ClipboardItem?
    @State private var showClearConfirm = false
    @State private var showStackModeClearConfirm = false
    @State private var showSnippets = false
    @State private var editingItem: ClipboardItem?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var filteredItems: [ClipboardItem] = []
    @State private var isMultiSelectMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var showAppFilters = false
    @State private var filterByCurrentApp = false
    @State private var highlightMap: [UUID: Set<Int>] = [:]
    @State private var searchDebounceTask: DispatchWorkItem?
    @State private var itemsUpdateDebounceTask: DispatchWorkItem?
    @State private var searchGeneration: UInt = 0
    @State private var lastSeenItemCount: Int = 0
    @State private var lastSeenFirstItemID: UUID?
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var diffPair: DiffPair?
    /// IDs of sensitive items the user has unlocked in the current panel session.
    /// Cleared when the panel is shown so unlock state doesn't persist across opens.
    @State private var unlockedItemIDs: Set<UUID> = []
    /// Cached so the computed value isn't rebuilt on every view re-render (hover, animation, etc.).
    @State private var cachedAppFilters: [FilterType] = []
    /// Total number of items that match the current search + filter, including those not yet shown.
    @State private var totalMatchCount: Int = 0
    @State private var hasMoreFilteredItems = false
    /// How many matching items are currently loaded into `filteredItems`.
    @State private var visibleCount: Int = Self.renderPageSize
    @FocusState private var isSearchFocused: Bool
    @Namespace private var filterAnimation
    var onOpenSettings: () -> Void = {}
    /// Callback to open Settings directly on the Rules \u2192 Test section.
    var onOpenRulesTest: () -> Void = {}
    @ObservedObject private var pasteQueue = PasteQueue.shared
    @EnvironmentObject private var frontmostApp: FrontmostAppInfo

    private func buildAppFilters(from items: [ClipboardItem]) -> [FilterType] {
        var seen = Set<String>()
        var filters: [FilterType] = []
        for item in items {
            guard let bid = item.sourceBundleID, let name = item.sourceAppName, !seen.contains(bid) else { continue }
            seen.insert(bid)
            filters.append(.app(bundleID: bid, name: name))
            if filters.count >= 5 { break }
        }
        return filters
    }

    /// Maximum items shown in one page; tapping "load more" adds another page.
    private static let renderPageSize = 200

    private func updateFilteredItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var page: [ClipboardItem] = []
        page.reserveCapacity(visibleCount)

        if query.isEmpty {
            if filterType == .all {
                totalMatchCount = clipboardManager.items.count
                filteredItems = Array(clipboardManager.items.prefix(visibleCount))
                hasMoreFilteredItems = clipboardManager.items.count > filteredItems.count
                highlightMap = [:]
                return
            }
            let result = ClipboardListPaginator.page(from: clipboardManager.items, visibleCount: visibleCount) { item in
                filterType.matches(item)
            }
            filteredItems = result.items
            hasMoreFilteredItems = result.hasMore
            totalMatchCount = hasMoreFilteredItems ? filteredItems.count + 1 : filteredItems.count
            highlightMap = [:]
            return
        }

        let searched = clipboardManager.search(query, limit: visibleCount + 1) { item in
            filterType.matches(item)
        }
        hasMoreFilteredItems = searched.count > visibleCount
        page.append(contentsOf: searched.prefix(visibleCount))
        totalMatchCount = hasMoreFilteredItems ? page.count + 1 : page.count
        filteredItems = page
        var map: [UUID: Set<Int>] = [:]
        for item in filteredItems {
            let displayText = item.type == .image ? (item.ocrText ?? "") : item.displayText
            if let indices = FuzzySearch.matchedIndices(query: query, in: displayText) {
                map[item.id] = indices
            }
        }
        highlightMap = map
    }

    private func loadMoreItems() {
        visibleCount += Self.renderPageSize
        updateFilteredItems()
    }
    
    private func selectItem(at index: Int, asPlainText: Bool = false) {
        guard index > 0 && index <= min(9, filteredItems.count) else { return }
        pasteItem(filteredItems[index - 1], asPlainText: asPlainText)
    }
    
    private func moveFocus(_ direction: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        hoveredItemId = nil
        let newIndex: Int
        if let current = focusedIndex {
            newIndex = max(0, min(count - 1, current + direction))
        } else {
            newIndex = direction > 0 ? 0 : count - 1
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
            focusedIndex = newIndex
        }
        if newIndex < filteredItems.count {
            scrollProxy?.scrollTo(filteredItems[newIndex].id, anchor: .center)
        }
    }
    
    private func confirmFocused(asPlainText: Bool = false) {
        guard let idx = focusedIndex, idx >= 0, idx < filteredItems.count else { return }
        pasteItem(filteredItems[idx], asPlainText: asPlainText)
    }

    /// Gate paste through BiometricAuth for sensitive items; pass through immediately for non-sensitive.
    private func pasteItem(_ item: ClipboardItem, asPlainText: Bool = false) {
        if item.isSensitive {
            Task { @MainActor in
                do {
                    try await BiometricAuthService.shared.authenticate(
                        reason: LanguageManager.shared.l("biometric.unlockSensitive")
                    )
                    clipboardManager.copyToClipboard(item, autoPaste: true, asPlainText: asPlainText)
                } catch {
                    // Auth failed or was cancelled — do nothing
                }
            }
        } else {
            clipboardManager.copyToClipboard(item, autoPaste: true, asPlainText: asPlainText)
        }
    }
    
    private func cycleFilter() {
        let all = FilterType.staticCases
        guard let i = all.firstIndex(of: filterType) else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) { filterType = .all }
            focusedIndex = nil
            return
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
            filterType = all[(i + 1) % all.count]
        }
        focusedIndex = nil
    }

    private func toggleMultiSelect() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
            isMultiSelectMode.toggle()
            if !isMultiSelectMode { selectedItemIDs.removeAll() }
        }
    }

    private func mergeAndPasteSelected() {
        let selectedItems = filteredItems.filter { selectedItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }
        let merged = selectedItems.map { item -> String in
            if item.type == .image { return item.ocrText ?? "[Image]" }
            return item.content
        }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(merged, forType: .string)
        clipboardManager.addTextItem(content: merged)
        isMultiSelectMode = false
        selectedItemIDs.removeAll()
        clipboardManager.onItemSelected?()
    }
    
    private func queueSelectedForPaste() {
        let selectedItems = filteredItems.filter { selectedItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }
        PasteQueue.shared.enqueue(selectedItems)
        isMultiSelectMode = false
        selectedItemIDs.removeAll()
        clipboardManager.onItemSelected?()
    }

    private func handleTransform(_ result: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result, forType: .string)
        clipboardManager.addTextItem(content: result)
    }

    @ViewBuilder
    private func historyRow(index: Int, item: ClipboardItem) -> some View {
        let rowIndex: Int? = isMultiSelectMode ? nil : (index < 9 ? index + 1 : nil)
        let imageURL = clipboardManager.imageFileURL(for: item)
        let isFocused = focusedIndex == index
        let isUnlocked = unlockedItemIDs.contains(item.id)
        let isSelected = selectedItemIDs.contains(item.id)
        let highlights = highlightMap[item.id]
        let selectAction: (() -> Void)? = isMultiSelectMode ? {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
                if selectedItemIDs.contains(item.id) {
                    selectedItemIDs.remove(item.id)
                } else {
                    selectedItemIDs.insert(item.id)
                }
            }
        } : nil

        ClipboardItemRow(
            item: item,
            imageURL: imageURL,
            index: rowIndex,
            isFocused: isFocused,
            onCopy: { asPlainText in
                clipboardManager.copyToClipboard(item, autoPaste: true, asPlainText: asPlainText)
            },
            onPin: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) {
                    clipboardManager.togglePin(item)
                }
            },
            onDelete: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                    clipboardManager.deleteItem(item)
                }
            },
            onPreview: { previewItem = item },
            onEdit: { if item.type != .image { editingItem = item } },
            onTransform: { handleTransform($0) },
            isSelected: isSelected,
            onSelect: selectAction,
            highlightIndices: highlights,
            isUnlocked: isUnlocked,
            onUnlock: { unlockedItemIDs.insert(item.id) },
            onHoverChange: { hovering in
                if hovering {
                    hoveredItemId = item.id
                    focusedIndex = nil
                } else if hoveredItemId == item.id {
                    hoveredItemId = nil
                }
            },
            onReorder: { sourceID, placeBefore in
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    if placeBefore {
                        clipboardManager.moveItem(id: sourceID, before: item.id)
                    } else {
                        clipboardManager.moveItem(id: sourceID, after: item.id)
                    }
                }
            },
            filePaths: item.filePaths
        )
        .id(item.id)
    }

    @ViewBuilder
    private func historyList() -> some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                historyRow(index: index, item: item)
            }
            if hasMoreFilteredItems {
                Button(action: loadMoreItems) {
                    Text(lang.l("list.loadMorePage"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func filterButton(_ type: FilterType) -> some View {
        let label = type.isAppFilter ? type.key : lang.l(type.key)
        Text(label)
            .font(.system(size: 12, weight: filterType == type ? .semibold : .regular))
            .foregroundColor(filterType == type ? .primary : .secondary.opacity(0.65))
            .frame(maxWidth: type.isAppFilter ? nil : .infinity)
            .padding(.horizontal, type.isAppFilter ? 10 : 0)
            .padding(.vertical, 6)
            .background {
                if filterType == type {
                    Capsule()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                        .shadow(color: .black.opacity(0.03), radius: 0.5)
                        .matchedGeometryEffect(id: "activeFilter", in: filterAnimation)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78)) {
                    filterType = type
                }
            }
    }
    
    var body: some View {
        Group {
            if !lang.hasSelectedLanguage {
                LanguagePickerView()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                SearchField(
                    text: $searchText,
                    placeholder: lang.l("search.placeholder"),
                    size: .regular,
                    reduceMotion: reduceMotion,
                    focus: $isSearchFocused
                )
                LanguageSwitcherButton()
            }
            .padding(.trailing, 14)

            HStack(spacing: 4) {
                ForEach(FilterType.staticCases, id: \.self) { type in
                    filterButton(type)
                }
                if let bid = frontmostApp.bundleID, let name = frontmostApp.appName {
                    Divider().frame(height: 16).opacity(0.3)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                            filterByCurrentApp.toggle()
                            if filterByCurrentApp { filterType = .app(bundleID: bid, name: name) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: filterByCurrentApp ? "app.badge.fill" : "app.badge")
                                .font(.system(size: 10, weight: .medium))
                            Text(name)
                                .font(.system(size: 11, weight: filterByCurrentApp ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundColor(filterByCurrentApp ? .primary : .secondary.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if filterByCurrentApp {
                                Capsule()
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(lang.l("filter.currentApp"))
                }
                if !cachedAppFilters.isEmpty {
                    Divider().frame(height: 16).opacity(0.3)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) { showAppFilters.toggle() }
                    } label: {
                        Image(systemName: "app.badge")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(filterType.isAppFilter ? .primary : .secondary.opacity(0.65))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 14)
            .padding(.bottom, showAppFilters ? 4 : 10)

            if showAppFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                    ForEach(cachedAppFilters, id: \.self) { type in
                            filterButton(type)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider().opacity(0.3)

            // MARK: Paste Queue panel
            // Shown inline above the history list when the queue is active
            // OR when stack mode is enabled (even with empty queue).
            if pasteQueue.isActive || pasteQueue.stackMode {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: pasteQueue.stackMode ? "square.stack.3d.up.fill" : "doc.on.clipboard.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Text(lang.l("queue.title"))
                            .font(.system(size: 11, weight: .semibold))
                        if pasteQueue.stackMode {
                            TagBadge(lang.l("queue.stackMode"), color: .accentColor, fontSize: 9)
                        }
                        if pasteQueue.remaining > 0 {
                            Text(lang.l("queue.remaining", pasteQueue.remaining))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Toggle stack mode
                        Button {
                            if pasteQueue.stackMode && pasteQueue.remaining > 0 {
                                // Ask before clearing remaining items.
                                showStackModeClearConfirm = true
                            } else {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                    pasteQueue.stackMode.toggle()
                                }
                            }
                        } label: {
                            Image(systemName: pasteQueue.stackMode ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(pasteQueue.stackMode ? .accentColor : .secondary.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help(lang.l("queue.stackMode.help"))
                        if pasteQueue.remaining > 0 {
                            Button(lang.l("queue.clear")) { pasteQueue.clear() }
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.7))
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                    ForEach(Array(pasteQueue.pendingItemsPrefix(3).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.quaternary)
                                .frame(width: 14)
                            Text(item.type == .image ? lang.l("item.image") : item.content)
                                .lineLimit(1)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                    pasteQueue.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                    }
                    if pasteQueue.remaining > 3 {
                        Text("+ \(pasteQueue.remaining - 3) \(lang.l("list.loadMore", pasteQueue.remaining - 3))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                    }
                }
                .background(Color.accentColor.opacity(0.04))
                .overlay(alignment: .bottom) { Divider().opacity(0.3) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollViewReader { proxy in
            ScrollView {
        if filteredItems.isEmpty && showOnboarding {
                    OnboardingView {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78)) {
                            showOnboarding = false
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: searchText.isEmpty ? "clipboard" : "magnifyingglass",
                        message: searchText.isEmpty ? lang.l("empty.message") : lang.l("search.noResults"),
                        actionTitle: searchText.isEmpty ? nil : lang.l("search.clearSearch"),
                        action: searchText.isEmpty ? nil : {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                                searchText = ""
                            }
                        }
                    )
                    .padding(.vertical, 60)
                } else {
                    historyList()
                }
            }
            .onAppear { scrollProxy = proxy }
            }
            .frame(minHeight: 100, maxHeight: 350)
            .background(KeyboardShortcutHandler(
                onNumberPressed: { selectItem(at: $0) },
                onArrowPressed: { moveFocus($0) },
                onEnterPressed: { confirmFocused(asPlainText: $0) },
                onEscPressed: {
                    if !searchText.isEmpty {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { searchText = "" }
                    } else {
                        NSApp.keyWindow?.close()
                    }
                },
                onTabPressed: { cycleFilter() },
                onSpacePressed: {
                    if let idx = focusedIndex, idx < filteredItems.count {
                        previewItem = filteredItems[idx]
                    } else if let hovered = hoveredItemId, let item = filteredItems.first(where: { $0.id == hovered }) {
                        previewItem = item
                    }
                },
                onEditPressed: {
                    if let idx = focusedIndex, idx < filteredItems.count {
                        let item = filteredItems[idx]
                        if item.type != .image { editingItem = item }
                    }
                }
            ))
            
            Divider().opacity(0.3)
            
            HStack {
                if isMultiSelectMode {
                    Text(lang.l("multiselect.count", selectedItemIDs.count))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Spacer()
                    HStack(spacing: 6) {
                        if selectedItemIDs.count == 2 {
                            Button(lang.l("multiselect.compare")) {
                                let selected = filteredItems.filter { selectedItemIDs.contains($0.id) }
                                if selected.count == 2 {
                                    diffPair = DiffPair(itemA: selected[0], itemB: selected[1])
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        Button(lang.l("multiselect.merge")) { mergeAndPasteSelected() }
                            .font(.system(size: 11, weight: .medium))
                            .disabled(selectedItemIDs.isEmpty)
                        Button(lang.l("multiselect.queue")) { queueSelectedForPaste() }
                            .font(.system(size: 11, weight: .medium))
                            .disabled(selectedItemIDs.isEmpty)
                        Button(lang.l("button.cancel")) { toggleMultiSelect() }
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                } else {
                    // Show match count when searching, total count otherwise.
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if query.isEmpty {
                        Text(lang.l("items.count", clipboardManager.items.count))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    } else {
                        Text(lang.l("search.results", totalMatchCount))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        BottomBarButton(icon: pasteQueue.stackMode ? "square.stack.3d.up.fill" : "square.stack.3d.up", tint: pasteQueue.stackMode ? .accentColor : .secondary.opacity(0.7)) {
                            if pasteQueue.stackMode && pasteQueue.remaining > 0 {
                                showStackModeClearConfirm = true
                            } else {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                    pasteQueue.stackMode.toggle()
                                }
                            }
                        }
                        .help(lang.l("queue.stackMode.help"))
                        .accessibilityLabel(lang.l("queue.stackMode"))
                        BottomBarButton(icon: "text.quote", tint: .accentColor) { showSnippets = true }
                            .help(lang.l("snippets.title"))
                            .accessibilityLabel(lang.l("snippets.title"))
                        BottomBarButton(icon: "checklist", tint: .accentColor) { toggleMultiSelect() }
                            .help(lang.l("multiselect.title"))
                            .accessibilityLabel(lang.l("multiselect.title"))
                        // Settings button with context menu for destructive / secondary actions.
                        BottomBarButton(icon: "gearshape", action: onOpenSettings)
                            .help(lang.l("settings.title"))
                            .accessibilityLabel(lang.l("settings.title"))
                            .contextMenu {
                                Button { onOpenRulesTest() } label: {
                                    Label(lang.l("queue.testRules"), systemImage: "wand.and.rays")
                                }
                                Divider()
                                Button(role: .destructive) { showClearConfirm = true } label: {
                                    Label(lang.l("button.clear"), systemImage: "trash")
                                }
                                Divider()
                                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
                                    Label(lang.l("button.quit"), systemImage: "power")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .onAppear {
            searchText = ""
            focusedIndex = nil
            filterType = .all
            filterByCurrentApp = false
            showAppFilters = false
            unlockedItemIDs = []  // Reset unlock state on every panel open
            cachedAppFilters = buildAppFilters(from: clipboardManager.items)
            updateFilteredItems()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: showAppFilters) { _ in /* no-op, just triggers re-layout */ }
        .onChange(of: searchText) { _ in
            searchDebounceTask?.cancel()
            searchGeneration &+= 1
            let generation = searchGeneration
            visibleCount = Self.renderPageSize
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                updateFilteredItems()
                focusedIndex = nil
                return
            }
            let task = DispatchWorkItem {
                guard generation == searchGeneration else { return }
                updateFilteredItems()
                focusedIndex = filteredItems.isEmpty ? nil : 0
            }
            searchDebounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
        }
        .onChange(of: filterType) { newFilter in
            focusedIndex = nil
            visibleCount = Self.renderPageSize
            // If user switched to a non-current-app filter, reset the toggle
            if filterByCurrentApp {
                if case .app(let bid, _) = newFilter, bid == frontmostApp.bundleID {
                    // still filtering by current app — keep toggle on
                } else {
                    filterByCurrentApp = false
                }
            }
            updateFilteredItems()
        }
        .onReceive(clipboardManager.$historyRevision) { _ in
            itemsUpdateDebounceTask?.cancel()
            let task = DispatchWorkItem {
                let items = clipboardManager.items
                let needsFilterRebuild: Bool
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    needsFilterRebuild = items.count != lastSeenItemCount
                        || items.first?.id != lastSeenFirstItemID
                } else {
                    needsFilterRebuild = true
                }
                if needsFilterRebuild {
                    cachedAppFilters = buildAppFilters(from: items)
                    updateFilteredItems()
                }
                lastSeenItemCount = items.count
                lastSeenFirstItemID = items.first?.id
                if let hovered = hoveredItemId, clipboardManager.item(byID: hovered) == nil {
                    hoveredItemId = nil
                }
                if let fi = focusedIndex, fi >= filteredItems.count {
                    focusedIndex = filteredItems.isEmpty ? nil : filteredItems.count - 1
                }
            }
            itemsUpdateDebounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
        }
        .popupWindow(item: $previewItem) { item in
            PreviewSheet(item: item, image: clipboardManager.resolvedImage(for: item)) { itemToPaste in
                pasteItem(itemToPaste)
            }
        }
        .popupWindow(item: $editingItem) { item in
            EditSheet(item: item, clipboardManager: clipboardManager) {
                clipboardManager.onItemSelected?()
            }
        }
        .popupWindow(isPresented: $showSnippets) {
            SnippetsView(snippetManager: snippetManager) { _ in
                clipboardManager.onItemSelected?()
            }
        }
        .alert(lang.l("settings.clearAllConfirm"), isPresented: $showClearConfirm) {
            Button(lang.l("button.cancel"), role: .cancel) {}
            Button(lang.l("button.clear"), role: .destructive) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) { clipboardManager.clearAll() }
            }
        }
        .alert(lang.l("queue.stackModeClearConfirm"), isPresented: $showStackModeClearConfirm) {
            Button(lang.l("button.cancel"), role: .cancel) {}
            Button(lang.l("queue.clearAndExit"), role: .destructive) {
                pasteQueue.clear()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    pasteQueue.stackMode = false
                }
            }
        }
        .popupWindow(item: $diffPair) { pair in
            DiffViewerSheet(itemA: pair.itemA, itemB: pair.itemB)
        }
    }
}

