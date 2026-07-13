import Foundation
import os

protocol SnippetStore {
    func loadSnippets() throws -> [Snippet]
    @discardableResult
    func saveSnippets(_ snippets: [Snippet]) throws -> Bool
}

final class JSONSnippetStore: SnippetStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager", category: "SnippetStore")

    init(storageDirectory: URL) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        self.fileURL = storageDirectory.appendingPathComponent("snippets.json")
    }

    func loadSnippets() throws -> [Snippet] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Snippet].self, from: data)
    }

    @discardableResult
    func saveSnippets(_ snippets: [Snippet]) throws -> Bool {
        let data = try encoder.encode(snippets)
        try data.write(to: fileURL, options: .atomic)
        return true
    }
}
