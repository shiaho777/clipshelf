import Foundation
import AppKit

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    var onItemSelected: (() -> Void)?
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private var lastContent: String = ""
    private var lastAddTime: Date = .distantPast
    
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClipboardManager")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("history.json")
    }
    
    private var pinnedCount: Int { items.filter { $0.isPinned }.count }
    
    init() {
        loadItems()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        startMonitoring()
    }
    
    deinit { stopMonitoring() }
    
    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        // 检查图片
        if let image = NSImage(pasteboard: pasteboard), let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            addImageItem(imageData: pngData)
            return
        }
        
        // 检查富文本
        if let rtfData = pasteboard.data(forType: .rtf),
           let plainText = pasteboard.string(forType: .string), !plainText.isEmpty {
            let now = Date()
            let interval = now.timeIntervalSince(lastAddTime)
            if plainText == lastContent && interval < 3 { return }
            lastContent = plainText
            lastAddTime = now
            addRichTextItem(content: plainText, rtfData: rtfData)
            return
        }
        
        // 检查纯文本
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let now = Date()
            let interval = now.timeIntervalSince(lastAddTime)
            if string == lastContent && interval < 3 { return }
            if !lastContent.isEmpty && interval < 3 {
                if lastContent.contains(string) || string.hasPrefix(lastContent) || lastContent.hasPrefix(string) {
                    if string.count > lastContent.count {
                        items.removeAll { $0.content == lastContent && $0.type == .text && !$0.isPinned }
                    } else {
                        return
                    }
                }
            }
            lastContent = string
            lastAddTime = now
            addTextItem(content: string)
        }
    }
    
    func addTextItem(content: String) {
        items.removeAll { $0.content == content && $0.type == .text && !$0.isPinned }
        items.insert(ClipboardItem(content: content, type: .text), at: pinnedCount)
        saveItems()
    }
    
    func addRichTextItem(content: String, rtfData: Data) {
        items.removeAll { $0.content == content && $0.type == .richText && !$0.isPinned }
        items.insert(ClipboardItem(content: content, rtfData: rtfData, type: .richText), at: pinnedCount)
        saveItems()
    }
    
    func addImageItem(imageData: Data) {
        items.insert(ClipboardItem(imageData: imageData, type: .image), at: pinnedCount)
        saveItems()
    }
    
    func copyToClipboard(_ item: ClipboardItem, autoPaste: Bool = false) {
        pasteboard.clearContents()
        switch item.type {
        case .image:
            if let imageData = item.imageData,
               let image = NSImage(data: imageData), let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
                pasteboard.setData(imageData, forType: .png)
            }
        case .richText:
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            pasteboard.setString(item.content, forType: .string)
        case .text:
            pasteboard.setString(item.content, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
        if autoPaste { onItemSelected?() }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }
    
    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items = items.filter { $0.isPinned } + items.filter { !$0.isPinned }
        saveItems()
    }
    
    func clearAll() {
        items.removeAll { !$0.isPinned }
        saveItems()
    }
    
    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            try? encoded.write(to: storageURL)
        }
    }
    
    private func loadItems() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }
    
    func search(_ query: String) -> [ClipboardItem] {
        query.isEmpty ? items : items.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }
}
