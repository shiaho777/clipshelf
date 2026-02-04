import Foundation
import AppKit
import Carbon.HIToolbox

struct SnippetFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isExpanded: Bool
    
    init(id: UUID = UUID(), name: String = "", isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
    }
}

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var shortcutIndex: Int
    var folderId: UUID?
    
    init(id: UUID = UUID(), name: String = "", content: String = "", shortcutIndex: Int = 0, folderId: UUID? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.shortcutIndex = shortcutIndex
        self.folderId = folderId
    }
}

class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    
    @Published var snippets: [Snippet] = []
    @Published var folders: [SnippetFolder] = []
    private var hotKeyRefs: [Int: EventHotKeyRef] = [:]
    
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClipboardManager")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("snippets.json")
    }
    
    private var foldersURL: URL {
        storageURL.deletingLastPathComponent().appendingPathComponent("folders.json")
    }
    
    init() {
        loadSnippets()
        loadFolders()
    }
    
    func snippets(in folder: SnippetFolder?) -> [Snippet] {
        snippets.filter { $0.folderId == folder?.id }
    }
    
    func addFolder(_ folder: SnippetFolder) {
        folders.append(folder)
        saveFolders()
    }
    
    func updateFolder(_ folder: SnippetFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            saveFolders()
        }
    }
    
    func deleteFolder(_ folder: SnippetFolder) {
        snippets.filter { $0.folderId == folder.id }.forEach { snippet in
            var updated = snippet
            updated.folderId = nil
            updateSnippet(updated)
        }
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }
    
    func toggleFolderExpanded(_ folder: SnippetFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].isExpanded.toggle()
            saveFolders()
        }
    }
    
    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            try? encoded.write(to: foldersURL)
        }
    }
    
    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersURL),
              let decoded = try? JSONDecoder().decode([SnippetFolder].self, from: data) else { return }
        folders = decoded
    }
    
    func importData(snippets: [Snippet], folders: [SnippetFolder]) {
        self.snippets.append(contentsOf: snippets)
        self.folders.append(contentsOf: folders)
        saveSnippets()
        saveFolders()
        registerHotKeys()
    }
    
    func registerHotKeys() {
        unregisterAllHotKeys()
        for snippet in snippets where snippet.shortcutIndex > 0 {
            registerHotKey(for: snippet.shortcutIndex)
        }
    }
    
    private func registerHotKey(for index: Int) {
        guard index >= 1 && index <= 9 else { return }
        
        let keyCode: UInt32 = UInt32(0x12 + index - 1) // 1=0x12, 2=0x13, ..., 9=0x19
        let modifiers: UInt32 = UInt32(cmdKey)
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("SNIP".fourCharCodeValue)
        hotKeyID.id = UInt32(index)
        
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if let ref = hotKeyRef {
            hotKeyRefs[index] = ref
        }
    }
    
    private func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
    
    func pasteSnippet(index: Int) {
        guard let snippet = snippets.first(where: { $0.shortcutIndex == index }) else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulateCmdV()
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
    
    func addSnippet(_ snippet: Snippet) {
        var newSnippet = snippet
        if newSnippet.shortcutIndex > 0 {
            snippets.removeAll { $0.shortcutIndex == newSnippet.shortcutIndex }
        }
        snippets.append(newSnippet)
        saveSnippets()
        registerHotKeys()
    }
    
    func updateSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            if snippet.shortcutIndex > 0 {
                snippets.removeAll { $0.shortcutIndex == snippet.shortcutIndex && $0.id != snippet.id }
            }
            snippets[index] = snippet
            saveSnippets()
            registerHotKeys()
        }
    }
    
    func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        saveSnippets()
        registerHotKeys()
    }
    
    func availableShortcuts() -> [Int] {
        let used = Set(snippets.map { $0.shortcutIndex })
        return (0...9).filter { $0 == 0 || !used.contains($0) }
    }
    
    private func saveSnippets() {
        if let encoded = try? JSONEncoder().encode(snippets) {
            try? encoded.write(to: storageURL)
        }
    }
    
    private func loadSnippets() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else { return }
        snippets = decoded
    }
}

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf8.prefix(4) { result = (result << 8) + FourCharCode(char) }
        return result
    }
}
