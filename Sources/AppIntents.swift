import AppIntents
import AppKit

// MARK: - Search Clipboard History

@available(macOS 13.0, *)
struct SearchClipboardHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Clipboard History"
    static var description = IntentDescription("Search your clipboard history by keyword")

    @Parameter(title: "Query")
    var query: String

    @Parameter(title: "Limit", default: 5)
    var limit: Int

    /// Optional type filter: \"text\", \"image\", or \"richText\"
    @Parameter(title: "Type Filter (text / image / richText)", default: "")
    var typeFilter: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let delegate = NSApp.delegate as? AppDelegate else { return .result(value: []) }
        var results = delegate.clipboardManager.search(query)
        if !typeFilter.isEmpty, let type = ClipboardItem.ItemType(rawValue: typeFilter) {
            results = results.filter { $0.type == type }
        }
        return .result(value: Array(results.prefix(limit).map(\.content)))
    }
}

// MARK: - Get Recent Items

@available(macOS 13.0, *)
struct GetRecentItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recent Clipboard Items"
    static var description = IntentDescription("Retrieve the most recent items from your clipboard history")
    
    @Parameter(title: "Count", default: 5)
    var count: Int
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(value: [])
        }
        return .result(value: delegate.clipboardManager.recentItemContents(limit: count))
    }
}

// MARK: - Pin Item by ID

@available(macOS 13.0, *)
struct PinClipboardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Pin on Clipboard Item"
    static var description = IntentDescription("Pin or unpin a clipboard item identified by its UUID string")

    @Parameter(title: "Item ID (UUID string)")
    var itemID: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let uuid = UUID(uuidString: itemID) else { return .result(value: false) }
        delegate.clipboardManager.pinItem(byID: uuid)
        return .result(value: true)
    }
}

// MARK: - Delete Item by ID

@available(macOS 13.0, *)
struct DeleteClipboardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Clipboard Item"
    static var description = IntentDescription("Permanently delete a clipboard item by its UUID string")

    @Parameter(title: "Item ID (UUID string)")
    var itemID: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let uuid = UUID(uuidString: itemID) else { return .result(value: false) }
        delegate.clipboardManager.deleteItem(byID: uuid)
        return .result(value: true)
    }
}

// MARK: - Paste Item by Index

@available(macOS 13.0, *)
struct PasteItemByIndexIntent: AppIntent {
    static var title: LocalizedStringResource = "Paste Clipboard Item by Index"
    static var description = IntentDescription("Copy the Nth item (1-indexed) to the clipboard and optionally trigger paste")

    @Parameter(title: "Index", default: 1)
    var index: Int

    @Parameter(title: "As Plain Text", default: false)
    var asPlainText: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let delegate = NSApp.delegate as? AppDelegate else { return .result(value: "") }
        let idx = index - 1
        guard let item = delegate.clipboardManager.item(at: idx) else { return .result(value: "") }
        delegate.clipboardManager.copyToClipboard(item, autoPaste: true, asPlainText: asPlainText)
        return .result(value: item.content)
    }
}

// MARK: - Get Items by Source App

@available(macOS 13.0, *)
struct GetItemsByAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Clipboard Items by App"
    static var description = IntentDescription("Retrieve clipboard items copied from a specific app bundle ID")

    @Parameter(title: "Bundle ID (e.g. com.apple.Safari)")
    var bundleID: String

    @Parameter(title: "Limit", default: 10)
    var limit: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let delegate = NSApp.delegate as? AppDelegate else { return .result(value: []) }
        return .result(value: delegate.clipboardManager.itemContents(sourceBundleID: bundleID, limit: limit))
    }
}

// MARK: - Clear Sensitive Items

@available(macOS 13.0, *)
struct ClearSensitiveItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Sensitive Clipboard Items"
    static var description = IntentDescription("Remove all sensitive items from clipboard history")
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(value: 0)
        }
        return .result(value: delegate.clipboardManager.clearSensitiveItems())
    }
}
