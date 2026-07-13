import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import os

/// Indexes clipboard history items in CoreSpotlight so they appear in macOS system search.
/// Sensitive items (`isSensitive = true`) are never indexed.
@MainActor
final class SpotlightIndexService {
    static let shared = SpotlightIndexService()

    private let domainID = "com.clipshelf.clipboardHistory"
    private let index = CSSearchableIndex.default()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf",
                                category: "Spotlight")
    private var pendingItems: [UUID: ClipboardItem] = [:]
    private var pendingWork: DispatchWorkItem?

    private init() {}

    // MARK: - Public API

    /// Batch-index items on startup. Runs asynchronously in a background Task.
    func indexItems(_ items: [ClipboardItem]) {
        let eligible = items.filter { !$0.isSensitive }
        guard !eligible.isEmpty else { return }
        let domainID = domainID
        let index = index
        let logger = logger
        Task.detached(priority: .background) {
            let searchItems = eligible.map { Self.makeSearchableItem($0, domainID: domainID) }
            do {
                try await index.indexSearchableItems(searchItems)
            } catch {
                await MainActor.run {
                    logger.error("Spotlight batch index failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Index a single item (call after adding a new item).
    func indexItem(_ item: ClipboardItem) {
        guard !item.isSensitive else { return }
        pendingItems[item.id] = item
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let items = Array(self.pendingItems.values)
            self.pendingItems.removeAll(keepingCapacity: true)
            self.indexItems(items)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Remove a single item from the Spotlight index.
    func deindexItem(id: UUID) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                try await self.index.deleteSearchableItems(withIdentifiers: [id.uuidString])
            } catch {
                await MainActor.run {
                    self.logger.error("Spotlight deindex failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Remove all ClipShelf items from the Spotlight index.
    func deindexAll() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                try await self.index.deleteSearchableItems(withDomainIdentifiers: [self.domainID])
            } catch {
                await MainActor.run {
                    self.logger.error("Spotlight deindex all failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated private static func makeSearchableItem(_ item: ClipboardItem, domainID: String) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // Title: source app name or type badge
        let typeLabel: String
        switch item.type {
        case .text:    typeLabel = "Text"
        case .richText: typeLabel = "Rich Text"
        case .image:   typeLabel = "Image"
        case .fileURL: typeLabel = "File"
        }
        attributeSet.title = item.sourceAppName.map { "\($0) — \(typeLabel)" } ?? typeLabel

        // Searchable text body (capped at 1000 chars; images use OCR text)
        let body: String
        if item.type == .image {
            body = item.ocrText ?? ""
        } else if item.type == .fileURL {
            body = item.content  // path strings
        } else {
            body = String(item.content.prefix(1000))
        }
        attributeSet.textContent = body
        attributeSet.contentDescription = String(body.prefix(200))

        attributeSet.addedDate = item.timestamp
        attributeSet.metadataModificationDate = item.timestamp

        if let appName = item.sourceAppName {
            attributeSet.authorNames = [appName]
        }

        return CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attributeSet
        )
    }
}
