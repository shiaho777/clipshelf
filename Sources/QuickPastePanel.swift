import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A compact, cursor-anchored panel for quick pasting.
///
/// Shows the most recent clipboard items as a small list near the text cursor.
/// Press 1-9 to paste, Esc to dismiss. Designed for zero-context-switch pasting
/// — the panel appears where you're already typing.
@MainActor
class QuickPastePanel: ObservableObject {
    static let shared = QuickPastePanel()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<QuickPasteView>?
    private(set) var isVisible = false
    private weak var clipboardManager: ClipboardManager?
    private var clickMonitor: Any?
    /// The app that was frontmost when the panel was shown.
    /// We re-activate it after paste/dismiss so the user can continue typing.
    private var targetApp: NSRunningApplication?

    private init() {}

    /// Shows the panel at the given screen location (or near the text cursor
    /// if Accessibility permissions allow).
    func show(clipboardManager: ClipboardManager, at cursorLocation: NSPoint? = nil) {
        let location = cursorLocation ?? CursorLocator.shared.cursorLocation() ?? defaultLocation()
        self.clipboardManager = clipboardManager
        // Save the current frontmost app so we can re-activate it after paste/dismiss.
        // Note: at this point ClipboardManager is NOT yet frontmost (we haven't made
        // the panel key yet), so this correctly captures the user's target app.
        self.targetApp = NSWorkspace.shared.frontmostApplication

        clipboardManager.forceRefreshClipboard()

        let view = QuickPasteView(clipboardManager: clipboardManager) { [weak self] in
            self?.hide()
        } onPaste: { [weak self] item in
            self?.pasteAndClose(item: item)
        }
        let controller = NSHostingController(rootView: view)
        hostingController = controller

        let panelSize = NSSize(width: 320, height: 240)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Vibrancy background matching the main panel.
        let vibrantView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        vibrantView.material = .hudWindow
        vibrantView.blendingMode = .behindWindow
        vibrantView.state = .active
        vibrantView.autoresizingMask = [.width, .height]
        let hostingView = controller.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = vibrantView
        vibrantView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: vibrantView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: vibrantView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: vibrantView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: vibrantView.trailingAnchor)
        ])

        panel.minSize = NSSize(width: 240, height: 160)
        panel.maxSize = NSSize(width: 400, height: 400)
        self.panel = panel

        // Position the panel near the cursor, keeping it on-screen.
        let positioned = clampToScreen(location: location, panelSize: panelSize)
        panel.setFrameOrigin(positioned)

        // Entrance animation: fade + scale up.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let originalFrame = panel.frame
        let shrunkFrame = NSRect(
            x: originalFrame.midX - originalFrame.width * 0.48,
            y: originalFrame.midY - originalFrame.height * 0.46,
            width: originalFrame.width * 0.96,
            height: originalFrame.height * 0.96
        )
        panel.setFrame(shrunkFrame, display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }

        isVisible = true

        // Dismiss when clicking elsewhere.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        guard isVisible else { return }
        let originalFrame = panel?.frame ?? .zero
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.setFrame(originalFrame, display: false)
            self?.panel?.alphaValue = 1
            self?.panel = nil
            self?.hostingController = nil
            self?.isVisible = false
        })
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        // Reactivate the user's target app so they can continue typing.
        // Use the saved targetApp (NOT frontmostApplication, which is ourselves).
        if let app = targetApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                app.activate(options: .activateIgnoringOtherApps)
                self?.targetApp = nil
            }
        }
    }

    /// Copy item to clipboard, hide panel, reactivate target app, then simulate Cmd+V.
    private func pasteAndClose(item: ClipboardItem) {
        guard let cm = clipboardManager else { return }
        cm.copyToClipboard(item)
        let app = targetApp
        // Hide the panel first (triggers exit animation).
        hide()
        // After the panel is dismissed and the target app is re-activated,
        // simulate Cmd+V. The timing must account for:
        // 1. Panel exit animation (0.1s in hide)
        // 2. Target app activation delay
        // 3. monitor.acknowledgeChangeCount (called by copyToClipboard)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            app?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.simulateCmdV()
            }
        }
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func defaultLocation() -> NSPoint {
        let screen = NSScreen.main?.frame ?? .zero
        return NSPoint(x: screen.midX - 160, y: screen.midY - 120)
    }

    private func clampToScreen(location: NSPoint, panelSize: NSSize) -> NSPoint {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        var x = location.x + 8
        var y = location.y - panelSize.height - 4
        // Clamp right
        if x + panelSize.width > screenFrame.maxX { x = screenFrame.maxX - panelSize.width }
        // Clamp left
        if x < screenFrame.minX { x = screenFrame.minX }
        // Clamp bottom
        if y < screenFrame.minY { y = location.y + 20 }
        // Clamp top
        if y + panelSize.height > screenFrame.maxY { y = screenFrame.maxY - panelSize.height }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Cursor Locator

/// Attempts to locate the text cursor position using the Accessibility API.
/// Falls back to the mouse location when the cursor isn't available.
final class CursorLocator {
    static let shared = CursorLocator()

    /// Returns the current text insertion point in screen coordinates, or the
    /// mouse location as a fallback.
    func cursorLocation() -> NSPoint? {
        // Try the focused UI element's caret position via AX API.
        if let caret = axCaretLocation() { return caret }
        // Fallback: mouse location (works without AX, less precise).
        return NSEvent.mouseLocation
    }

    private func axCaretLocation() -> NSPoint? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let elementRef = focusedElement else { return nil }
        let element = elementRef as! AXUIElement

        // Try to get the bounds of the selected text range.
        // The caret is at the end of the selection; we use kAXBoundsForRange
        // to get its screen position.
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeVal = rangeValue else { return nil }

        let axValue = rangeVal as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }

        var boundsRef: CFTypeRef?
        let rangeParam = AXValueCreate(.cfRange, &range)
        guard let rangeParam,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeParam, &boundsRef) == .success,
              let bounds = boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        // The caret is at the left edge of the selection bounds.
        return NSPoint(x: rect.minX, y: rect.maxY)
    }
}

