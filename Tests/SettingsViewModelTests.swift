import XCTest
@testable import ClipShelf

final class SettingsViewModelTests: XCTestCase {

    private var mockService: MockLaunchAtLoginService!
    private var prefsStore: InMemoryAppPreferencesStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockService = MockLaunchAtLoginService()
        prefsStore = InMemoryAppPreferencesStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeViewModel() -> SettingsViewModel {
        SettingsViewModel(
            launchAtLoginService: mockService,
            preferencesStore: prefsStore,
            storageDirectory: tempDir
        )
    }

    // MARK: - Toggle Success

    func testToggleOnSuccess() {
        let vm = makeViewModel()
        vm.launchAtLogin = true
        vm.handleLaunchAtLoginToggleChange()
        XCTAssertEqual(mockService.setEnabledCalls, [true])
        XCTAssertEqual(prefsStore.launchAtLogin, true)
        XCTAssertNil(vm.launchAtLoginErrorKey)
    }

    func testToggleOffSuccess() {
        let vm = makeViewModel()
        prefsStore.launchAtLogin = true
        vm.loadLaunchAtLoginPreferenceIfNeeded()
        vm.launchAtLogin = false
        vm.handleLaunchAtLoginToggleChange()
        XCTAssertEqual(mockService.setEnabledCalls, [false])
        XCTAssertEqual(prefsStore.launchAtLogin, false)
    }

    // MARK: - Toggle Failure

    func testToggleFailureRollsBack() {
        let vm = makeViewModel()
        mockService.errorToThrow = NSError(domain: "test", code: 1)
        vm.launchAtLogin = true
        vm.handleLaunchAtLoginToggleChange()
        XCTAssertFalse(vm.launchAtLogin, "Should roll back to false on failure")
        XCTAssertEqual(vm.launchAtLoginErrorKey, "settings.launchAtLoginFailed")
    }

    func testToggleFailureDoesNotPersist() {
        let vm = makeViewModel()
        mockService.errorToThrow = NSError(domain: "test", code: 1)
        vm.launchAtLogin = true
        vm.handleLaunchAtLoginToggleChange()
        XCTAssertNil(prefsStore.launchAtLogin, "Should not persist on failure")
    }

    // MARK: - Load Preference

    func testLoadPreferenceFromStore() {
        prefsStore.launchAtLogin = true
        let vm = makeViewModel()
        vm.loadLaunchAtLoginPreferenceIfNeeded()
        XCTAssertTrue(vm.launchAtLogin)
    }

    func testLoadPreferenceDefaultsFalse() {
        let vm = makeViewModel()
        vm.loadLaunchAtLoginPreferenceIfNeeded()
        XCTAssertFalse(vm.launchAtLogin)
    }

    func testLoadPreferenceIdempotent() {
        prefsStore.launchAtLogin = true
        let vm = makeViewModel()
        vm.loadLaunchAtLoginPreferenceIfNeeded()
        XCTAssertTrue(vm.launchAtLogin)
        prefsStore.launchAtLogin = false  // change underlying value
        vm.loadLaunchAtLoginPreferenceIfNeeded()  // should not reload
        XCTAssertTrue(vm.launchAtLogin, "Second call should not reload")
    }
}
