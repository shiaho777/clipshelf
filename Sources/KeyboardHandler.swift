import SwiftUI
import AppKit

struct KeyboardShortcutHandler: NSViewRepresentable {
    var onNumberPressed: ((Int) -> Void)? = nil
    var onArrowPressed: ((Int) -> Void)? = nil
    var onEnterPressed: ((Bool) -> Void)? = nil
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowFocusChanged),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
    }

    @objc private func windowFocusChanged() {
        guard let window, window.firstResponder is NSWindow || (window.firstResponder as? NSView)?.acceptsFirstResponder == false else {
            return
        }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if keyCode == 126 { onArrowPressed?(-1); return }
        if keyCode == 125 { onArrowPressed?(1); return }
        if keyCode == 36 || keyCode == 76 {
            onEnterPressed?(flags.contains(.shift))
            return
        }
        if keyCode == 53 { onEscPressed?(); return }
        if keyCode == 48 { onTabPressed?(); return }
        if keyCode == 49 && flags.isEmpty { onSpacePressed?(); return }
        if keyCode == 14 && flags.isEmpty { onEditPressed?(); return }

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
