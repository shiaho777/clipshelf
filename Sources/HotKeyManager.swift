import Foundation
import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    
    static let defaultMain = HotKeyConfig(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧V
    
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
    
    @Published var mainHotKey: HotKeyConfig = .defaultMain {
        didSet { saveConfig(); reregisterMainHotKey() }
    }
    
    private var mainHotKeyRef: EventHotKeyRef?
    var onMainHotKey: (() -> Void)?
    
    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClipboardManager")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("hotkeys.json")
    }
    
    init() {
        loadConfig()
    }
    
    private func loadConfig() {
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            mainHotKey = config
        }
    }
    
    func registerMainHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CBMG".fourCharCodeValue)
        hotKeyID.id = 1
        
        RegisterEventHotKey(mainHotKey.keyCode, mainHotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &mainHotKeyRef)
    }
    
    func reregisterMainHotKey() {
        if let ref = mainHotKeyRef {
            UnregisterEventHotKey(ref)
            mainHotKeyRef = nil
        }
        registerMainHotKey()
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(mainHotKey) {
            try? data.write(to: configURL)
        }
    }
}

struct HotKeyRecorderView: View {
    @Binding var hotKey: HotKeyConfig
    @State private var isRecording = false
    @ObservedObject var lang = LanguageManager.shared
    
    var body: some View {
        HStack {
            Text(lang.l("hotkey.main"))
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
    
    func makeNSView(context: Context) -> NSView {
        let view = HotKeyRecorderNSView()
        view.onKeyEvent = { keyCode, modifiers in
            if isRecording {
                hotKey = HotKeyConfig(keyCode: UInt32(keyCode), modifiers: modifiers)
                isRecording = false
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
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
