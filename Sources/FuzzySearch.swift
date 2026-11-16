import Foundation

struct FuzzyMatch {
    let score: Int
    let item: ClipboardItem
}

enum FuzzySearch {
    private struct Candidate {
        let item: ClipboardItem
        let headLower: String
        let headOriginal: String
    }

    static func matchedIndices(query: String, in text: String) -> Set<Int>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let queryLower = trimmed.lowercased()
        let tokens = queryLower.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        let textLower = String(text.prefix(512)).lowercased()
        let textScalars = Array(textLower.unicodeScalars)

        let allTokensExact = tokens.allSatisfy { textLower.contains($0) }
        if allTokensExact {
            var indices = Set<Int>()
            for token in tokens {
                if let range = textLower.range(of: token) {
                    let startInt = textLower.distance(from: textLower.startIndex, to: range.lowerBound)
                    let endInt = textLower.distance(from: textLower.startIndex, to: range.upperBound)
                    for i in startInt..<endInt { indices.insert(i) }
                }
            }
            return indices
        }

        var allIndices = Set<Int>()
        for token in tokens {
            guard let tokenIndices = subsequenceIndices(query: token, textScalars: textScalars) else {
                return nil
            }
            allIndices.formUnion(tokenIndices)
        }
        return allIndices
    }

    private static func subsequenceIndices(query: String, in textLower: String) -> Set<Int>? {
        subsequenceIndices(query: query, textScalars: Array(textLower.unicodeScalars))
    }

    private static func subsequenceIndices(query: String, textScalars: [Unicode.Scalar]) -> Set<Int>? {
        let queryChars = Array(query.unicodeScalars)
        let textChars = textScalars
        guard !queryChars.isEmpty else { return Set() }
        guard textChars.count >= queryChars.count else { return nil }

        var indices = Set<Int>()
        var queryIndex = 0
        for (textIndex, textChar) in textChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            if textChar == queryChars[queryIndex] {
                indices.insert(textIndex)
                queryIndex += 1
            }
        }
        guard queryIndex == queryChars.count else { return nil }
        return indices
    }

    struct ParsedQuery {
        var textTokens: [String]
        var appFilter: String?
        var typeFilter: ClipboardItem.ItemType?

        var hasMetadataFilters: Bool { appFilter != nil || typeFilter != nil }
        var hasTextQuery: Bool { !textTokens.isEmpty }
    }

    static func parseQuery(_ query: String) -> ParsedQuery {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        var result = ParsedQuery(textTokens: [])
        for token in tokens {
            if token.hasPrefix("app:") {
                result.appFilter = String(token.dropFirst(4))
            } else if token.hasPrefix("type:") {
                let val = String(token.dropFirst(5))
                switch val {
                case "image": result.typeFilter = .image
                case "text": result.typeFilter = .text
                case "rich", "richtext": result.typeFilter = .richText
                case "file", "files", "fileurl", "url": result.typeFilter = .fileURL
                default: result.textTokens.append(token)
                }
            } else {
                result.textTokens.append(token)
            }
        }
        return result
    }

    static func search(_ query: String, in items: [ClipboardItem], limit: Int? = nil) -> [ClipboardItem] {
        search(query, in: items, limit: limit, where: nil)
    }

    static func search<S: Sequence>(
        _ query: String,
        in items: S,
        limit: Int? = nil,
        where predicate: ((ClipboardItem) -> Bool)? = nil
    ) -> [ClipboardItem] where S.Element == ClipboardItem {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            var result: [ClipboardItem] = []
            if let limit {
                result.reserveCapacity(limit)
                for item in items where predicate?(item) ?? true {
                    result.append(item)
                    if result.count == limit { break }
                }
                return result
            }
            for item in items where predicate?(item) ?? true {
                result.append(item)
            }
            return result
        }

        let parsed = parseQuery(trimmed)

        let combinedPredicate: (ClipboardItem) -> Bool = { item in
            if predicate?(item) == false {
                return false
            }
            if let appFilter = parsed.appFilter,
               item.sourceBundleID?.lowercased().contains(appFilter) != true {
                return false
            }
            if let typeFilter = parsed.typeFilter, item.type != typeFilter {
                return false
            }
            return true
        }

        guard parsed.hasTextQuery else {
            var result: [ClipboardItem] = []
            if let limit {
                result.reserveCapacity(limit)
                for item in items where combinedPredicate(item) {
                    result.append(item)
                    if result.count == limit { break }
                }
                return result
            }
            for item in items where combinedPredicate(item) {
                result.append(item)
            }
            return result
        }

        let tokens = parsed.textTokens
        guard !tokens.isEmpty else {
            var result: [ClipboardItem] = []
            if let limit {
                result.reserveCapacity(limit)
                for item in items where combinedPredicate(item) {
                    result.append(item)
                    if result.count == limit { break }
                }
                return result
            }
            for item in items where combinedPredicate(item) {
                result.append(item)
            }
            return result
        }
        
        let shortestToken = tokens.min(by: { $0.count < $1.count })!
        let tokenScalars = tokens.map { Array($0.unicodeScalars) }
        let shortestScalars = Array(shortestToken.unicodeScalars)

        var candidates: [Candidate] = []
        for item in items where combinedPredicate(item) {
            let searchableText = item.type == .image
                ? (item.ocrText ?? "")
                : item.content
            guard searchableText.count >= shortestToken.count else { continue }
            let headOriginal = String(searchableText.prefix(256))
            let headLower = asciiLowercased(headOriginal) ?? headOriginal.lowercased()
            guard isSubsequenceScalars(shortestScalars, of: headLower) else { continue }
            candidates.append(Candidate(item: item, headLower: headLower, headOriginal: headOriginal))
        }

        let matchLimit = limit.map { max($0, 1) }
        var heap = ScoreHeap(limit: matchLimit)
        for (offset, candidate) in candidates.enumerated() {
            let textLower = candidate.headLower
            let allTokensExact = tokens.allSatisfy { textLower.contains($0) }
            let score: Int
            if allTokensExact {
                score = 1000 + scoreExactMatch(tokens: tokens, in: textLower, original: candidate.headOriginal)
            } else {
                let textChars = Array(textLower.unicodeScalars)
                let origChars = Array(candidate.headOriginal.unicodeScalars)
                let bonus = boundaryBonusTable(textChars: textChars, origChars: origChars)
                var totalScore = 0
                var allMatch = true
                for (tokenIndex, _) in tokens.enumerated() {
                    if let tokenScore = subsequenceScorePrecomputed(queryScalars: tokenScalars[tokenIndex], textChars: textChars, bonus: bonus) {
                        totalScore += tokenScore
                    } else {
                        allMatch = false
                        break
                    }
                }
                guard allMatch else { continue }
                score = totalScore
            }
            heap.push(score: score, offset: offset, item: candidate.item)
        }
        return heap.sortedItems()
    }

    private static func boundaryBonusTable(textChars: [Unicode.Scalar], origChars: [Unicode.Scalar]) -> [Int] {
        var bonus = [Int](repeating: 0, count: textChars.count)
        for index in textChars.indices {
            if index == 0 {
                bonus[index] = 15
                continue
            }
            let prevCategory = textChars[index - 1].properties.generalCategory
            let isLetterPrev = prevCategory == .lowercaseLetter
                || prevCategory == .uppercaseLetter
                || prevCategory == .titlecaseLetter
                || prevCategory == .modifierLetter
                || prevCategory == .otherLetter
            if !isLetterPrev { bonus[index] += 15 }
            if index < origChars.count,
               origChars[index].properties.isUppercase,
               origChars[index - 1].properties.isLowercase {
                bonus[index] += 10
            }
        }
        return bonus
    }

    private static func subsequenceScorePrecomputed(queryScalars queryChars: [Unicode.Scalar], textChars: [Unicode.Scalar], bonus: [Int]) -> Int? {
        guard !queryChars.isEmpty else { return 0 }
        guard textChars.count >= queryChars.count else { return nil }
        var score = 0
        var queryIndex = 0
        var consecutiveMatches = 0
        var lastMatchIndex = -2
        for (textIndex, textChar) in textChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            if textChar == queryChars[queryIndex] {
                if textIndex == lastMatchIndex + 1 {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 1
                }
                score += bonus[textIndex]
                lastMatchIndex = textIndex
                queryIndex += 1
            }
        }
        guard queryIndex == queryChars.count else { return nil }
        score += max(0, 100 - textChars.count)
        return score
    }

    private struct ScoreHeap {
        private var entries: [(score: Int, offset: Int, item: ClipboardItem)] = []
        private let limit: Int?

        init(limit: Int?) {
            self.limit = limit
            if let limit { entries.reserveCapacity(limit + 1) }
        }

        private func worse(_ a: (score: Int, offset: Int, item: ClipboardItem), _ b: (score: Int, offset: Int, item: ClipboardItem)) -> Bool {
            if a.score != b.score { return a.score < b.score }
            return a.offset > b.offset
        }

        mutating func push(score: Int, offset: Int, item: ClipboardItem) {
            guard let limit else {
                entries.append((score, offset, item))
                return
            }
            if entries.count < limit {
                entries.append((score, offset, item))
                siftUp(entries.count - 1)
                return
            }
            guard let root = entries.first else { return }
            if score > root.score || (score == root.score && offset < root.offset) {
                entries[0] = (score, offset, item)
                siftDown(0)
            }
        }

        private mutating func siftUp(_ start: Int) {
            var index = start
            while index > 0 {
                let parent = (index - 1) / 2
                guard worse(entries[index], entries[parent]) else { break }
                entries.swapAt(index, parent)
                index = parent
            }
        }

        private mutating func siftDown(_ start: Int) {
            var index = start
            let count = entries.count
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var smallest = index
                if left < count, worse(entries[left], entries[smallest]) { smallest = left }
                if right < count, worse(entries[right], entries[smallest]) { smallest = right }
                guard smallest != index else { break }
                entries.swapAt(index, smallest)
                index = smallest
            }
        }

        func sortedItems() -> [ClipboardItem] {
            entries.sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.offset < b.offset
            }.map(\.item)
        }
    }

    private static func asciiLowercased(_ text: String) -> String? {
        var bytes = Array(text.utf8)
        for index in bytes.indices {
            let byte = bytes[index]
            if byte > 127 { return nil }
            if byte >= 65 && byte <= 90 { bytes[index] = byte + 32 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func isSubsequenceScalars(_ query: [Unicode.Scalar], of text: String) -> Bool {
        var queryIndex = 0
        guard !query.isEmpty else { return true }
        for scalar in text.unicodeScalars {
            if scalar == query[queryIndex] {
                queryIndex += 1
                if queryIndex == query.count { return true }
            }
        }
        return false
    }
    
    private static func isSubsequence(_ query: String, of text: String) -> Bool {
        var queryScalars = query.unicodeScalars.makeIterator()
        var queryCurrent = queryScalars.next()
        guard queryCurrent != nil else { return true }
        for scalar in text.unicodeScalars {
            if scalar == queryCurrent {
                queryCurrent = queryScalars.next()
                if queryCurrent == nil { return true }
            }
        }
        return queryCurrent == nil
    }
    
    private static func scoreExactMatch(tokens: [String], in textLower: String, original: String) -> Int {
        var score = 0
        for token in tokens {
            if textLower.hasPrefix(token) {
                score += 50
            }
            if original.contains(token) {
                score += 20
            }
        }
        score += max(0, 200 - textLower.count)
        return score
    }
    
    static func subsequenceScore(query: String, in textLower: String, original: String) -> Int? {
        subsequenceScore(queryScalars: Array(query.unicodeScalars), in: textLower, original: original)
    }

    static func subsequenceScore(queryScalars queryChars: [Unicode.Scalar], in textLower: String, original: String) -> Int? {
        let textChars = Array(textLower.unicodeScalars)
        let origChars = Array(original.unicodeScalars)

        guard !queryChars.isEmpty else { return 0 }
        guard textChars.count >= queryChars.count else { return nil }

        var score = 0
        var queryIndex = 0
        var consecutiveMatches = 0
        var lastMatchIndex = -2

        for (textIndex, textChar) in textChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if textChar == queryChars[queryIndex] {
                if textIndex == lastMatchIndex + 1 {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 1
                }

                if textIndex == 0 {
                    score += 15
                } else {
                    let prev = textChars[textIndex - 1]
                    let prevCategory = prev.properties.generalCategory
                    let isLetterPrev = prevCategory == .lowercaseLetter
                        || prevCategory == .uppercaseLetter
                        || prevCategory == .titlecaseLetter
                        || prevCategory == .modifierLetter
                        || prevCategory == .otherLetter
                    if !isLetterPrev {
                        score += 15
                    }
                }

                if textIndex > 0, textIndex < origChars.count {
                    if origChars[textIndex].properties.isUppercase && origChars[textIndex - 1].properties.isLowercase {
                        score += 10
                    }
                }

                lastMatchIndex = textIndex
                queryIndex += 1
            }
        }

        guard queryIndex == queryChars.count else { return nil }

        score += max(0, 100 - textChars.count)

        return score
    }
}
