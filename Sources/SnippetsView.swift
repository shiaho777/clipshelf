import SwiftUI
import AppKit

struct SnippetsView: View {
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject var lang = LanguageManager.shared
    @Environment(\.popupWindowDismiss) private var dismissPopup
    @State private var searchText = ""
    @State private var editingSnippet: Snippet?
    @State private var isAdding = false
    var onPaste: ((String) -> Void)?

    private var filtered: [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snippetManager.snippets }
        return snippetManager.snippets.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query) ||
            $0.category.lowercased().contains(query) ||
            ($0.shortcut?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (add button before the close button)
            SheetHeader(lang.l("snippets.title"), onClose: { dismissPopup() }) {
                SheetHeaderIconButton(icon: "plus.circle.fill", help: lang.l("snippets.add")) {
                    isAdding = true
                }
            }

            // Search
            SearchField(
                text: $searchText,
                placeholder: lang.l("search.placeholder"),
                size: .compact
            )

            Divider().opacity(0.3)

            // List
            if filtered.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: searchText.isEmpty ? "text.quote" : "magnifyingglass",
                    message: snippetManager.snippets.isEmpty ? lang.l("snippets.empty") : lang.l("search.noResults")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { snippet in
                            SnippetRow(snippet: snippet, lang: lang)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(snippet.content, forType: .string)
                                    onPaste?(snippet.content)
                                }
                                .contextMenu {
                                    Button(lang.l("action.edit")) { editingSnippet = snippet }
                                    Button(lang.l("action.copy")) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(snippet.content, forType: .string)
                                    }
                                    Divider()
                                    Button(lang.l("action.delete"), role: .destructive) {
                                        snippetManager.delete(snippet)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
            }
        }
        .standardPopupLayout()
        .popupWindow(isPresented: $isAdding) {
            SnippetEditSheet(snippetManager: snippetManager, lang: lang)
        }
        .popupWindow(item: $editingSnippet) { snippet in
            SnippetEditSheet(snippetManager: snippetManager, lang: lang, existing: snippet)
        }
    }
}

// MARK: - Snippet Row

private struct SnippetRow: View {
    let snippet: Snippet
    @ObservedObject var lang: LanguageManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let shortcut = snippet.shortcut, !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                Text(snippet.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !snippet.category.isEmpty {
                Text(snippet.category)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor) : .clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Edit Sheet

struct SnippetEditSheet: View {
    @ObservedObject var snippetManager: SnippetManager
    @ObservedObject var lang: LanguageManager
    var existing: Snippet?
    @Environment(\.popupWindowDismiss) private var dismissPopup
    @State private var title = ""
    @State private var content = ""
    @State private var category = ""
    @State private var shortcut = ""

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(lang.l(isEditing ? "snippets.edit" : "snippets.add"), onClose: { dismissPopup() })

            Form {
                TextField(lang.l("snippets.field.title"), text: $title)
                TextField(lang.l("snippets.field.shortcut"), text: $shortcut)
                    .font(.system(.body, design: .monospaced))
                TextField(lang.l("snippets.field.category"), text: $category)
                Section {
                    TextEditor(text: $content)
                        .font(.system(size: 13))
                        .frame(minHeight: 80)
                        .standardEditorSurface()
                    Text("Variables: {{date}} · {{time}} · {{datetime}} · {{clipboard}} · {{random:8}} · {{cursor}}")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, DesignSystem.Spacing.xs)

            SheetFooter {
                Spacer()
                Button(lang.l("button.cancel")) { dismissPopup() }
                    .keyboardShortcut(.escape)
                Button(lang.l(isEditing ? "snippets.save" : "snippets.add")) {
                    saveSnippet()
                    dismissPopup()
                }
                .keyboardShortcut(.return)
                .disabled(title.isEmpty || content.isEmpty)
            }
        }
        .standardPopupLayout()
        .onAppear {
            if let s = existing {
                title = s.title
                content = s.content
                category = s.category
                shortcut = s.shortcut ?? ""
            }
        }
    }

    private func saveSnippet() {
        let sc = shortcut.isEmpty ? nil : shortcut
        if var s = existing {
            s.title = title
            s.content = content
            s.category = category
            s.shortcut = sc
            snippetManager.update(s)
        } else {
            let s = Snippet(title: title, content: content, category: category, shortcut: sc)
            snippetManager.add(s)
        }
    }
}
