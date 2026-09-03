import SwiftUI
import AppKit

struct KeyboardShortcutHandler: NSViewRepresentable {
    var onNumberPressed: ((Int) -> Void)? = nil
    var onArrowPressed: ((Int) -> Void)? = nil
    var onEnterPressed: ((Bool) -> Void)? = nil  // Bool = asPlainText (Shift held)
    var onEscPressed: (() -> Void)? = nil
    var onTabPressed: (() -> Void)? = nil
    var onSpacePressed: (() -> Void)? = nil
    var onEditPressed: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> KeyboardHandlerView {
        let view = KeyboardHandlerView()
        view.onNumberPressed = onNumberPressed
        view.onArrowPressed = onArrowPressed
        view.onEnterPressed = onEnterPressed
        view.onEscPressed = onEscPressed
        view.onTabPressed = onTabPressed
        view.onSpacePressed = onSpacePressed
        view.onEditPressed = onEditPressed
        return view
    }
    
    func updateNSView(_ nsView: KeyboardHandlerView, context: Context) {
        nsView.onNumberPressed = onNumberPressed
        nsView.onArrowPressed = onArrowPressed
        nsView.onEnterPressed = onEnterPressed
        nsView.onEscPressed = onEscPressed
        nsView.onTabPressed = onTabPressed
        nsView.onSpacePressed = onSpacePressed
        nsView.onEditPressed = onEditPressed
    }
}

class KeyboardHandlerView: NSView {
    var onNumberPressed: ((Int) -> Void)?
    var onArrowPressed: ((Int) -> Void)?
    var onEnterPressed: ((Bool) -> Void)?
    var onEscPressed: (() -> Void)?
    var onTabPressed: (() -> Void)?
    var onSpacePressed: (() -> Void)?
    var onEditPressed: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    /// Observe focus changes so the handler can claim first responder when the
    /// search field loses it. Previously the view only received keyDown after
    /// the user clicked the list background — arrow/space/E navigation was
    /// dead in the default state where the search field held focus.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowFocusChanged),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
    }

    @objc private func windowFocusChanged() {
        guard let window, window.firstResponder is NSWindow || (window.firstResponder as? NSView)?.acceptsFirstResponder == false else {
            // Search field (an NSTextView) is first responder — leave it alone;
            // it forwards unmatched keys via its own keyDown path.
            return
        }
        window.makeFirstResponder(self)
    }

    /// Forward keys we don't handle to the search field when it exists, so
    /// typing always lands in search regardless of first responder.
    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        // ↑ arrow (keyCode 126)
        if keyCode == 126 { onArrowPressed?(-1); return }
        // ↓ arrow (keyCode 125)
        if keyCode == 125 { onArrowPressed?(1); return }
        // Enter / Return (keyCode 36 or 76)
        if keyCode == 36 || keyCode == 76 {
            onEnterPressed?(flags.contains(.shift))
            return
        }
        // Esc (keyCode 53)
        if keyCode == 53 { onEscPressed?(); return }
        // Tab (keyCode 48)
        if keyCode == 48 { onTabPressed?(); return }
        // Space for preview
        if keyCode == 49 && flags.isEmpty { onSpacePressed?(); return }
        // E key for edit (keyCode 14)
        if keyCode == 14 && flags.isEmpty { onEditPressed?(); return }

        // ⌘1-9
        if flags.contains(.command) {
            let keyMap: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
            if let num = keyMap[keyCode] {
                onNumberPressed?(num)
                return
            }
        }

        super.keyDown(with: event)
    }
}
