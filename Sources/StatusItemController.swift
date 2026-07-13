import AppKit

@MainActor
final class StatusItemController {
    private(set) var statusItem: NSStatusItem?
    private var smartPasteBadgeTask: Task<Void, Never>?

    func install(target: AnyObject, action: Selector) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
            button.action = action
            button.target = target
        }
        statusItem = item
    }

    func showSmartPasteBadge(_ adapterName: String) {
        guard let button = statusItem?.button else { return }
        smartPasteBadgeTask?.cancel()
        button.image = NSImage(
            systemSymbolName: "arrow.right.doc.on.clipboard",
            accessibilityDescription: "App-aware Paste"
        )
        button.title = " " + adapterName
        smartPasteBadgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: LanguageManager.shared.l("status.item.normalDescription")
            )
        }
    }
}
