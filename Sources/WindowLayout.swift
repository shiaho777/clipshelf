import SwiftUI
import AppKit

enum WindowLayout {
    static let mainPanelSize = CGSize(width: 340, height: 480)
    static let popupSize = mainPanelSize
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

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
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
                let origin = NSPoint(
                    x: frame.minX + 28,
                    y: frame.maxY - size.height - 28
                )
                panel.setFrameOrigin(origin)
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
                let origin = NSPoint(
                    x: frame.minX + 28,
                    y: frame.maxY - size.height - 28
                )
                panel.setFrameOrigin(origin)
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

// MARK: - Design System
//
// A single source of truth for the spacing, sizing, typography, and colour
// values used across the app's panels and sheets. Before this existed, each
// sheet re-declared its own paddings and font sizes, which drifted apart over
// time (headers ranged from 10–14pt vertical padding, close buttons from 16–18pt,
// search fields used four different fonts). Route new UI through these tokens so
// the app stays visually consistent.

enum DesignSystem {
    /// Corner radii used throughout the app.
    enum Radius {
        static let badge: CGFloat = 3        // small tag pills
        static let control: CGFloat = 6      // small buttons, chips
        static let card: CGFloat = 8         // list rows, cards
        static let editor: CGFloat = 10      // text editors, larger surfaces
    }

    /// Standard spacing increments (4pt grid).
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
    }

    /// Font sizes. Named by role rather than raw number so intent is clear.
    enum FontSize {
        static let sheetTitle: CGFloat = 14  // sheet/panel header titles
        static let body: CGFloat = 13        // primary body text, list titles
        static let secondary: CGFloat = 12   // secondary text, buttons
        static let caption: CGFloat = 11     // captions, counts, metadata
        static let footnote: CGFloat = 10    // timestamps, badges, hints
    }

    /// Sheet header layout constants (shared by every SheetHeader).
    enum Header {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 14
        static let closeIconSize: CGFloat = 16
        static let actionIconSize: CGFloat = 16
    }

    /// Sheet footer layout constants (shared by every SheetFooter).
    enum Footer {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 12
    }
}

// MARK: - Shared UI Components

/// A consistent header bar for popup sheets: a leading title, optional trailing
/// action buttons, and a trailing close button. Every sheet in the app should
/// use this instead of hand-rolling its own HStack + close button so titles,
/// paddings, and the close affordance stay identical everywhere.
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

/// A circular icon button styled to match the header close button — used for
/// secondary header actions such as "add" (`plus.circle.fill`).
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

/// A consistent footer bar for popup sheets. Wraps content in a leading divider
/// and the standard horizontal/vertical padding so action bars line up across
/// every sheet.
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

/// A unified inline search field. Consolidates the four slightly different
/// search bars that existed across the app (main panel, quick paste, snippets,
/// app picker) into one component with a couple of size variants.
struct SearchField: View {
    enum Size {
        case regular   // main panel
        case compact   // popovers, quick paste

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
    var placeholder: String = LanguageManager.shared.l("search.placeholder")
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
                    TextField(placeholder, text: $text)
                        .focused(focus)
                } else {
                    TextField(placeholder, text: $text)
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

// MARK: - Tag Badge

/// A small colored pill used to tag list items — "R" for rich text, "Screenshot"
/// for screenshots, "+N" for extra file counts, etc. Before this existed, the same
/// styling (h4/v1.5 padding, radius-3 corners, 10% tint background, 75% tint
/// foreground) was copy-pasted in five places in ClipboardItemRow with subtly
/// different font sizes. Use this so every badge looks identical.
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

// MARK: - Empty State

/// A centered empty/placeholder state: a large light icon, a message, and an
/// optional action button. Consolidates the near-identical empty views that the
/// main history list and the snippets list each hand-rolled.
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
