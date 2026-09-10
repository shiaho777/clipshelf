import SwiftUI
import AppKit

enum WindowLayout {
    static let mainPanelSize = CGSize(width: 340, height: 480)
    static let popupSize = CGSize(width: 360, height: 440)
    static let previewSize = CGSize(width: 400, height: 380)
    static let editorSize = CGSize(width: 380, height: 400)
}

enum PopupPlacement {
    static func origin(parentFrame: CGRect, size: CGSize) -> NSPoint {
        if let screen = NSScreen.main?.visibleFrame {
            let leftX = parentFrame.minX - size.width - 12
            if leftX >= screen.minX {
                return NSPoint(x: leftX, y: parentFrame.maxY - size.height)
            }
            let rightX = parentFrame.maxX + 12
            if rightX + size.width <= screen.maxX {
                return NSPoint(x: rightX, y: parentFrame.maxY - size.height)
            }
        }
        return NSPoint(
            x: parentFrame.minX + 28,
            y: parentFrame.maxY - size.height - 28
        )
    }
}

private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PopupWindowDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var popupWindowDismiss: () -> Void {
        get { self[PopupWindowDismissKey.self] }
        set { self[PopupWindowDismissKey.self] = newValue }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    final class Coordinator {
        var didConfigure = false
        var pendingWorkItem: DispatchWorkItem?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfigure(view: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfigure(view: nsView, context: context)
    }

    private func scheduleConfigure(view: NSView, context: Context) {
        guard !context.coordinator.didConfigure else { return }
        context.coordinator.pendingWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard !context.coordinator.didConfigure, let window = view.window else { return }
            configure(window)
            context.coordinator.didConfigure = true
        }
        context.coordinator.pendingWorkItem = work
        DispatchQueue.main.async(execute: work)
    }
}

private struct BoolPopupWindowPresenter<PopupContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let size: CGSize
    let content: () -> PopupContent

    final class Coordinator: NSObject, NSWindowDelegate {
        var isPresented: Binding<Bool>
        let size: CGSize
        let content: () -> PopupContent
        weak var anchorView: NSView?
        var window: PopupPanel?
        var isClosingProgrammatically = false

        init(isPresented: Binding<Bool>, size: CGSize, content: @escaping () -> PopupContent) {
            self.isPresented = isPresented
            self.size = size
            self.content = content
        }

        func updateWindow() {
            guard isPresented.wrappedValue else {
                closeWindow()
                return
            }

            let rootView = AnyView(
                content()
                    .environment(\.popupWindowDismiss) { [weak self] in
                        self?.closeWindow()
                    }
            )

            if let window {
                (window.contentViewController as? NSHostingController<AnyView>)?.rootView = rootView
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                return
            }

            let panel = PopupPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: size.width, height: size.height)
            panel.maxSize = NSSize(width: size.width, height: size.height)
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.backgroundColor = .windowBackgroundColor
            panel.isOpaque = true
            panel.contentViewController = NSHostingController(rootView: rootView)

            if let parentWindow = anchorView?.window {
                let frame = parentWindow.frame
                panel.setFrameOrigin(PopupPlacement.origin(parentFrame: frame, size: size))
                panel.level = parentWindow.level.rawValue >= NSWindow.Level.floating.rawValue
                    ? parentWindow.level + 1
                    : .floating
            } else {
                panel.center()
                panel.level = .floating
            }

            window = panel
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func closeWindow() {
            guard let window else { return }
            isClosingProgrammatically = true
            window.close()
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            let shouldResetBinding = isPresented.wrappedValue
            let programmatic = isClosingProgrammatically
            isClosingProgrammatically = false
            if shouldResetBinding {
                DispatchQueue.main.async {
                    self.isPresented.wrappedValue = false
                }
            } else if programmatic {
                DispatchQueue.main.async {
                    self.isPresented.wrappedValue = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, size: size, content: content)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.isPresented = $isPresented
        context.coordinator.updateWindow()
    }
}

private struct ItemPopupWindowPresenter<Item: Identifiable, PopupContent: View>: NSViewRepresentable {
    @Binding var item: Item?
    let size: CGSize
    let content: (Item) -> PopupContent

    final class Coordinator: NSObject, NSWindowDelegate {
        var item: Binding<Item?>
        let size: CGSize
        let content: (Item) -> PopupContent
        weak var anchorView: NSView?
        var window: PopupPanel?
        var presentedItemID: Item.ID?

        init(item: Binding<Item?>, size: CGSize, content: @escaping (Item) -> PopupContent) {
            self.item = item
            self.size = size
            self.content = content
        }

        func updateWindow() {
            guard let itemValue = item.wrappedValue else {
                closeWindow()
                return
            }

            let rootView = AnyView(
                content(itemValue)
                    .environment(\.popupWindowDismiss) { [weak self] in
                        self?.closeWindow()
                    }
            )

            if let window {
                presentedItemID = itemValue.id
                (window.contentViewController as? NSHostingController<AnyView>)?.rootView = rootView
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                return
            }

            let panel = PopupPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: size.width, height: size.height)
            panel.maxSize = NSSize(width: size.width, height: size.height)
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.backgroundColor = .windowBackgroundColor
            panel.isOpaque = true
            panel.contentViewController = NSHostingController(rootView: rootView)

            if let parentWindow = anchorView?.window {
                let frame = parentWindow.frame
                panel.setFrameOrigin(PopupPlacement.origin(parentFrame: frame, size: size))
                panel.level = parentWindow.level.rawValue >= NSWindow.Level.floating.rawValue
                    ? parentWindow.level + 1
                    : .floating
            } else {
                panel.center()
                panel.level = .floating
            }

            presentedItemID = itemValue.id
            window = panel
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func closeWindow() {
            window?.close()
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            presentedItemID = nil
            if item.wrappedValue != nil {
                DispatchQueue.main.async {
                    self.item.wrappedValue = nil
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(item: $item, size: size, content: content)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.item = $item
        context.coordinator.updateWindow()
    }
}

extension View {
    func standardPopupLayout(size: CGSize = WindowLayout.popupSize) -> some View {
        self
            .frame(width: size.width, height: size.height)
            .background(
                WindowConfigurator { window in
                    window.isMovableByWindowBackground = true
                    window.minSize = NSSize(width: size.width, height: size.height)
                    window.maxSize = NSSize(width: size.width, height: size.height)
                }
            )
    }

    func popupWindow<PopupContent: View>(
        isPresented: Binding<Bool>,
        size: CGSize = WindowLayout.popupSize,
        @ViewBuilder content: @escaping () -> PopupContent
    ) -> some View {
        background(BoolPopupWindowPresenter(isPresented: isPresented, size: size, content: content))
    }

    func popupWindow<Item: Identifiable, PopupContent: View>(
        item: Binding<Item?>,
        size: CGSize = WindowLayout.popupSize,
        @ViewBuilder content: @escaping (Item) -> PopupContent
    ) -> some View {
        background(ItemPopupWindowPresenter(item: item, size: size, content: content))
    }

    func standardEditorSurface(cornerRadius: CGFloat = DesignSystem.Radius.editor) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
    }
}

enum DesignSystem {
    enum Radius {
        static let badge: CGFloat = 3
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let editor: CGFloat = 10
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
    }

    enum FontSize {
        static let sheetTitle: CGFloat = 14
        static let body: CGFloat = 13
        static let secondary: CGFloat = 12
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 10
    }

    enum Header {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 14
        static let closeIconSize: CGFloat = 16
        static let actionIconSize: CGFloat = 16
    }

    enum Footer {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 12
    }
}

struct SheetHeader<Trailing: View>: View {
    let title: String
    var onClose: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        onClose: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.onClose = onClose
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text(title)
                    .font(.system(size: DesignSystem.FontSize.sheetTitle, weight: .semibold))
                Spacer()
                trailing()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DesignSystem.Header.closeIconSize))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(LanguageManager.shared.l("button.cancel"))
                    .accessibilityLabel(LanguageManager.shared.l("button.cancel"))
                }
            }
            .padding(.horizontal, DesignSystem.Header.horizontalPadding)
            .padding(.vertical, DesignSystem.Header.verticalPadding)

            Divider().opacity(0.3)
        }
    }
}

