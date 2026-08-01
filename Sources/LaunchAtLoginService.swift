import ServiceManagement

protocol LaunchAtLoginService {
    /// Whether the app is currently registered as a login item on the system.
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginServiceFactory {
    /// The production service: SMAppService with a LaunchAgent fallback.
    static func defaultService() -> LaunchAtLoginService {
        CompositeLaunchAtLoginService(
            primary: SMAppLaunchAtLoginService(),
            fallback: LaunchAgentLaunchAtLoginService()
        )
    }
}

/// Registers via SMAppService (the modern macOS 13+ login item API).
final class SMAppLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            // unregister() throws when nothing is registered; ignore that.
            try? SMAppService.mainApp.unregister()
        }
    }
}

/// Fallback registration via a per-user LaunchAgent plist. Works for
/// ad-hoc/unsigned developer builds where SMAppService.register() can fail,
/// and on any supported macOS version.
final class LaunchAgentLaunchAtLoginService: LaunchAtLoginService {
    private let label: String
    private let executableURL: URL
    private let agentDirectory: URL
    private let uid: uid_t
    private let runLaunchCtl: ([String]) -> Int32

    init(
        label: String = Bundle.main.bundleIdentifier ?? "com.nicebro.ClipShelf",
        executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: "/dev/null"),
        agentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        uid: uid_t = getuid(),
        runLaunchCtl: @escaping ([String]) -> Int32 = LaunchAgentLaunchAtLoginService.defaultLaunchCtl
    ) {
        self.label = label
        self.executableURL = executableURL
        self.agentDirectory = agentDirectory
        self.uid = uid
        self.runLaunchCtl = runLaunchCtl
    }

    private var plistURL: URL {
        agentDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }
        return runLaunchCtl(["print", "gui/\(uid)/\(label)"]) == 0
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            uninstall()
        }
    }

    private func install() throws {
        try FileManager.default.createDirectory(
            at: agentDirectory, withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .xml, options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        // Drop any previous instance before bootstrapping the new plist.
        _ = runLaunchCtl(["bootout", "gui/\(uid)/\(label)"])
        guard runLaunchCtl(["bootstrap", "gui/\(uid)", plistURL.path]) == 0 else {
            // bootstrap can be finicky on some systems; fall back to legacy load.
            guard runLaunchCtl(["load", "-w", plistURL.path]) == 0 else {
                try? FileManager.default.removeItem(at: plistURL)
                throw LaunchAgentError.failedToLoad
            }
            return
        }
    }

    private func uninstall() {
        _ = runLaunchCtl(["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func defaultLaunchCtl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

/// Tries the primary service first; falls back to the legacy service when
/// registration fails (e.g. unsigned builds on systems where SMAppService
/// refuses to register). Disabling clears both mechanisms.
final class CompositeLaunchAtLoginService: LaunchAtLoginService {
    private let primary: LaunchAtLoginService
    private let fallback: LaunchAtLoginService

    init(primary: LaunchAtLoginService, fallback: LaunchAtLoginService) {
        self.primary = primary
        self.fallback = fallback
    }

    var isEnabled: Bool { primary.isEnabled || fallback.isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try primary.setEnabled(true)
            } catch {
                try fallback.setEnabled(true)
            }
        } else {
            try? primary.setEnabled(false)
            try? fallback.setEnabled(false)
        }
    }
}

private enum LaunchAgentError: LocalizedError {
    case failedToLoad

    var errorDescription: String? {
        "Could not load the LaunchAgent login item"
    }
}
