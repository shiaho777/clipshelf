import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FrontmostAppInfo: ObservableObject {
    static let shared = FrontmostAppInfo()
    @Published var bundleID: String?
    @Published var appName: String?
}

private struct FrontmostAppInfoKey: EnvironmentKey {
    static let defaultValue: FrontmostAppInfo = .shared
}

extension EnvironmentValues {
    var frontmostAppInfo: FrontmostAppInfo {
        get { self[FrontmostAppInfoKey.self] }
        set { self[FrontmostAppInfoKey.self] = newValue }
    }
}
