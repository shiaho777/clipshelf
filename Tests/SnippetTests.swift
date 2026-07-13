import XCTest
@testable import ClipShelf

// MARK: - InMemorySnippetStore

private final class InMemorySnippetStore: SnippetStore {
    var snippets: [Snippet] = []

    func loadSnippets() throws -> [Snippet] { snippets }

    @discardableResult
    func saveSnippets(_ snippets: [Snippet]) throws -> Bool {
        self.snippets = snippets
        return true
    }
}

@MainActor
final class SnippetTests: XCTestCase {

    private func makeManager(preload: [Snippet] = []) -> (SnippetManager, InMemorySnippetStore) {
        let store = InMemorySnippetStore()
        store.snippets = preload
        let mgr = SnippetManager(store: store)
        return (mgr, store)
    }

    // MARK: - CRUD

    func testAddSnippet() {
        let (mgr, store) = makeManager()
        let s = Snippet(title: "Email", content: "hello@example.com")
        mgr.add(s)
        XCTAssertEqual(mgr.snippets.count, 1)
        XCTAssertEqual(store.snippets.count, 1)
        XCTAssertEqual(mgr.snippets[0].title, "Email")
    }

    func testUpdateSnippet() {
        let s = Snippet(title: "Old", content: "old content")
        let (mgr, _) = makeManager(preload: [s])
        var updated = mgr.snippets[0]
        updated.title = "New"
        updated.content = "new content"
        mgr.update(updated)
        XCTAssertEqual(mgr.snippets.count, 1)
        XCTAssertEqual(mgr.snippets[0].title, "New")
        XCTAssertEqual(mgr.snippets[0].content, "new content")
    }

    func testDeleteSnippet() {
        let s1 = Snippet(title: "A", content: "a")
        let s2 = Snippet(title: "B", content: "b")
        let (mgr, _) = makeManager(preload: [s1, s2])
        mgr.delete(mgr.snippets[0])
        XCTAssertEqual(mgr.snippets.count, 1)
        XCTAssertEqual(mgr.snippets[0].title, "B")
    }

    func testDeleteAtOffsets() {
        let items = (1...3).map { Snippet(title: "S\($0)", content: "c\($0)") }
        let (mgr, _) = makeManager(preload: items)
        mgr.delete(at: IndexSet(integer: 1))
        XCTAssertEqual(mgr.snippets.count, 2)
        XCTAssertEqual(mgr.snippets[0].title, "S1")
        XCTAssertEqual(mgr.snippets[1].title, "S3")
    }

    // MARK: - Text Expansion

    func testMatchExpansion() {
        let s = Snippet(title: "Email", content: "hello@example.com", shortcut: "/email")
        let (mgr, _) = makeManager(preload: [s])
        let match = mgr.matchExpansion("/email")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.content, "hello@example.com")
    }

    func testMatchExpansionNoMatch() {
        let s = Snippet(title: "Email", content: "hello@example.com", shortcut: "/email")
        let (mgr, _) = makeManager(preload: [s])
        XCTAssertNil(mgr.matchExpansion("/phone"))
    }

    func testMatchExpansionNoShortcut() {
        let s = Snippet(title: "No shortcut", content: "content")
        let (mgr, _) = makeManager(preload: [s])
        XCTAssertNil(mgr.matchExpansion("content"))
    }

    // MARK: - Categories

    func testCategories() {
        let items = [
            Snippet(title: "A", content: "a", category: "Work"),
            Snippet(title: "B", content: "b", category: "Personal"),
            Snippet(title: "C", content: "c", category: "Work"),
            Snippet(title: "D", content: "d")
        ]
        let (mgr, _) = makeManager(preload: items)
        XCTAssertEqual(mgr.categories, ["Personal", "Work"])
    }

    // MARK: - Persistence

    func testLoadFromStore() {
        let preloaded = [Snippet(title: "Pre", content: "loaded")]
        let (mgr, _) = makeManager(preload: preloaded)
        XCTAssertEqual(mgr.snippets.count, 1)
        XCTAssertEqual(mgr.snippets[0].title, "Pre")
    }
}
