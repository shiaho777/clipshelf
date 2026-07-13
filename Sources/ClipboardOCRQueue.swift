import Foundation

@MainActor
final class ClipboardOCRQueue {
    private var pendingIDs: [UUID] = []
    private var headIndex = 0
    private var pendingIDSet: Set<UUID> = []
    private var isProcessing = false
    private let maxPendingItems: Int
    private let imageManager: ClipboardImageManager
    private let itemProvider: (UUID) -> ClipboardItem?
    private let onRecognized: (UUID, String) -> Void

    var depth: Int { pendingIDs.count - headIndex }

    init(
        imageManager: ClipboardImageManager,
        maxPendingItems: Int = 64,
        itemProvider: @escaping (UUID) -> ClipboardItem?,
        onRecognized: @escaping (UUID, String) -> Void
    ) {
        self.imageManager = imageManager
        self.maxPendingItems = maxPendingItems
        self.itemProvider = itemProvider
        self.onRecognized = onRecognized
    }

    func enqueue(_ id: UUID) {
        guard pendingIDSet.insert(id).inserted else { return }
        pendingIDs.append(id)
        let queuedCount = pendingIDs.count - headIndex
        if queuedCount > maxPendingItems {
            let overflowCount = queuedCount - maxPendingItems
            let overflow = pendingIDs[headIndex..<(headIndex + overflowCount)]
            pendingIDSet.subtract(overflow)
            headIndex += overflowCount
            compactIfNeeded()
        }
        processNext()
    }

    func enqueue(ids: [UUID]) {
        for id in ids {
            enqueue(id)
        }
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty, !pendingIDs.isEmpty else { return }
        let boundedHeadIndex = min(headIndex, pendingIDs.count)
        let removedBeforeHeadIndex = pendingIDs[..<boundedHeadIndex].reduce(0) { count, id in
            count + (ids.contains(id) ? 1 : 0)
        }
        pendingIDs.removeAll { ids.contains($0) }
        headIndex = min(max(0, boundedHeadIndex - removedBeforeHeadIndex), pendingIDs.count)
        pendingIDSet.subtract(ids)
        compactIfNeeded()
    }

    private func processNext() {
        guard !isProcessing else { return }
        while headIndex < pendingIDs.count {
            let id = pendingIDs[headIndex]
            headIndex += 1
            pendingIDSet.remove(id)
            compactIfNeeded()
            guard let item = itemProvider(id), item.type == .image, item.ocrText == nil else {
                continue
            }
            isProcessing = true
            Task { [weak self] in
                guard let self else { return }
                let data = await self.imageManager.imageDataForOCR(for: item)
                guard let data else {
                    self.isProcessing = false
                    self.processNext()
                    return
                }
                self.imageManager.recognizeText(in: data) { [weak self] ocrText in
                    guard let self else { return }
                    self.isProcessing = false
                    if let ocrText {
                        self.onRecognized(id, ocrText)
                    }
                    self.processNext()
                }
            }
            return
        }
        compactIfNeeded(force: true)
    }

    private func compactIfNeeded(force: Bool = false) {
        guard headIndex > 0 else { return }
        if force || headIndex >= 16 && headIndex * 2 >= pendingIDs.count {
            pendingIDs.removeFirst(headIndex)
            headIndex = 0
        }
    }
}
