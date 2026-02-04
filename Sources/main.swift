import AppKit
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let clipboardManager = ClipboardManager()
    let snippetManager = SnippetManager.shared
    var hotKeyRef: EventHotKeyRef?
    var previousApp: NSRunningApplication?
    var settingsWindow: NSWindow?
    var snippetsWindow: NSWindow?
    
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
        registerSnippetHotKeys()
    }
    
    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(clipboardManager: clipboardManager, onOpenSnippets: { [weak self] in
                self?.openSnippets()
            }))
            settingsWindow?.center()
        }
        settingsWindow?.title = LanguageManager.shared.l("settings.title")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openSnippets() {
        if snippetsWindow == nil {
            snippetsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            snippetsWindow?.contentViewController = NSHostingController(rootView: SnippetListView())
            snippetsWindow?.center()
        }
        snippetsWindow?.title = LanguageManager.shared.l("snippets.title")
        snippetsWindow?.makeKeyAndOrderFront(nil)
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
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            let sig = hotKeyID.signature
            let id = hotKeyID.id
            
            DispatchQueue.main.async {
                if sig == OSType("CBMG".fourCharCodeValue) {
                    appDelegate.togglePopover()
                } else if sig == OSType("SNIP".fourCharCodeValue) {
                    appDelegate.snippetManager.pasteSnippet(index: Int(id))
                }
            }
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, nil)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func registerSnippetHotKeys() {
        snippetManager.registerHotKeys()
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


let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
