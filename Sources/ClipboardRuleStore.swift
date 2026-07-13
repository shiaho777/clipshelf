import Foundation
import os

protocol ClipboardRuleStore {
    func loadRules() throws -> [ClipboardRule]
    @discardableResult func saveRules(_ rules: [ClipboardRule]) throws -> Bool
}

final class JSONClipboardRuleStore: ClipboardRuleStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "RuleStore")
    
    init(storageDirectory: URL) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        self.fileURL = storageDirectory.appendingPathComponent("rules.json")
    }
    
    func loadRules() throws -> [ClipboardRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = Self.builtInRules()
            try? saveRules(defaults)
            return defaults
        }
        let data = try Data(contentsOf: fileURL)
        var rules = try decoder.decode([ClipboardRule].self, from: data)
        // Ensure built-in rules always exist
        let existing = Set(rules.filter(\.isBuiltIn).map(\.name))
        for builtin in Self.builtInRules() where !existing.contains(builtin.name) {
            rules.append(builtin)
        }
        return rules.sorted { $0.order < $1.order }
    }
    
    @discardableResult
    func saveRules(_ rules: [ClipboardRule]) throws -> Bool {
        let encoded = try encoder.encode(rules)
        try encoded.write(to: fileURL, options: .atomic)
        return true
    }
    
    // MARK: - Import / Export

    func exportRules(to url: URL, rules: [ClipboardRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url, options: .atomic)
    }

    func importRules(from url: URL) throws -> [ClipboardRule] {
        let data = try Data(contentsOf: url)
        var imported = try JSONDecoder().decode([ClipboardRule].self, from: data)
        // Assign new IDs to avoid collisions, mark as non-built-in
        imported = imported.map { rule in
            var r = rule
            r = ClipboardRule(id: UUID(), name: r.name, isEnabled: r.isEnabled, isBuiltIn: false, trigger: r.trigger, actions: r.actions, order: r.order)
            return r
        }
        return imported
    }

    // MARK: - Built-in Rules
    
    static func builtInRules() -> [ClipboardRule] {
        [
            ClipboardRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Strip URL Tracking",
                isEnabled: true,
                isBuiltIn: true,
                trigger: .always,
                actions: [.stripURLTracking],
                order: 0
            ),
            ClipboardRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Detect Sensitive Content",
                isEnabled: true,
                isBuiltIn: true,
                trigger: .always,
                actions: [.detectSensitive(autoDeleteSeconds: 60)],
                order: 1
            ),
            ClipboardRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Trim Trailing Whitespace",
                isEnabled: false,
                isBuiltIn: true,
                trigger: .contentType(.text),
                actions: [.trimWhitespace],
                order: 2
            )
        ]
    }
}
