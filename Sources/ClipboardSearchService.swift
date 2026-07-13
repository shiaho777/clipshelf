import Foundation

struct ClipboardSearchService {
    static let fuzzyScanCap = 2_500
    static let defaultFTSLimit = 500

    struct Context {
        let items: [ClipboardItem]
        let itemByID: [UUID: ClipboardItem]
        let embeddingCache: [UUID: [Float32]]
        let resolveMissing: (UUID) -> ClipboardItem?
        let searchFTS: (String, Int) -> [UUID]
    }

    static func search(
        _ query: String,
        limit: Int? = nil,
        where predicate: ((ClipboardItem) -> Bool)? = nil,
        context: Context
    ) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return limitedItems(from: context.items, limit: limit, where: predicate)
        }

        let parsed = FuzzySearch.parseQuery(trimmed)
        var ftsItems: [ClipboardItem] = []
        if !parsed.hasMetadataFilters {
            let requestedLimit = limit ?? Self.defaultFTSLimit
            let ftsLimit: Int
            if predicate == nil {
                ftsLimit = requestedLimit
            } else {
                ftsLimit = max(500, min(2_000, requestedLimit * 8))
            }
            let ftsIDs = context.searchFTS(trimmed, ftsLimit)
            if !ftsIDs.isEmpty {
                ftsItems.reserveCapacity(min(ftsIDs.count, ftsLimit))
                for id in ftsIDs {
                    let item = context.itemByID[id] ?? context.resolveMissing(id)
                    guard let item, predicate?(item) ?? true else { continue }
                    ftsItems.append(item)
                }
            }
        }

        if !parsed.hasMetadataFilters && ftsItems.count < 3 && !context.embeddingCache.isEmpty {
            let semantic = SemanticSearchService.shared.semanticSearch(
                query: trimmed,
                embeddings: context.embeddingCache,
                itemByID: context.itemByID
            )
            let ftsIDSet = Set(ftsItems.map(\.id))
            let extra = semantic.filter { !ftsIDSet.contains($0.id) && (predicate?($0) ?? true) }
            if !extra.isEmpty {
                let result = ftsItems + extra
                guard let limit else { return result }
                return Array(result.prefix(limit))
            }
        }

        if !ftsItems.isEmpty {
            guard let limit else { return ftsItems }
            return Array(ftsItems.prefix(limit))
        }

        let fuzzySource: [ClipboardItem]
        if context.items.count > Self.fuzzyScanCap {
            fuzzySource = Array(context.items.prefix(Self.fuzzyScanCap))
        } else {
            fuzzySource = context.items
        }
        return FuzzySearch.search(trimmed, in: fuzzySource, limit: limit, where: predicate)
    }

    static func limitedItems(
        from source: [ClipboardItem],
        limit: Int?,
        where predicate: ((ClipboardItem) -> Bool)?
    ) -> [ClipboardItem] {
        guard let limit else {
            guard let predicate else { return source }
            return source.filter(predicate)
        }
        var result: [ClipboardItem] = []
        result.reserveCapacity(limit)
        for item in source where predicate?(item) ?? true {
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }
}
