import Foundation
import AppKit
import Carbon.HIToolbox
import SwiftUI
import os

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in utf16.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}

struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    
    static let defaultMain = HotKeyConfig(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧V
    static let defaultQueue = HotKeyConfig(keyCode: 0x0B, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧B
    static let defaultQuickPaste = HotKeyConfig(keyCode: 9, modifiers: UInt32(cmdKey | optionKey)) // ⌘⌥V
    
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
    
    private func keyCodeToString(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x28: "K", 0x2C: "/", 0x2D: "N",
            0x2E: "M", 0x2F: ".", 0x31: " ", 0x32: "`"
        ]
        return keyMap[code] ?? "?"
    }
}

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    static let mainHotKeySignature = OSType("CBMG".fourCharCodeValue)
    static let mainHotKeyID: UInt32 = 1
    static let queueHotKeySignature = OSType("CBMQ".fourCharCodeValue)
    static let queueHotKeyID: UInt32 = 2
    static let quickPasteHotKeySignature = OSType("CBQP".fourCharCodeValue)
    static let quickPasteHotKeyID: UInt32 = 3
    
    @Published var mainHotKey: HotKeyConfig = .defaultMain {
        didSet {
            guard oldValue != mainHotKey else { return }
            saveConfig()
            reregisterMainHotKey()
        }
    }
    @Published var queueHotKey: HotKeyConfig = .defaultQueue {
        didSet {
            guard oldValue != queueHotKey else { return }
            saveConfig()
            reregisterQueueHotKey()
        }
    }
    @Published var quickPasteHotKey: HotKeyConfig = .defaultQuickPaste {
        didSet {
            guard oldValue != quickPasteHotKey else { return }
            saveConfig()
            reregisterQuickPasteHotKey()
        }
    }
    @Published private(set) var isMainHotKeyRegistered = true
    @Published private(set) var isQueueHotKeyRegistered = true
    @Published private(set) var isQuickPasteHotKeyRegistered = true
    
    private var mainHotKeyRef: EventHotKeyRef?
    private var queueHotKeyRef: EventHotKeyRef?
    private var quickPasteHotKeyRef: EventHotKeyRef?
    var onMainHotKey: (() -> Void)?
    var onQueueHotKey: (() -> Void)?
    var onQuickPasteHotKey: (() -> Void)?
    private let hotKeyStore: HotKeyStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "HotKey")

    init(storageDirectory: URL? = nil, hotKeyStore: HotKeyStore? = nil) {
        let resolvedStorageDirectory: URL
        if let storageDirectory {
            resolvedStorageDirectory = storageDirectory
        } else {
            resolvedStorageDirectory = AppStoragePaths.defaultStorageDirectory()
        }
        self.hotKeyStore = hotKeyStore ?? JSONHotKeyStore(storageDirectory: resolvedStorageDirectory)
        loadConfig()
    }
    
    private func loadConfig() {
        do {
            if let config = try hotKeyStore.loadMainHotKey() {
                mainHotKey = config
            }
            if let config = try hotKeyStore.loadQueueHotKey() {
                queueHotKey = config
            }
            if let config = try hotKeyStore.loadQuickPasteHotKey() {
                quickPasteHotKey = config
            }
        } catch {
            logger.error("Failed to load hotkey config: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func registerMainHotKey() -> Bool {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.mainHotKeySignature
        hotKeyID.id = Self.mainHotKeyID
        
        let status = RegisterEventHotKey(mainHotKey.keyCode, mainHotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &mainHotKeyRef)
        let success = (status == noErr) && mainHotKeyRef != nil
        isMainHotKeyRegistered = success
        if !success {
            logger.error("Failed to register main hotkey (status: \(status, privacy: .public), keyCode: \(self.mainHotKey.keyCode), modifiers: \(self.mainHotKey.modifiers))")
        }
        return success
    }
    
    func reregisterMainHotKey() {
        if let ref = mainHotKeyRef {
            UnregisterEventHotKey(ref)
            mainHotKeyRef = nil
        }
        registerMainHotKey()
    }
    
    @discardableResult
    func registerQueueHotKey() -> Bool {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.queueHotKeySignature
        hotKeyID.id = Self.queueHotKeyID
        
        let status = RegisterEventHotKey(queueHotKey.keyCode, queueHotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &queueHotKeyRef)
        let success = (status == noErr) && queueHotKeyRef != nil
        isQueueHotKeyRegistered = success
        if !success {
            logger.error("Failed to register queue hotkey (status: \(status, privacy: .public))")
        }
        return success
    }
    
    func reregisterQueueHotKey() {
        if let ref = queueHotKeyRef {
            UnregisterEventHotKey(ref)
            queueHotKeyRef = nil
        }
        registerQueueHotKey()
    }

    @discardableResult
    func registerQuickPasteHotKey() -> Bool {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.quickPasteHotKeySignature
        hotKeyID.id = Self.quickPasteHotKeyID

        let status = RegisterEventHotKey(quickPasteHotKey.keyCode, quickPasteHotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &quickPasteHotKeyRef)
        let success = (status == noErr) && quickPasteHotKeyRef != nil
        isQuickPasteHotKeyRegistered = success
        if !success {
            logger.error("Failed to register quick-paste hotkey (status: \(status, privacy: .public))")
        }
        return success
    }

    func reregisterQuickPasteHotKey() {
        if let ref = quickPasteHotKeyRef {
            UnregisterEventHotKey(ref)
            quickPasteHotKeyRef = nil
        }
        registerQuickPasteHotKey()
    }
    
    private func saveConfig() {
        do {
            _ = try hotKeyStore.saveMainHotKey(mainHotKey)
            _ = try hotKeyStore.saveQueueHotKey(queueHotKey)
            _ = try hotKeyStore.saveQuickPasteHotKey(quickPasteHotKey)
        } catch {
            logger.error("Failed to save hotkey config: \(error.localizedDescription)")
        }
    }
}

struct HotKeyRecorderView: View {
    @Binding var hotKey: HotKeyConfig
    var label: String = "hotkey.main"
    @State private var isRecording = false
    @ObservedObject var lang = LanguageManager.shared
    
    var body: some View {
        HStack {
            Text(lang.l(label))
            Spacer()
            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? lang.l("hotkey.recording") : hotKey.displayString)
                    .frame(minWidth: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .background(
            HotKeyRecorderHelper(isRecording: $isRecording, hotKey: $hotKey)
        )
    }
}

struct HotKeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotKey: HotKeyConfig

    final class Coordinator {
        var isRecording = false
        var onCommit: ((UInt16, UInt32) -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> NSView {
        let view = HotKeyRecorderNSView()
        let coordinator = context.coordinator
        view.onKeyEvent = { keyCode, modifiers in
            guard coordinator.isRecording else { return }
            coordinator.onCommit?(keyCode, modifiers)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isRecording = isRecording
        coordinator.onCommit = { keyCode, modifiers in
            hotKey = HotKeyConfig(keyCode: UInt32(keyCode), modifiers: modifiers)
            isRecording = false
        }
        if let view = nsView as? HotKeyRecorderNSView {
            view.isRecording = isRecording
        }
    }
}

class HotKeyRecorderNSView: NSView {
    var isRecording = false
    var onKeyEvent: ((UInt16, UInt32) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        
        if modifiers != 0 {
            onKeyEvent?(event.keyCode, modifiers)
        }
    }
}
