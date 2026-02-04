import Foundation

struct ExportData: Codable {
    let version: String
    let exportDate: Date
    let clipboardItems: [ClipboardItem]
    let snippets: [Snippet]
    let snippetFolders: [SnippetFolder]
}

class DataExporter {
    static let shared = DataExporter()
    
    func exportAll(to url: URL) {
        let data = ExportData(
            version: "1.1",
            exportDate: Date(),
            clipboardItems: [],  // 不导出剪贴板历史（可能包含敏感信息）
            snippets: SnippetManager.shared.snippets,
            snippetFolders: SnippetManager.shared.folders
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        if let jsonData = try? encoder.encode(data) {
            try? jsonData.write(to: url)
        }
    }
    
    func importAll(from url: URL, clipboardManager: ClipboardManager) {
        guard let jsonData = try? Data(contentsOf: url) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let data = try? decoder.decode(ExportData.self, from: jsonData) else { return }
        
        // 导入片段和文件夹
        SnippetManager.shared.importData(snippets: data.snippets, folders: data.snippetFolders)
    }
}
