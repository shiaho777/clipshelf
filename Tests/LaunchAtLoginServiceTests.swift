import XCTest
@testable import ClipShelf

final class LaunchAtLoginServiceTests: XCTestCase {

    private var primary: MockLaunchAtLoginService!
    private var fallback: MockLaunchAtLoginService!

    override func setUp() {
        super.setUp()
        primary = MockLaunchAtLoginService()
        fallback = MockLaunchAtLoginService()
    }

    private func makeService() -> CompositeLaunchAtLoginService {
        CompositeLaunchAtLoginService(primary: primary, fallback: fallback)
    }

    // MARK: - Composite: Enable

    func testEnableUsesPrimaryWhenItSucceeds() throws {
        let service = makeService()
        try service.setEnabled(true)
        XCTAssertEqual(primary.setEnabledCalls, [true])
        XCTAssertTrue(fallback.setEnabledCalls.isEmpty, "Fallback must not run when primary succeeds")
    }

    func testEnableFallsBackWhenPrimaryFails() throws {
        primary.errorToThrow = NSError(domain: "test", code: 1)
        let service = makeService()
        try service.setEnabled(true)
        XCTAssertEqual(primary.setEnabledCalls, [true])
        XCTAssertEqual(fallback.setEnabledCalls, [true], "Fallback should register when primary fails")
    }

    func testEnableThrowsWhenBothFail() {
        primary.errorToThrow = NSError(domain: "test", code: 1)
        fallback.errorToThrow = NSError(domain: "test", code: 2)
        let service = makeService()
        XCTAssertThrowsError(try service.setEnabled(true))
        XCTAssertEqual(fallback.setEnabledCalls, [true])
    }

    // MARK: - Composite: Disable

    func testDisableClearsBothMechanisms() throws {
        let service = makeService()
        try service.setEnabled(false)
        XCTAssertEqual(primary.setEnabledCalls, [false])
        XCTAssertEqual(fallback.setEnabledCalls, [false])
    }

    func testDisableIgnoresErrors() {
        primary.errorToThrow = NSError(domain: "test", code: 1)
        fallback.errorToThrow = NSError(domain: "test", code: 2)
        let service = makeService()
        XCTAssertNoThrow(try service.setEnabled(false))
        XCTAssertEqual(primary.setEnabledCalls, [false])
        XCTAssertEqual(fallback.setEnabledCalls, [false])
    }

    // MARK: - Composite: State

    func testIsEnabledTrueWhenEitherMechanismIsRegistered() {
        fallback.isEnabled = true
        XCTAssertTrue(makeService().isEnabled)
    }

    func testIsEnabledFalseWhenNeitherIsRegistered() {
        XCTAssertFalse(makeService().isEnabled)
    }

    // MARK: - LaunchAgent fallback

    private final class CallRecorder {
        var calls: [[String]] = []
    }

    private var tempAgentDir: URL!

    override func setUpWithError() throws {
        tempAgentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchagents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempAgentDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempAgentDir)
        try super.tearDownWithError()
    }

    private func makeLaunchAgentService(
        recorder: CallRecorder,
        launchCtlResult: @escaping ([String]) -> Int32
    ) -> LaunchAgentLaunchAtLoginService {
        LaunchAgentLaunchAtLoginService(
            label: "com.test.ClipShelf",
            executableURL: URL(fileURLWithPath: "/Applications/ClipShelf.app/Contents/MacOS/ClipShelf"),
            agentDirectory: tempAgentDir,
            uid: 501,
            runLaunchCtl: { args in
                recorder.calls.append(args)
                return launchCtlResult(args)
            }
        )
    }

    func testLaunchAgentInstallWritesPlistAndBootstraps() throws {
        let recorder = CallRecorder()
        let service = makeLaunchAgentService(recorder: recorder) { _ in 0 }

        try service.setEnabled(true)

        let plistURL = tempAgentDir.appendingPathComponent("com.test.ClipShelf.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let data = try Data(contentsOf: plistURL)
        let payload = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(payload["Label"] as? String, "com.test.ClipShelf")
        XCTAssertEqual(
            payload["ProgramArguments"] as? [String],
            ["/Applications/ClipShelf.app/Contents/MacOS/ClipShelf"]
        )
        XCTAssertEqual(payload["RunAtLoad"] as? Bool, true)
        // bootout (previous instance) then bootstrap the new plist.
        XCTAssertEqual(recorder.calls.first, ["bootout", "gui/501/com.test.ClipShelf"])
        XCTAssertEqual(recorder.calls.last, ["bootstrap", "gui/501", plistURL.path])
    }

    func testLaunchAgentInstallFallsBackToLoadWhenBootstrapFails() throws {
        let recorder = CallRecorder()
        let service = makeLaunchAgentService(recorder: recorder) { args in
            args.first == "bootstrap" ? 78 : 0
        }

        try service.setEnabled(true)

        XCTAssertEqual(
            recorder.calls.last,
            ["load", "-w", tempAgentDir.appendingPathComponent("com.test.ClipShelf.plist").path]
        )
    }

    func testLaunchAgentInstallThrowsWhenAllLoadsFail() throws {
        let recorder = CallRecorder()
        let service = makeLaunchAgentService(recorder: recorder) { _ in 78 }

        XCTAssertThrowsError(try service.setEnabled(true))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempAgentDir.appendingPathComponent("com.test.ClipShelf.plist").path
            ),
            "Plist should be removed when loading fails"
        )
    }

    func testLaunchAgentUninstallRemovesPlistAndBootsOut() throws {
        let recorder = CallRecorder()
        let service = makeLaunchAgentService(recorder: recorder) { _ in 0 }
        let plistURL = tempAgentDir.appendingPathComponent("com.test.ClipShelf.plist")
        try Data("placeholder".utf8).write(to: plistURL)

        try service.setEnabled(false)

        XCTAssertEqual(recorder.calls, [["bootout", "gui/501/com.test.ClipShelf"]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testLaunchAgentIsEnabledOnlyWhenPlistExistsAndLaunchCtlKnowsIt() throws {
        let recorder = CallRecorder()
        let service = makeLaunchAgentService(recorder: recorder) { args in
            args.first == "print" ? 0 : 78
        }

        XCTAssertFalse(service.isEnabled, "No plist yet — must be disabled")

        let plistURL = tempAgentDir.appendingPathComponent("com.test.ClipShelf.plist")
        try Data("placeholder".utf8).write(to: plistURL)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(recorder.calls, [["print", "gui/501/com.test.ClipShelf"]])

        let failing = LaunchAgentLaunchAtLoginService(
            label: "com.test.ClipShelf",
            executableURL: URL(fileURLWithPath: "/Applications/ClipShelf.app/Contents/MacOS/ClipShelf"),
            agentDirectory: tempAgentDir,
            uid: 501,
            runLaunchCtl: { _ in 78 }
        )
        XCTAssertFalse(failing.isEnabled, "Plist exists but launchctl does not know it")
    }
}
