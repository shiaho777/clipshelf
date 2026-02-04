import AppKit
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let clipboardManager = ClipboardManager()
    var hotKeyRef: EventHotKeyRef?
    var previousApp: NSRunningApplication?
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        clipboardManager.onItemSelected = { [weak self] in self?.pasteAndClose() }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(clipboardManager: clipboardManager, onOpenSettings: { [weak self] in
                self?.openSettings()
            })
        )
        
        registerGlobalHotKey()
    }
    
    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(clipboardManager: clipboardManager))
            settingsWindow?.center()
        }
        settingsWindow?.title = LanguageManager.shared.l("settings.title")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func registerGlobalHotKey() {
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 9
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CBMG".fourCharCodeValue)
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { appDelegate.togglePopover() }
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, nil)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func pasteAndClose() {
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.previousApp?.activate(options: .activateIgnoringOtherApps)
        }
    }
}

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf8.prefix(4) { result = (result << 8) + FourCharCode(char) }
        return result
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
