import Foundation
import AppKit

struct UpdateRelease: Equatable {
    let version: String
    let assetName: String
    let assetURL: URL
    let size: Int64
}

enum UpdateReleaseParser {

    static func parse(_ data: Data) -> UpdateRelease? {
        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let version = object["tag_name"] as? String,
            let assets = object["assets"] as? [[String: Any]],
            let asset = pickDMGAsset(assets),
            let url = URL(string: asset.url)
        else { return nil }
        return UpdateRelease(version: version, assetName: asset.name, assetURL: url, size: asset.size)
    }

    static func pickDMGAsset(_ assets: [[String: Any]]) -> (name: String, url: String, size: Int64)? {
        let dmgs = assets.filter {
            ($0["name"] as? String).map { $0.lowercased().hasSuffix(".dmg") } ?? false
        }
        let preferred = dmgs.first {
            ($0["name"] as? String)?.lowercased().contains("universal") ?? false
        } ?? dmgs.first
        guard
            let candidate = preferred,
            let name = candidate["name"] as? String,
            let url = candidate["browser_download_url"] as? String
        else { return nil }
        let size = (candidate["size"] as? NSNumber)?.int64Value ?? 0
        return (name, url, size)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        func components(_ raw: String) -> [Int] {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
            if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
            return s.split(separator: ".").compactMap { Int($0) }
        }
        let a = components(lhs)
        let b = components(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double, Int64, Int64) -> Void
    private let onFinish: (URL) -> Void
    private let onError: (Error) -> Void

    init(onProgress: @escaping (Double, Int64, Int64) -> Void,
         onFinish: @escaping (URL) -> Void,
         onError: @escaping (Error) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        onProgress(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        onFinish(location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onError(error) }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let apiURL = URL(string: "https://api.github.com/repos/shiaho777/clipshelf/releases/latest")!

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading(fraction: Double, received: Int64, total: Int64, speedBytesPerSec: Double)
        case ready(url: URL, version: String)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle

    private var downloadTask: URLSessionTask?
    private var downloadSession: URLSession?
    private var pendingRelease: UpdateRelease?
    private var currentDownload: (version: String, targetURL: URL)?
    private var speedSamples: [(time: Date, bytes: Int64)] = []

    private init() {}

    func checkForUpdates() {
        switch phase {
        case .idle, .checking, .upToDate, .failed: break
        case .available, .downloading, .ready: return
        }
        phase = .checking
        let task = URLSession.shared.dataTask(with: Self.apiURL) { [weak self] data, _, error in
            Task { @MainActor in
                self?.didFinishCheck(data: data, error: error)
            }
        }
        task.resume()
    }

    private func didFinishCheck(data: Data?, error: Error?) {
        if let error {
            phase = .failed(message: error.localizedDescription)
            return
        }
        guard let data, let release = UpdateReleaseParser.parse(data) else {
            phase = .failed(message: LanguageManager.shared.l("update.noRelease"))
            return
        }
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        if UpdateReleaseParser.compareVersions(release.version, current) > 0 {
            phase = .available(release)
        } else {
            phase = .upToDate
        }
    }

    func startDownload() {
        guard case .available(let release) = phase else { return }
        beginDownload(release: release)
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func beginDownload(release: UpdateRelease) {
        pendingRelease = release
        let dir = Self.downloadsDirectory()
        let targetURL = dir.appendingPathComponent("ClipShelf-\(release.version).dmg")
        currentDownload = (release.version, targetURL)
        speedSamples.removeAll()
        phase = .downloading(fraction: 0, received: 0, total: 0, speedBytesPerSec: 0)

        let delegate = DownloadProgressDelegate(
            onProgress: { [weak self] fraction, received, total in
                Task { @MainActor in
                    self?.didProgress(fraction: fraction, received: received, total: total)
                }
            },
            onFinish: { [weak self] location in
                Task { @MainActor in
                    self?.didFinishDownload(at: location)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.didFailDownload(error)
                }
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadSession = session
        let task = session.downloadTask(with: release.assetURL)
        task.resume()
        downloadTask = task
    }

    private func didProgress(fraction: Double, received: Int64, total: Int64) {
        guard case .downloading = phase else { return }
        let now = Date()
        speedSamples.append((now, received))
        speedSamples.removeAll { now.timeIntervalSince($0.time) > 2.0 }
        var speed: Double = 0
        if let oldest = speedSamples.first, received > oldest.bytes,
           now.timeIntervalSince(oldest.time) > 0.25 {
            speed = Double(received - oldest.bytes) / now.timeIntervalSince(oldest.time)
        }
        phase = .downloading(fraction: fraction, received: received, total: total, speedBytesPerSec: speed)
    }

    private func didFinishDownload(at location: URL) {
        guard let (version, targetURL) = currentDownload else { return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: targetURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }
            try fm.moveItem(at: location, to: targetURL)
            phase = .ready(url: targetURL, version: version)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func didFailDownload(_ error: Error) {
        if (error as NSError?)?.code == NSURLErrorCancelled {
            if let release = pendingRelease {
                phase = .available(release)
            } else {
                phase = .idle
            }
            return
        }
        phase = .failed(message: error.localizedDescription)
    }

    func install() {
        guard case .ready(let url, _) = phase else { return }
        NSWorkspace.shared.open(url)
    }

    static func downloadsDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ClipShelf/Updates", isDirectory: true)
    }
}
