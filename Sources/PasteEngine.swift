import AppKit
import Carbon.HIToolbox
import os

enum PasteFailure: Equatable {
    case noTargetApp
    case secureInput
    case activationTimeout
    case keystrokeUnavailable
}

enum PasteDecision: Equatable {
    case sendKeystroke
    case retryActivation
    case fail(PasteFailure)
}

enum PasteOutcomePolicy {
    static func decide(
        frontmostMatchesTarget: Bool,
        secureInputEnabled: Bool,
        elapsed: TimeInterval,
        activationTimeout: TimeInterval,
        keystrokesAvailable: Bool
    ) -> PasteDecision {
        if secureInputEnabled { return .fail(.secureInput) }
        if frontmostMatchesTarget {
            return keystrokesAvailable ? .sendKeystroke : .fail(.keystrokeUnavailable)
        }
        if elapsed >= activationTimeout { return .fail(.activationTimeout) }
        return .retryActivation
    }
}

@MainActor
final class PasteEngine {
    static let shared = PasteEngine()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "PasteEngine")
    private var generation: UInt64 = 0
    private var activeTask: Task<Void, Never>?
    private var lastNoticeAt: Date?

    private init() {}

    func paste(into targetApp: NSRunningApplication?, pollInterval: TimeInterval = 0.05, activationTimeout: TimeInterval = 2.0) {
        generation &+= 1
        let currentGeneration = generation
        activeTask?.cancel()
        guard let targetApp, !targetApp.isTerminated else {
            notifyFailure(.noTargetApp)
            return
        }
        activeTask = Task { @MainActor [weak self] in
            let start = Date()
            var didRequestActivation = false
            while !Task.isCancelled {
                guard let self, self.generation == currentGeneration else { return }
                let frontmostMatches = NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier
                let decision = PasteOutcomePolicy.decide(
                    frontmostMatchesTarget: frontmostMatches,
                    secureInputEnabled: IsSecureEventInputEnabled(),
                    elapsed: Date().timeIntervalSince(start),
                    activationTimeout: activationTimeout,
                    keystrokesAvailable: Self.keystrokesAvailable()
                )
                switch decision {
                case .sendKeystroke:
                    Self.postCmdV()
                    return
                case .fail(let failure):
                    self.notifyFailure(failure)
                    return
                case .retryActivation:
                    if !didRequestActivation || !frontmostMatches {
                        targetApp.activate(options: .activateIgnoringOtherApps)
                        didRequestActivation = true
                    }
                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            }
        }
    }

    func cancelPendingPaste() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    private func notifyFailure(_ failure: PasteFailure) {
        logger.warning("Paste failed: \(String(describing: failure), privacy: .public)")
        let now = Date()
        if let lastNoticeAt, now.timeIntervalSince(lastNoticeAt) < 1.0 { return }
        lastNoticeAt = now
        UserNotifier.shared.show(Self.message(for: failure), kind: .warning)
    }

    static func message(for failure: PasteFailure) -> String {
        let lang = LanguageManager.shared
        switch failure {
        case .noTargetApp: return lang.l("paste.failed.noTarget")
        case .secureInput: return lang.l("paste.failed.secureInput")
        case .activationTimeout: return lang.l("paste.failed.activation")
        case .keystrokeUnavailable: return lang.l("paste.failed.keystroke")
        }
    }

    static func keystrokesAvailable() -> Bool {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) != nil
    }

    static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}