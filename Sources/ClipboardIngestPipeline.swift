import Foundation

@MainActor
final class ClipboardIngestPipeline {
    private let ruleEngine: ClipboardRuleEngine
    private let onStore: (CapturedContent, Bool, Date?, Bool) -> Void

    init(
        ruleEngine: ClipboardRuleEngine,
        onStore: @escaping (CapturedContent, Bool, Date?, Bool) -> Void
    ) {
        self.ruleEngine = ruleEngine
        self.onStore = onStore
    }

    func handle(_ content: CapturedContent) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.ruleEngine.process(content)
            switch result {
            case .store(let c):
                self.onStore(c, false, nil, false)
            case .storeSensitive(let c, let ttl):
                let expiry = ttl.map { Date().addingTimeInterval(Double($0)) }
                self.onStore(c, true, expiry, false)
            case .discard:
                return
            case .pin(let c):
                self.onStore(c, false, nil, true)
            }
        }
    }
}
