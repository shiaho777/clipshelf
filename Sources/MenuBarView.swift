import SwiftUI

enum FilterType: CaseIterable {
    case all, text, image
    var key: String {
        switch self {
        case .all: return "filter.all"
        case .text: return "filter.text"
        case .image: return "filter.image"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var lang = LanguageManager.shared
    @State private var searchText = ""
    @State private var hoveredItemId: UUID?
    @State private var refreshTrigger = false
    @State private var filterType: FilterType = .all
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var onOpenSettings: () -> Void = {}
    
    var filteredItems: [ClipboardItem] {
        _ = refreshTrigger
        let searched = clipboardManager.search(searchText)
        switch filterType {
        case .all: return searched
        case .text: return searched.filter { $0.type == .text }
        case .image: return searched.filter { $0.type == .image }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(lang.l("search.placeholder"), text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            
            HStack(spacing: 0) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    Text(lang.l(type.key))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(filterType == type ? Color.accentColor.opacity(0.2) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { filterType = type }
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            ScrollView {
                if filteredItems.isEmpty {
                    Text(lang.l("empty.message")).foregroundColor(.secondary).padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredItems) { item in
                            ClipboardItemRow(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                onCopy: { clipboardManager.copyToClipboard(item, autoPaste: true) },
                                onPin: { clipboardManager.togglePin(item) },
                                onDelete: { clipboardManager.deleteItem(item) }
                            )
                            .onHover { hoveredItemId = $0 ? item.id : nil }
                        }
                    }.padding(.vertical, 4)
                }
            }.frame(minHeight: 100, maxHeight: 350)
            
            Divider()
            
            HStack {
                Text(lang.l("items.count", filteredItems.count)).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain)
                Button(lang.l("button.clear")) { clipboardManager.clearAll() }.buttonStyle(.plain).foregroundColor(.red)
                Button(lang.l("button.quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }.padding(10)
        }
        .frame(width: 320)
        .onReceive(timer) { _ in refreshTrigger.toggle() }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @ObservedObject var lang = LanguageManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            if item.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundColor(.orange)
            }
            
            if item.type == .image, let nsImage = item.image {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 60).cornerRadius(4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.l("item.image")).font(.system(size: 12)).foregroundColor(.secondary)
                    Text(item.timeAgo).font(.caption2).foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText).lineLimit(2).font(.system(size: 12))
                    Text(item.timeAgo).font(.caption2).foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onPin) { Image(systemName: item.isPinned ? "pin.slash" : "pin") }
                        .buttonStyle(.plain)
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.5) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .onDrag {
            if item.type == .image, let imageData = item.imageData, let image = NSImage(data: imageData) {
                return NSItemProvider(object: image)
            }
            return NSItemProvider(object: item.content as NSString)
        }
    }
}
