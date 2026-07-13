import Foundation

struct FuzzyMatch {
    let score: Int
    let item: ClipboardItem
}

enum FuzzySearch {
    /// Returns the set of character indices in `text` that match the given query.
    /// Mirrors the matching logic of `search()`: tries exact token match first, then fuzzy subsequence.
    /// Returns nil if the text does not match the query at all.
    static func matchedIndices(query: String, in text: String) -> Set<Int>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let queryLower = trimmed.lowercased()
        let tokens = queryLower.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        let textLower = text.lowercased()

        // Try exact token matching first
        let allTokensExact = tokens.allSatisfy { textLower.contains($0) }
        if allTokensExact {
            var indices = Set<Int>()
            for token in tokens {
                // Find the first occurrence of each token
                if let range = textLower.range(of: token) {
                    let startInt = textLower.distance(from: textLower.startIndex, to: range.lowerBound)
                    let endInt = textLower.distance(from: textLower.startIndex, to: range.upperBound)
                    for i in startInt..<endInt { indices.insert(i) }
                }
            }
            return indices
        }

        // Try fuzzy subsequence matching for each token
        var allIndices = Set<Int>()
        for token in tokens {
            guard let tokenIndices = subsequenceIndices(query: token, in: textLower) else {
                return nil
            }
            allIndices.formUnion(tokenIndices)
        }
        return allIndices
    }

    /// Returns the character indices in `textLower` where query characters matched as a subsequence.
    /// Returns nil if no subsequence match.
    private static func subsequenceIndices(query: String, in textLower: String) -> Set<Int>? {
        let queryChars = Array(query)
        let textChars = Array(textLower)
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

    // MARK: - Search Query Parsing

    /// Parsed components from a search query like "app:com.apple.Safari type:text hello"
    struct ParsedQuery {
        var textTokens: [String]
        var appFilter: String?      // app:bundleID
        var typeFilter: ClipboardItem.ItemType?  // type:text|image|rich

        var hasMetadataFilters: Bool { appFilter != nil || typeFilter != nil }
        var hasTextQuery: Bool { !textTokens.isEmpty }
    }

    /// Parse a query string, extracting `app:` and `type:` prefixes.
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
        
        var matches: [FuzzyMatch] = []
        let matchLimit = limit.map { max($0, 1) }
        
        for item in items where combinedPredicate(item) {
            let searchableText = item.type == .image
                ? (item.ocrText ?? "")
                : item.content
            
            guard searchableText.count >= shortestToken.count else { continue }
            
            let textLower = searchableText.lowercased()
            
            if !isSubsequence(shortestToken, of: textLower) { continue }
            
            let allTokensExact = tokens.allSatisfy { textLower.contains($0) }
            if allTokensExact {
                let exactBonus = 1000
                let score = exactBonus + scoreExactMatch(tokens: tokens, in: textLower, original: searchableText)
                appendMatch(FuzzyMatch(score: score, item: item), to: &matches, limit: matchLimit)
                continue
            }
            
            var totalScore = 0
            var allMatch = true
            for token in tokens {
                if let tokenScore = subsequenceScore(query: token, in: textLower, original: searchableText) {
                    totalScore += tokenScore
                } else {
                    allMatch = false
                    break
                }
            }
            
            if allMatch {
                appendMatch(FuzzyMatch(score: totalScore, item: item), to: &matches, limit: matchLimit)
            }
        }
        
        let sorted = matches.enumerated().sorted { a, b in
            if a.element.score != b.element.score {
                return a.element.score > b.element.score
            }
            return a.offset < b.offset
        }
        if let limit {
            return sorted.prefix(limit).map(\.element.item)
        }
        return sorted.map(\.element.item)
    }

    private static func appendMatch(_ match: FuzzyMatch, to matches: inout [FuzzyMatch], limit: Int?) {
        guard let limit else {
            matches.append(match)
            return
        }
        if matches.count < limit {
            matches.append(match)
            return
        }
        guard let lowestIndex = matches.indices.min(by: { matches[$0].score < matches[$1].score }),
              match.score > matches[lowestIndex].score else { return }
        matches[lowestIndex] = match
    }
    
    /// Quick subsequence check without scoring — O(n) early filter.
    private static func isSubsequence(_ query: String, of text: String) -> Bool {
        var qi = query.startIndex
        var ti = text.startIndex
        while qi < query.endIndex && ti < text.endIndex {
            if query[qi] == text[ti] { qi = query.index(after: qi) }
            ti = text.index(after: ti)
        }
        return qi == query.endIndex
    }
    
    // MARK: - Scoring
    
    /// Score for exact token containment — rewards prefix match and shorter targets.
    private static func scoreExactMatch(tokens: [String], in textLower: String, original: String) -> Int {
        var score = 0
        for token in tokens {
            if textLower.hasPrefix(token) {
                score += 50  // starts-with bonus
            }
            // Case-sensitive exact match bonus
            if original.contains(token) {
                score += 20
            }
        }
        // Shorter content = more relevant (normalized)
        score += max(0, 200 - textLower.count)
        return score
    }
    
    /// Subsequence matching: query characters must appear in order within the target.
    /// Returns a score, or nil if no match.
    static func subsequenceScore(query: String, in textLower: String, original: String) -> Int? {
        let queryChars = Array(query)
        let textChars = Array(textLower)
        // Pre-build once here; previously this was allocated inside the hot loop
        // for every matched character, causing O(n²) allocations per search item.
        let origChars = Array(original)

        guard !queryChars.isEmpty else { return 0 }
        guard textChars.count >= queryChars.count else { return nil }
        
        var score = 0
        var queryIndex = 0
        var consecutiveMatches = 0
        var lastMatchIndex = -2  // impossible index to start
        
        for (textIndex, textChar) in textChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            
            if textChar == queryChars[queryIndex] {
                // Consecutive character bonus
                if textIndex == lastMatchIndex + 1 {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 1
                }
                
                // Word boundary bonus (start of word)
                if textIndex == 0 || !textChars[textIndex - 1].isLetter {
                    score += 15
                }
                
            // CamelCase boundary bonus
                if textIndex > 0, textIndex < origChars.count {
                    if origChars[textIndex].isUppercase && origChars[textIndex - 1].isLowercase {
                        score += 10
                    }
                }
                
                lastMatchIndex = textIndex
                queryIndex += 1
            }
        }
        
        // All query characters must be matched
        guard queryIndex == queryChars.count else { return nil }
        
        // Shorter content = more relevant
        score += max(0, 100 - textChars.count)
        
        return score
    }
}