struct SheetHeaderIconButton: View {
    let icon: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DesignSystem.Header.actionIconSize))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .accessibilityLabel(help ?? "")
    }
}

struct SheetFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: DesignSystem.Spacing.lg) {
                content()
            }
            .padding(.horizontal, DesignSystem.Footer.horizontalPadding)
            .padding(.vertical, DesignSystem.Footer.verticalPadding)
        }
    }
}

struct SearchField: View {
    enum Size {
        case regular
        case compact

        var iconSize: CGFloat {
            switch self {
            case .regular: return 14
            case .compact: return 12
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .regular: return 14
            case .compact: return 13
            }
        }
        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return DesignSystem.Spacing.xl
            case .compact: return DesignSystem.Spacing.lg
            }
        }
        var verticalPadding: CGFloat {
            switch self {
            case .regular: return 11
            case .compact: return DesignSystem.Spacing.md
            }
        }
    }

    @Binding var text: String
    @ObservedObject private var lang = LanguageManager.shared
    var placeholder: String? = nil
    var size: Size = .regular
    var reduceMotion: Bool = false
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: size.iconSize, weight: .medium))
                .foregroundStyle(.tertiary)
            Group {
                if let focus {
                    TextField(placeholder ?? lang.l("search.placeholder"), text: $text)
                        .focused(focus)
                } else {
                    TextField(placeholder ?? lang.l("search.placeholder"), text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: size.fontSize))
            if !text.isEmpty {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: size.iconSize))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
    }
}

struct TagBadge: View {
    let text: String
    var systemImage: String?
    var color: Color = .blue
    var fontSize: CGFloat = 8

    init(_ text: String, systemImage: String? = nil, color: Color = .blue, fontSize: CGFloat = 8) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize))
            }
            Text(text)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, 1.5)
        .background(color.opacity(0.1))
        .foregroundColor(color.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.badge))
    }
}

struct EmptyStateView: View {
    let icon: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl - 2) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.system(size: DesignSystem.FontSize.body, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: DesignSystem.FontSize.secondary, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
