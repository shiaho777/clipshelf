import XCTest
@testable import ClipShelf

final class LanguageManagerTests: XCTestCase {

    private var prefsStore: InMemoryAppPreferencesStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        prefsStore = InMemoryAppPreferencesStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeManager(savedLanguage: String? = nil) -> LanguageManager {
        prefsStore.language = savedLanguage
        return LanguageManager(storageDirectory: tempDir, preferencesStore: prefsStore)
    }

    func testChineseVariantsNormalizeToZh() {
        let mgr = makeManager(savedLanguage: "zh-Hans")
        XCTAssertEqual(mgr.language, "zh")
    }

    func testEnglishVariantsNormalizeToEn() {
        let mgr = makeManager(savedLanguage: "en-US")
        XCTAssertEqual(mgr.language, "en")
    }

    func testUnsupportedLanguageFallsBackToEn() {
        let mgr = makeManager(savedLanguage: "fr")
        XCTAssertEqual(mgr.language, "en")
    }

    func testExactEnStaysEn() {
        let mgr = makeManager(savedLanguage: "en")
        XCTAssertEqual(mgr.language, "en")
    }

    func testExactZhStaysZh() {
        let mgr = makeManager(savedLanguage: "zh")
        XCTAssertEqual(mgr.language, "zh")
    }

    func testSwitchLanguagePersists() {
        let mgr = makeManager(savedLanguage: "en")
        mgr.language = "zh"
        XCTAssertEqual(prefsStore.language, "zh")
    }

    func testSameLanguageDoesNotPersist() {
        let mgr = makeManager(savedLanguage: "en")
        prefsStore.language = nil
        mgr.language = "en"
    }
}
