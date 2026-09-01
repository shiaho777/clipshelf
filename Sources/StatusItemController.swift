import AppKit

@MainActor
final class StatusItemController {
    private(set) var statusItem: NSStatusItem?
    private var smartPasteBadgeTask: Task<Void, Never>?
    /// Set while the transient smart-paste badge is showing, so the queue-badge
    /// updater doesn't fight the reset timer (they raced: smart-paste fired
    /// during stack mode and its reset wiped the queue icon+count).
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
        }
        statusItem = item
    }

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