// MARK: - Quick Paste View

struct QuickPasteView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    let onDismiss: () -> Void
    let onPaste: (ClipboardItem) -> Void
    @State private var hoveredIndex: Int?
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    private let maxItems = 9

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchField(
                text: $searchText,
                placeholder: LanguageManager.shared.l("search.placeholder"),
                size: .compact,
                focus: $isFocused
            )

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        quickRow(index: index, item: item)
                    }
                    if displayItems.isEmpty {
                        Text(LanguageManager.shared.l("search.noResults"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 30)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
        }
        .frame(minWidth: 300)
        .background(KeyboardShortcutHandler(
            onNumberPressed: { num in selectAndPaste(at: num) },
            onArrowPressed: { dir in moveHover(dir) },
            onEnterPressed: { _ in
                if let idx = hoveredIndex, idx < displayItems.count {
                    onPaste(displayItems[idx])
                }
            },
            onEscPressed: {
                if !searchText.isEmpty {
                    searchText = ""
                } else {
                    onDismiss()
                }
            }
        ))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                isFocused = true
            }
        }
        .onChange(of: searchText) { _ in
            hoveredIndex = nil
        }
    }

    /// Returns up to 9 items, filtered by search text if non-empty.
    private var displayItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(clipboardManager.items.prefix(maxItems))
        }
        // Use fuzzy search for matching.
        return clipboardManager.search(query, limit: maxItems)
    }

    @ViewBuilder
    private func quickRow(index: Int, item: ClipboardItem) -> some View {
        let isHovered = hoveredIndex == index
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.quaternary)
                .frame(width: 16)

            if item.type == .image {
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(item.ocrText ?? LanguageManager.shared.l("item.image"))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else if item.type == .fileURL {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.75))
                Text(item.filePaths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? item.content)
                    .font(.system(size: 12))
                    .lineLimit(1)
            } else {
                Text(item.displayText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.88))
            }

            Spacer(minLength: 4)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.orange.opacity(0.75))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
        }
        .onTapGesture {
            onPaste(item)
        }
        .contextMenu {
            Button(LanguageManager.shared.l("action.copy")) {
                clipboardManager.copyToClipboard(item)
            }
        }
    }

    private func moveHover(_ direction: Int) {
        let count = displayItems.count
        guard count > 0 else { return }
        let newIndex: Int
        if let current = hoveredIndex {
            newIndex = max(0, min(count - 1, current + direction))
        } else {
            newIndex = direction > 0 ? 0 : count - 1
        }
        hoveredIndex = newIndex
    }

    private func selectAndPaste(at num: Int) {
        guard num > 0 && num <= displayItems.count else { return }
        onPaste(displayItems[num - 1])
    }
}
