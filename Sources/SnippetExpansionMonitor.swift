import AppKit
import Carbon.HIToolbox
import os

@MainActor
final class SnippetExpansionMonitor {
    private let snippetManager: SnippetManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "SnippetExpansion")

    private(set) var isActive: Bool = false

    private var inputBuffer = ""
    private let maxBufferLength = 64

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(snippetManager: SnippetManager) {
        self.snippetManager = snippetManager
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }

    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<SnippetExpansionMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(event)
            },
            userInfo: refcon
        ) else {
            logger.warning("Failed to create CGEvent tap — Accessibility permission may be missing")
            isActive = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        logger.info("Snippet expansion monitor started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        inputBuffer = ""
        isActive = false
    }

    private nonisolated func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if isResetKey(Int(keyCode)) {
            MainActor.assumeIsolated { inputBuffer = "" }
            return Unmanaged.passRetained(event)
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return Unmanaged.passRetained(event) }
        let typed = String(utf16CodeUnits: chars, count: length)

        MainActor.assumeIsolated {
            inputBuffer.append(typed)
            if inputBuffer.count > maxBufferLength {
                inputBuffer = String(inputBuffer.suffix(maxBufferLength))
            }

            if let match = findMatch() {
                deleteBackward(count: match.shortcut!.count)
                insertText(match.content)
                inputBuffer = ""
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func findMatch() -> Snippet? {
        for snippet in snippetManager.snippets {
            guard let shortcut = snippet.shortcut, !shortcut.isEmpty else { continue }
            if inputBuffer.hasSuffix(shortcut) {
                return snippet
            }
        }
        return nil
    }

    private nonisolated func isResetKey(_ keyCode: Int) -> Bool {
        let resetKeys: Set<Int> = [
            kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
            kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
            kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        ]
        return resetKeys.contains(keyCode)
    }

    private nonisolated func deleteBackward(count: Int) {
        for _ in 0..<count {
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) {
                down.post(tap: .cgAnnotatedSessionEventTap)
                up.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    private nonisolated func insertText(_ template: String) {
        NotificationCenter.default.post(name: .clipboardSuppressCapture, object: nil)
        let pb = NSPasteboard.general
        let savedTypes = pb.types ?? []
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        for type in savedTypes where type != .string {
            if let data = pb.data(forType: type) {
                savedData.append((type, data))
            }
        }
        let clipboardText = pb.string(forType: .string) ?? ""

        let (expanded, cursorBackCount) = SnippetVariableEngine.expand(
            template: template,
            clipboardText: clipboardText
        )

        pb.clearContents()
        pb.setString(expanded, forType: .string)

        if let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }

        if cursorBackCount > 0 {
            for _ in 0..<cursorBackCount {
                if let down = CGEvent(keyboardEventSource: nil,
                                     virtualKey: CGKeyCode(kVK_LeftArrow),
                                     keyDown: true),
                   let up = CGEvent(keyboardEventSource: nil,
                                   virtualKey: CGKeyCode(kVK_LeftArrow),
                                   keyDown: false) {
                    down.post(tap: .cgAnnotatedSessionEventTap)
                    up.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }

        let oldContents = clipboardText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .clipboardSuppressCapture, object: nil)
            pb.clearContents()
            if !oldContents.isEmpty {
                pb.setString(oldContents, forType: .string)
            }
            for (type, data) in savedData {
                pb.setData(data, forType: type)
            }
        }
    }
}
