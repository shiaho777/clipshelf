import Foundation
import AppKit
import ImageIO
import os

struct CapturedContent {
    enum Kind {
        case text(content: String)
        case richText(content: String, rtfData: Data)
        case image(data: Data)
        case imageFile(data: Data, fileExtension: String)
        case fileURL(paths: [String])
    }
    let kind: Kind
    let sourceBundleID: String?
    let sourceAppName: String?
    var isScreenshot: Bool = false
}

extension Notification.Name {
    static let clipboardSuppressCapture = Notification.Name("ClipboardSuppressCapture")
}

final class ClipboardMonitor {
    enum Cadence {
        static let active: TimeInterval = 0.35
        static let normal: TimeInterval = 1.0
        static let idle: TimeInterval = 5.0
        static let deepIdle: TimeInterval = 12.0
    }

    enum CheckOutcome {
        case noChange
        case captured
        case ignored
    }

    var onCapture: ((CapturedContent) -> Void)?
    var excludedBundleIDs: Set<String> = []
    private var suppressionsRemaining = 0
    var suppressNextCapture: Bool {
        get { suppressionsRemaining > 0 }
        set { suppressionsRemaining = max(0, suppressionsRemaining + (newValue ? 1 : -1)) }
    }

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard: NSPasteboard
    private var lastContent: String = ""
    private var lastAddTime: Date = .distantPast
    private var monitorInterval: TimeInterval = Cadence.normal
    private var unchangedPollCount = 0
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "Monitor")
    private var appActivationObserver: NSObjectProtocol?
    private var suppressObserver: NSObjectProtocol?
    private var currentBundleID: String?
    private var currentAppName: String?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func start() {
        lastChangeCount = pasteboard.changeCount
        unchangedPollCount = 0
        updateCurrentApplication()
        scheduleTimer(interval: Cadence.normal)
        observeAppActivation()
        suppressObserver = NotificationCenter.default.addObserver(
            forName: .clipboardSuppressCapture, object: nil, queue: .main
        ) { [weak self] _ in
            self?.suppressNextCapture = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
        if let obs = suppressObserver {
            NotificationCenter.default.removeObserver(obs)
            suppressObserver = nil
        }
    }

    func acknowledgeChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        monitorInterval = interval
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = interval * 0.25
        timer = t
    }

    private func adjustCadence(to interval: TimeInterval) {
        guard abs(monitorInterval - interval) > 0.01 else { return }
        scheduleTimer(interval: interval)
    }

    private func tick() {
        switch checkClipboard() {
        case .captured:
            unchangedPollCount = 0
            adjustCadence(to: Cadence.active)
        case .ignored:
            unchangedPollCount = 0
            adjustCadence(to: Cadence.normal)
        case .noChange:
            unchangedPollCount += 1
            if unchangedPollCount > 60 {
                adjustCadence(to: Cadence.deepIdle)
            } else if unchangedPollCount > 20 {
                adjustCadence(to: Cadence.idle)
            } else if unchangedPollCount > 8 {
                adjustCadence(to: Cadence.normal)
            }
        }
    }

    private func observeAppActivation() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.timer != nil else { return }
            self.updateCurrentApplication()
            self.unchangedPollCount = 0
            self.adjustCadence(to: Cadence.active)
        }
    }

    private func updateCurrentApplication() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        currentBundleID = frontApp?.bundleIdentifier
        currentAppName = frontApp?.localizedName
    }

    @discardableResult
    func checkClipboard() -> CheckOutcome {
        guard pasteboard.changeCount != lastChangeCount else { return .noChange }
        lastChangeCount = pasteboard.changeCount
        if suppressionsRemaining > 0 {
            suppressionsRemaining -= 1
            return .ignored
        }

        if currentBundleID == nil && currentAppName == nil {
            updateCurrentApplication()
        }
        let bundleID = currentBundleID
        let appName = currentAppName

        if let bundleID, excludedBundleIDs.contains(bundleID) {
            return .ignored
        }

        let types = pasteboard.types ?? []

        if types.contains(.rtf),
           let rtfData = pasteboard.data(forType: .rtf),
           let plainText = pasteboard.string(forType: .string), !plainText.isEmpty {
            let now = Date()
            if plainText == lastContent && now.timeIntervalSince(lastAddTime) < 3 { return .ignored }
            lastContent = plainText
            lastAddTime = now
            onCapture?(CapturedContent(kind: .richText(content: plainText, rtfData: rtfData), sourceBundleID: bundleID, sourceAppName: appName))
            return .captured
        }

        if types.contains(.string),
           let string = pasteboard.string(forType: .string), !string.isEmpty {
            let now = Date()
            let interval = now.timeIntervalSince(lastAddTime)
            if string == lastContent && interval < 3 { return .ignored }
            if !lastContent.isEmpty && interval < 3 {
                if lastContent.contains(string) || string.hasPrefix(lastContent) || lastContent.hasPrefix(string) {
                    if string.count > lastContent.count {
                        lastContent = string
                        lastAddTime = now
                        onCapture?(CapturedContent(kind: .text(content: string), sourceBundleID: bundleID, sourceAppName: appName))
                        return .captured
                    } else if string.count < lastContent.count {
                        lastContent = string
                        lastAddTime = now
                        onCapture?(CapturedContent(kind: .text(content: string), sourceBundleID: bundleID, sourceAppName: appName))
                        return .captured
                    } else {
                        return .ignored
                    }
                }
            }
            lastContent = string
            lastAddTime = now
            onCapture?(CapturedContent(kind: .text(content: string), sourceBundleID: bundleID, sourceAppName: appName))
            return .captured
        }

        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            let filePaths = urls.filter { $0.isFileURL }.map(\.path)
            if !filePaths.isEmpty {
                let content = filePaths.joined(separator: "\n")
                let now = Date()
                if content == lastContent && now.timeIntervalSince(lastAddTime) < 3 { return .ignored }
                lastContent = content
                lastAddTime = now
                let isScreenshot = filePaths.contains { Self.isScreenshotPath($0) }
                onCapture?(CapturedContent(kind: .fileURL(paths: filePaths), sourceBundleID: bundleID, sourceAppName: appName, isScreenshot: isScreenshot))
                return .captured
            }
        }

        if let capturedImage = captureImageData() {
            let isScreenshot = Self.hasScreenshotMetadata(pasteboard: pasteboard)
            onCapture?(CapturedContent(kind: capturedImage, sourceBundleID: bundleID, sourceAppName: appName, isScreenshot: isScreenshot))
            return .captured
        }

        return .ignored
    }

    private func captureImageData() -> CapturedContent.Kind? {
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return .imageFile(data: pngData, fileExtension: "png")
        }
        if let jpegData = pasteboard.data(forType: .init("public.jpeg")), !jpegData.isEmpty {
            return .imageFile(data: jpegData, fileExtension: "jpg")
        }
        if let heicData = pasteboard.data(forType: .init("public.heic")), !heicData.isEmpty {
            return .imageFile(data: heicData, fileExtension: "heic")
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let cgImage = cgImage(from: tiffData) {
            return pngData(from: cgImage).map { .imageFile(data: $0, fileExtension: "png") }
        }
        if let nsImage = NSImage(pasteboard: pasteboard),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return pngData(from: cgImage).map { .imageFile(data: $0, fileExtension: "png") }
        }
        return nil
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Data(referencing: mutableData)
    }

    private static func isScreenshotPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        let englishPrefixes = ["screenshot", "screen recording", "screen shot"]
        if englishPrefixes.contains(where: { lowerName.hasPrefix($0) }) { return true }
        let chinesePrefixes = ["截屏", "屏幕录制", "屏幕快照"]
        if chinesePrefixes.contains(where: { name.hasPrefix($0) }) { return true }
        return false
    }

    private static func hasScreenshotMetadata(pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        for type in types {
            let raw = type.rawValue
            if raw.contains("com.apple.screenshot") || raw.contains("screenshot") { return true }
            if raw == "com.apple.pasteboard.promised-file-url" { return true }
        }
        return false
    }
}
