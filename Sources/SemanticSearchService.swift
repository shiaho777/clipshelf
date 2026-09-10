import Foundation
import NaturalLanguage
import Accelerate
import os

final class SemanticSearchService {
    static let shared = SemanticSearchService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf",
                                category: "SemanticSearch")
    private let queue = DispatchQueue(label: "SemanticSearch.embedding", qos: .utility)

    private let sentenceModel: NLEmbedding?
    private let wordModel: NLEmbedding?
    private let dimension: Int

    private let queryEmbeddingCache = NSCache<NSString, QueryVectorBox>()

    var isAvailable: Bool { sentenceModel != nil || wordModel != nil }

    private final class QueryVectorBox {
        let vector: [Float32]
        init(_ vector: [Float32]) { self.vector = vector }
    }

    private init() {
        sentenceModel = NLEmbedding.sentenceEmbedding(for: .english)
        wordModel = NLEmbedding.wordEmbedding(for: .english)
        if let s = sentenceModel {
            dimension = s.dimension
        } else if let w = wordModel {
            dimension = w.dimension
        } else {
            dimension = 0
        }
    }

    func computeEmbedding(for text: String) -> [Float32]? {
        guard !text.isEmpty, dimension > 0 else { return nil }

        if let model = sentenceModel,
           let vector = model.vector(for: text) {
            return vector.map { Float32($0) }
        }

        if let model = wordModel {
            return averageWordEmbedding(text: text, model: model)
        }
        return nil
    }

    func scheduleEmbeddingBatch(for items: [ClipboardItem],
                                store: SQLiteHistoryStore,
                                cachedIDs: Set<UUID>,
                                onNewEmbeddings: (([UUID: [Float32]]) -> Void)? = nil) {
        guard isAvailable else { return }
        let candidates = items.filter {
            !cachedIDs.contains($0.id) &&
            $0.type != .image &&
            !$0.content.isEmpty &&
            !$0.isSensitive
        }
        guard !candidates.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            var fresh: [UUID: [Float32]] = [:]
            for item in candidates {
                guard let vector = self.computeEmbedding(for: item.content) else { continue }
                store.saveEmbedding(vector, for: item.id)
                fresh[item.id] = vector
            }
            if let callback = onNewEmbeddings, !fresh.isEmpty {
                DispatchQueue.main.async { callback(fresh) }
            }
        }
    }

    func semanticSearch(query: String,
                        embeddings: [UUID: [Float32]],
                        itemByID: [UUID: ClipboardItem],
                        limit: Int = 20) -> [ClipboardItem] {
        guard isAvailable, !query.isEmpty, !embeddings.isEmpty else { return [] }

        guard let queryVec = cachedQueryEmbedding(for: query) else { return [] }
        let queryNorm = l2Norm(queryVec)
        guard queryNorm > 1e-6 else { return [] }

        var scored: [(item: ClipboardItem, score: Float32)] = []

        for (id, vec) in embeddings {
            guard let item = itemByID[id] else { continue }
            guard vec.count == queryVec.count else { continue }
            let score = cosineSimilarity(queryVec, queryNorm, vec)
            if score > 0.35 { scored.append((item, score)) }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.item }
    }

    private func cachedQueryEmbedding(for query: String) -> [Float32]? {
        let key = query as NSString
        if let boxed = queryEmbeddingCache.object(forKey: key) {
            return boxed.vector
        }
        guard let vector = computeEmbedding(for: query) else { return nil }
        queryEmbeddingCache.setObject(QueryVectorBox(vector), forKey: key, cost: vector.count * MemoryLayout<Float32>.size)
        return vector
    }

    func float32ArrayToData(_ vector: [Float32]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    func dataToFloat32Array(_ data: Data) -> [Float32] {
        data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }
    }

    private func averageWordEmbedding(text: String, model: NLEmbedding) -> [Float32]? {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if let vec = model.vector(for: token) {
                for i in 0..<min(vec.count, sum.count) { sum[i] += vec[i] }
                count += 1
            }
            return true
        }
        guard count > 0 else { return nil }
        let scale = 1.0 / Double(count)
        return sum.map { Float32($0 * scale) }
    }

    private func l2Norm(_ v: [Float32]) -> Float32 {
        var result: Float32 = 0
        vDSP_svesq(v, 1, &result, vDSP_Length(v.count))
        return sqrt(result)
    }

    private func cosineSimilarity(_ a: [Float32], _ aNorm: Float32,
                                  _ b: [Float32]) -> Float32 {
        var dot: Float32 = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        let bNorm = l2Norm(b)
        let denom = aNorm * bNorm
        return denom > 1e-6 ? dot / denom : 0
    }
}
