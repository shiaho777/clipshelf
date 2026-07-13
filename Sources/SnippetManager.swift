import Foundation
import os

@MainActor
final class SnippetManager: ObservableObject {
    @Published var snippets: [Snippet] = []

    private let store: SnippetStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "SnippetManager")

    init(store: SnippetStore? = nil) {
        let dir = AppStoragePaths.defaultStorageDirectory()
        self.store = store ?? JSONSnippetStore(storageDirectory: dir)
        loadSnippets()
    }

    // MARK: - CRUD

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var updated = snippet
        updated.updatedAt = Date()
        snippets[idx] = updated
        save()
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Text Expansion

    /// Check if the given text matches a snippet shortcut and return its content.
    func matchExpansion(_ text: String) -> Snippet? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippets.first { snippet in
            guard let shortcut = snippet.shortcut, !shortcut.isEmpty else { return false }
            return trimmed == shortcut
        }
    }

    /// All unique categories, sorted.
    var categories: [String] {
        Array(Set(snippets.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Persistence

    private func loadSnippets() {
        do { snippets = try store.loadSnippets() }
        catch { logger.error("Failed to load snippets: \(error.localizedDescription)") }
    }

    private func save() {
        do { try store.saveSnippets(snippets) }
        catch { logger.error("Failed to save snippets: \(error.localizedDescription)") }
    }
}
