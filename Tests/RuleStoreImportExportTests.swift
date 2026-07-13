import XCTest
@testable import ClipShelf

final class RuleStoreImportExportTests: XCTestCase {
    private var store: JSONClipboardRuleStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = JSONClipboardRuleStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testExportAndImportRoundTrip() throws {
        let rules = [
            ClipboardRule(name: "Test Rule", trigger: .always, actions: [.trimWhitespace], order: 0),
            ClipboardRule(name: "URL Rule", trigger: .contentMatches(pattern: "^https://"), actions: [.stripURLTracking], order: 1),
        ]
        let exportURL = tempDir.appendingPathComponent("test.cliprules")
        try store.exportRules(to: exportURL, rules: rules)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let imported = try store.importRules(from: exportURL)
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].name, "Test Rule")
        XCTAssertEqual(imported[1].name, "URL Rule")
    }

    func testImportedRulesGetNewIDs() throws {
        let original = ClipboardRule(name: "Original", actions: [.autoPin], order: 0)
        let exportURL = tempDir.appendingPathComponent("ids.cliprules")
        try store.exportRules(to: exportURL, rules: [original])

        let imported = try store.importRules(from: exportURL)
        XCTAssertEqual(imported.count, 1)
        XCTAssertNotEqual(imported[0].id, original.id)
    }

    func testImportedRulesAreNotBuiltIn() throws {
        let builtIn = ClipboardRule(id: UUID(), name: "Built-In", isEnabled: true, isBuiltIn: true, trigger: .always, actions: [.autoPin], order: 0)
        let exportURL = tempDir.appendingPathComponent("builtin.cliprules")
        try store.exportRules(to: exportURL, rules: [builtIn])

        let imported = try store.importRules(from: exportURL)
        XCTAssertFalse(imported[0].isBuiltIn)
    }

    func testExportProducesPrettyJSON() throws {
        let rules = [ClipboardRule(name: "Pretty", actions: [.trimWhitespace], order: 0)]
        let exportURL = tempDir.appendingPathComponent("pretty.cliprules")
        try store.exportRules(to: exportURL, rules: rules)

        let data = try Data(contentsOf: exportURL)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Pretty printed JSON contains newlines and indentation
        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("  "))
    }
}
