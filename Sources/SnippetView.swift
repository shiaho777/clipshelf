import SwiftUI

struct SnippetListView: View {
    @ObservedObject var snippetManager = SnippetManager.shared
    @ObservedObject var lang = LanguageManager.shared
    @State private var showingAddSheet = false
    @State private var editingSnippet: Snippet?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lang.l("snippets.title")).font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding()
            
            Divider()
            
            if snippetManager.snippets.isEmpty {
                VStack {
                    Spacer()
                    Text(lang.l("snippets.empty")).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(snippetManager.snippets) { snippet in
                        SnippetRow(snippet: snippet) {
                            editingSnippet = snippet
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { snippetManager.deleteSnippet(snippetManager.snippets[$0]) }
                    }
                }
            }
        }
        .frame(width: 400, height: 350)
        .sheet(isPresented: $showingAddSheet) {
            SnippetEditView(snippet: nil) { newSnippet in
                snippetManager.addSnippet(newSnippet)
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditView(snippet: snippet) { updatedSnippet in
                snippetManager.updateSnippet(updatedSnippet)
            }
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onEdit: () -> Void
    @ObservedObject var lang = LanguageManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snippet.name).fontWeight(.medium)
                    if snippet.shortcutIndex > 0 {
                        Text("⌘\(snippet.shortcutIndex)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(snippet.content.prefix(50) + (snippet.content.count > 50 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct SnippetEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var lang = LanguageManager.shared
    @ObservedObject var snippetManager = SnippetManager.shared
    
    let existingSnippet: Snippet?
    let onSave: (Snippet) -> Void
    
    @State private var name: String = ""
    @State private var content: String = ""
    @State private var shortcutIndex: Int = 0
    
    init(snippet: Snippet?, onSave: @escaping (Snippet) -> Void) {
        self.existingSnippet = snippet
        self.onSave = onSave
        _name = State(initialValue: snippet?.name ?? "")
        _content = State(initialValue: snippet?.content ?? "")
        _shortcutIndex = State(initialValue: snippet?.shortcutIndex ?? 0)
    }
    
    var availableShortcuts: [Int] {
        var available = snippetManager.availableShortcuts()
        if let existing = existingSnippet, existing.shortcutIndex > 0, !available.contains(existing.shortcutIndex) {
            available.append(existing.shortcutIndex)
            available.sort()
        }
        return available
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(existingSnippet == nil ? lang.l("snippets.add") : lang.l("snippets.edit"))
                .font(.headline)
            
            Form {
                TextField(lang.l("snippets.name"), text: $name)
                
                Picker(lang.l("snippets.shortcut"), selection: $shortcutIndex) {
                    Text(lang.l("snippets.none")).tag(0)
                    ForEach(availableShortcuts.filter { $0 > 0 }, id: \.self) { index in
                        Text("⌘\(index)").tag(index)
                    }
                }
                
                Text(lang.l("snippets.content"))
                TextEditor(text: $content)
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3))
            }
            
            HStack {
                Button(lang.l("button.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(lang.l("button.save")) {
                    let snippet = Snippet(
                        id: existingSnippet?.id ?? UUID(),
                        name: name,
                        content: content,
                        shortcutIndex: shortcutIndex
                    )
                    onSave(snippet)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || content.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}
