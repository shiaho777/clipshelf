import AppKit
import SwiftUI
import Carbon.HIToolbox
import os
import Combine

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    nonisolated override init() { super.init() }

    private let statusItemController = StatusItemController()
    private var cancellables = Set<AnyCancellable>()
    var panel: FloatingPanel!
    var clipboardManager: ClipboardManager!
    let hotKeyManager = HotKeyManager.shared
    var pasteQueue: PasteQueue!
    var snippetManager: SnippetManager!
    var snippetExpansionMonitor: SnippetExpansionMonitor?
    var previousApp: NSRunningApplication?
#if canImport(Sparkle)
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
#endif
    private var clickMonitor: Any?
    private var pasteObserver: NSObjectProtocol?
    private var didPaste = false
    private var pasteGeneration: UInt64 = 0
    private var isPanelAnimating = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "App")
    private var queueObserver: Any?

    private let minPanelSize = NSSize(width: 300, height: 400)
    private let maxPanelSize = NSSize(width: 600, height: 800)
    private let defaultPanelSize = NSSize(width: WindowLayout.mainPanelSize.width, height: WindowLayout.mainPanelSize.height)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.nicebro.ClipShelf"
            let currentApp = NSRunningApplication.current
            let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0 != currentApp }
            if let existing = otherInstances.first {
                existing.activate(options: .activateIgnoringOtherApps)
                NSApp.terminate(nil)
                return
            }
        }

        clipboardManager = ClipboardManager()
        restoreLaunchAtLoginIfNeeded()
        pasteQueue = PasteQueue.shared
        snippetManager = SnippetManager()
        checkAccessibilityPermission()
        
        statusItemController.install(target: self, action: #selector(togglePanel))
        statusItemController.onOpenPanel = { [weak self] in self?.showPanel() }
        statusItemController.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItemController.onQuit = { NSApplication.shared.terminate(nil) }
        
        clipboardManager.onItemSelected = { [weak self] in self?.pasteAndClose() }
        
        let savedSize = loadPanelSize()
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: savedSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isEnabled = true
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.delegate = self
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.minSize = minPanelSize
        panel.maxSize = maxPanelSize
        if let contentView = panel.contentView {
            let vibrantView = NSVisualEffectView(frame: contentView.bounds)
            vibrantView.material = .hudWindow
            vibrantView.blendingMode = .behindWindow
            vibrantView.state = .active
            vibrantView.autoresizingMask = [.width, .height]
            let hostingView = NSHostingController(
                rootView: MenuBarView(
                    clipboardManager: clipboardManager,
                    snippetManager: snippetManager,
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onOpenRulesTest: { [weak self] in self?.openSettings(tab: 1) }
                )
                .environmentObject(FrontmostAppInfo.shared)
            ).view
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.layer?.backgroundColor = .clear
            contentView.addSubview(vibrantView)
            contentView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
        } else {
            panel.contentViewController = NSHostingController(
                rootView: MenuBarView(
                    clipboardManager: clipboardManager,
                    snippetManager: snippetManager,
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onOpenRulesTest: { [weak self] in self?.openSettings(tab: 1) }
                )
                .environmentObject(FrontmostAppInfo.shared)
            )
        }
        
        hotKeyManager.onMainHotKey = { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.onQueueHotKey = { [weak self] in
            self?.pasteNextFromQueue()
        }
        hotKeyManager.onQuickPasteHotKey = { [weak self] in
            self?.toggleQuickPaste()
        }
        
        registerGlobalHotKey()

        if UserDefaults.standard.object(forKey: "snippetExpansionEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "snippetExpansionEnabled")
        }
        if UserDefaults.standard.bool(forKey: "snippetExpansionEnabled") {
            snippetExpansionMonitor = SnippetExpansionMonitor(snippetManager: snippetManager)
            snippetExpansionMonitor?.start()
        }

        queueObserver = NotificationCenter.default.addObserver(
            forName: .init("PasteQueueChanged"), object: nil, queue: .main
        ) { [weak self] _ in self?.updateStatusBarBadge() }
        pasteQueue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusBarBadge() }
        }.store(in: &cancellables)

        clipboardManager.$lastSmartPasteDescription
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] adapterName in
                self?.showSmartPasteBadge(adapterName)
            }
            .store(in: &cancellables)
    }
    
    func openSettings(tab: Int = 0) {
        if tab > 0 {
            UserDefaults.standard.set(tab, forKey: "_settingsRequestedTab")
        }
        showPanel()
    }

    func registerGlobalHotKey() {
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if hotKeyID.signature == HotKeyManager.mainHotKeySignature {
                DispatchQueue.main.async {
                    appDelegate.hotKeyManager.onMainHotKey?()
                }
            } else if hotKeyID.signature == HotKeyManager.queueHotKeySignature {
                DispatchQueue.main.async {
                    appDelegate.hotKeyManager.onQueueHotKey?()
                }
            } else if hotKeyID.signature == HotKeyManager.quickPasteHotKeySignature {
                DispatchQueue.main.async {
                    appDelegate.hotKeyManager.onQuickPasteHotKey?()
                }
            }
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, nil)
        if installStatus != noErr {
            logger.error("Failed to install global hotkey event handler: \(installStatus, privacy: .public)")
        }
        hotKeyManager.reregisterMainHotKey()
        hotKeyManager.reregisterQueueHotKey()
        hotKeyManager.reregisterQuickPasteHotKey()
    }
    
    @objc func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if panel.isVisible { hidePanel() }
            statusItemController.popUpMenu()
            return
        }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        hidePanel()
        return false
    }

    private func showPanel() {
        guard let button = statusItemController.statusItem?.button, !isPanelAnimating else { return }
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication

        FrontmostAppInfo.shared.bundleID = previousApp?.bundleIdentifier
        FrontmostAppInfo.shared.appName = previousApp?.localizedName

        clipboardManager.forceRefreshClipboard()
        clipboardManager.cleanupOldItems()

        let buttonRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        let panelSize = panel.frame.size
        let x = buttonRect.midX - panelSize.width / 2
        let y = buttonRect.minY - panelSize.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let originalFrame = panel.frame
        let shrunkFrame = NSRect(
            x: originalFrame.midX - originalFrame.width * 0.48,
            y: originalFrame.maxY - originalFrame.height * 0.96,
            width: originalFrame.width * 0.96,
            height: originalFrame.height * 0.96
        )
        panel.setFrame(shrunkFrame, display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            guard let self, self.panel.isVisible else { return }
            if event.type == .leftMouseUp || event.type == .rightMouseUp {
                if ClipboardDragSession.isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if NSEvent.pressedMouseButtons == 0 {
                            ClipboardDragSession.end()
                        }
                    }
                }
                return
            }
            if ClipboardDragSession.isAlive || NSEvent.pressedMouseButtons != 0 { return }
            if !NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) {
                self.hidePanel()
            }
        }
    }

    private func hidePanel() {
        guard !isPanelAnimating else { return }
        isPanelAnimating = true
        savePanelSize(panel.frame.size)
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        let originalFrame = panel.frame
        let shrunkFrame = NSRect(
            x: originalFrame.midX - originalFrame.width * 0.48,
            y: originalFrame.maxY - originalFrame.height * 0.94,
            width: originalFrame.width * 0.96,
            height: originalFrame.height * 0.94
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(shrunkFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.setFrame(originalFrame, display: false)
            self.panel.alphaValue = 1
            self.isPanelAnimating = false
        })
    }
    
    func pasteAndClose() {
        hidePanel()
        guard let targetApp = previousApp else { return }
        clipboardManager.targetBundleID = targetApp.bundleIdentifier

        cleanupPasteObserver()
        pasteGeneration &+= 1
        let generation = pasteGeneration
        didPaste = false

        pasteObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, !self.didPaste, self.pasteGeneration == generation,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == targetApp.processIdentifier else { return }
            self.didPaste = true
            self.cleanupPasteObserver()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.pasteGeneration == generation else { return }
                self.simulateCmdV()
            }
        }

        targetApp.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didPaste, self.pasteGeneration == generation else { return }
            self.didPaste = true
            self.cleanupPasteObserver()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
                self.logger.warning("Paste target failed to activate; skipping fallback Cmd+V")
                return
            }
            self.simulateCmdV()
        }
    }
    
    private func cleanupPasteObserver() {
        if let obs = pasteObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            pasteObserver = nil
        }
    }
    
    func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
    
    func pasteNextFromQueue() {
        guard let item = pasteQueue.dequeueNext() else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        clipboardManager.targetBundleID = previousApp?.bundleIdentifier
        guard clipboardManager.copyToClipboard(item) else {
            updateStatusBarBadge()
            return
        }
        guard let targetApp = previousApp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulateCmdV()
        }
    }

    func toggleQuickPaste() {
        if QuickPastePanel.shared.isVisible {
            QuickPastePanel.shared.hide()
        } else {
            if panel.isVisible { hidePanel() }
            previousApp = NSWorkspace.shared.frontmostApplication
            clipboardManager.targetBundleID = previousApp?.bundleIdentifier
            QuickPastePanel.shared.show(clipboardManager: clipboardManager)
        }
    }
    
    private func updateStatusBarBadge() {
        guard let button = statusItemController.statusItem?.button else { return }
        guard !statusItemController.isShowingSmartPasteBadge else { return }
        if pasteQueue.stackMode {
            button.image = NSImage(
                systemSymbolName: "square.stack.3d.up.fill",
                accessibilityDescription: LanguageManager.shared.l("queue.stackMode")
            )
            button.title = pasteQueue.remaining > 0 ? "\(pasteQueue.remaining)" : ""
        } else if pasteQueue.isActive {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard.fill",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
            button.title = "\(pasteQueue.remaining)"
        } else {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
            button.title = ""
        }
    }

    @MainActor
    private func showSmartPasteBadge(_ adapterName: String) {
        guard !pasteQueue.isActive else { return }
        statusItemController.showSmartPasteBadge(adapterName)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.clipboardManager.lastSmartPasteDescription = nil
            self.updateStatusBarBadge()
        }
    }
    
    func checkAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "clipshelf" else { continue }
            handleURL(url)
        }
    }
    
    private func handleURL(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "search":
            showPanel()
        case "clear-sensitive":
            clipboardManager.clearSensitiveItems()
        case "open":
            showPanel()
        default:
            break
        }
    }
    

    func applicationWillTerminate(_ notification: Notification) {
        if let panel, panel.isVisible { savePanelSize(panel.frame.size) }
        clipboardManager?.prepareForTermination()
    }

    private func restoreLaunchAtLoginIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf", category: "App")
            let service = LaunchAtLoginServiceFactory.defaultService()
            guard !service.isEnabled else { return }
            let prefsStore = JSONAppPreferencesStore(storageDirectory: AppStoragePaths.defaultStorageDirectory())
            guard (try? prefsStore.loadLaunchAtLogin()) == true else { return }
            do {
                try service.setEnabled(true)
            } catch {
                logger.error("Failed to restore launch-at-login: \(error.localizedDescription)")
            }
        }
    }

    private func loadPanelSize() -> NSSize {
        let w = UserDefaults.standard.double(forKey: "panelWidth")
        let h = UserDefaults.standard.double(forKey: "panelHeight")
        guard w >= minPanelSize.width, h >= minPanelSize.height else { return defaultPanelSize }
        return NSSize(
            width: min(w, maxPanelSize.width),
            height: min(h, maxPanelSize.height)
        )
    }

    private func savePanelSize(_ size: NSSize) {
        UserDefaults.standard.set(size.width, forKey: "panelWidth")
        UserDefaults.standard.set(size.height, forKey: "panelHeight")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
