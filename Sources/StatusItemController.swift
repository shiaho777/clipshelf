import AppKit

@MainActor
final class StatusItemController {
    private(set) var statusItem: NSStatusItem?
    private var smartPasteBadgeTask: Task<Void, Never>?
    var isShowingSmartPasteBadge = false

    func install(target: AnyObject, action: Selector) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
            button.action = action
            button.target = target
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ClipShelf"
        }
        statusItem = item
    }

    var onOpenPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func popUpMenu() {
        guard let item = statusItem else { return }
        let lang = LanguageManager.shared
        let menu = NSMenu()
        let open = NSMenuItem(
            title: lang.l("status.menu.open"),
            action: #selector(StatusItemController.menuOpen(_:)),
            keyEquivalent: ""
        )
        open.target = self
        let settings = NSMenuItem(
            title: lang.l("settings.title"),
            action: #selector(StatusItemController.menuSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        let quit = NSMenuItem(
            title: lang.l("status.menu.quit"),
            action: #selector(StatusItemController.menuQuit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(open)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.popUpMenu(menu)
    }

    @objc private func menuOpen(_ sender: Any?) { onOpenPanel?() }
    @objc private func menuSettings(_ sender: Any?) { onOpenSettings?() }
    @objc private func menuQuit(_ sender: Any?) { onQuit?() }

    func showSmartPasteBadge(_ adapterName: String) {
        guard let button = statusItem?.button else { return }
        smartPasteBadgeTask?.cancel()
        isShowingSmartPasteBadge = true
        button.image = NSImage(
            systemSymbolName: "arrow.right.doc.on.clipboard",
            accessibilityDescription: LanguageManager.shared.l("settings.smartPaste")
        )
        button.title = " " + adapterName
        smartPasteBadgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            isShowingSmartPasteBadge = false
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
        }
    }
}
