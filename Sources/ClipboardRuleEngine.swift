import Foundation

enum RuleEngineResult: Equatable {
    case store(CapturedContent)
    case storeSensitive(CapturedContent, ttl: Int?)
    case discard
    case pin(CapturedContent)
    
    static func == (lhs: RuleEngineResult, rhs: RuleEngineResult) -> Bool {
        switch (lhs, rhs) {
        case (.discard, .discard): return true
        case (.store(let a), .store(let b)): return a == b
        case (.storeSensitive(let a, let t1), .storeSensitive(let b, let t2)): return a == b && t1 == t2
        case (.pin(let a), .pin(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - CapturedContent Equatable

extension CapturedContent: Equatable {
    static func == (lhs: CapturedContent, rhs: CapturedContent) -> Bool {
        guard lhs.sourceBundleID == rhs.sourceBundleID,
              lhs.sourceAppName == rhs.sourceAppName else { return false }
        switch (lhs.kind, rhs.kind) {
        case (.text(let a), .text(let b)): return a == b
        case (.richText(let a, let d1), .richText(let b, let d2)): return a == b && d1 == d2
        case (.image(let a), .image(let b)): return a == b
        case (.imageFile(let a, let extA), .imageFile(let b, let extB)): return a == b && extA == extB
        default: return false
        }
    }
}

// MARK: - Rule Engine

@MainActor
final class ClipboardRuleEngine {
    var rules: [ClipboardRule] = [] {
        didSet { rebuildExecutionPlan() }
    }
    private let scriptRunner = ScriptRuleRunner()
    private var enabledRules: [ClipboardRule] = []
    private let regexCache = NSCache<NSString, NSRegularExpression>()

    private func rebuildExecutionPlan() {
        enabledRules = rules.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    func process(_ content: CapturedContent) async -> RuleEngineResult {
        var current = content
        var shouldPin = false
        var isSensitive = false
        var sensitiveTTL: Int? = nil
        
        for rule in enabledRules {
            guard triggerMatches(rule.trigger, content: current) else { continue }
            
            for action in rule.actions {
                switch action {
                case .discard:
                    return .discard
                    
                case .stripURLTracking:
                    current = applyStripURLTracking(current)
                    
                case .detectSensitive(let ttl):
                    if containsSensitiveContent(current) {
                        isSensitive = true
                        sensitiveTTL = ttl
                    }
                    
                case .replaceRegex(let pattern, let replacement):
                    current = applyRegexReplace(current, pattern: pattern, replacement: replacement)
                    
                case .trimWhitespace:
                    current = applyTrimWhitespace(current)
                    
                case .autoPin:
                    shouldPin = true
                    
                case .runScript(let source):
                    if let text = textContent(current) {
                        let result = await scriptRunner.evaluate(script: source, content: text, sourceBundleID: current.sourceBundleID)
                        switch result {
                        case .discard:
                            return .discard
                        case .modified(let newText):
                            current = replaceText(in: current, with: newText)
                        case .passthrough, .none:
                            break
                        }
                    }
                }
            }
        }

        if isSensitive {
            return .storeSensitive(current, ttl: sensitiveTTL)
        }
        if shouldPin {
            return .pin(current)
        }
        return .store(current)
    }

    // MARK: - Test / Preview

    /// One execution step in the debug trace: captures the state before and after each action.
    struct TraceStep {
        let ruleName: String
        let actionName: String
        let inputText: String
        let outputText: String
        /// True when this action caused early termination (discard).
        let isTerminal: Bool

        var didChange: Bool { !isTerminal && inputText != outputText }
    }

    struct TestResult {
        let output: String
        let matchedRules: [String]
        let outcome: String  // "store", "discard", "sensitive", "pin"
        let steps: [TraceStep]

        init(output: String, matchedRules: [String], outcome: String, steps: [TraceStep] = []) {
            self.output = output
            self.matchedRules = matchedRules
            self.outcome = outcome
            self.steps = steps
        }
    }

    /// Test all enabled rules against sample text, returning the processed result,
    /// matched rules, and a per-action execution trace. Does not modify any state.
    func testProcess(text: String, sourceBundleID: String? = nil) async -> TestResult {
        let content = CapturedContent(kind: .text(content: text), sourceBundleID: sourceBundleID, sourceAppName: nil)
        var current = content
        var shouldPin = false
        var isSensitive = false
        var matchedRuleNames: [String] = []
        var traceSteps: [TraceStep] = []

        for rule in enabledRules {
            guard triggerMatches(rule.trigger, content: current) else { continue }
            matchedRuleNames.append(rule.name)

            for action in rule.actions {
                let inputText = textContent(current) ?? ""
                switch action {
                case .discard:
                    traceSteps.append(TraceStep(
                        ruleName: rule.name, actionName: "discard",
                        inputText: inputText, outputText: "", isTerminal: true))
                    return TestResult(output: "", matchedRules: matchedRuleNames,
                                     outcome: "discard", steps: traceSteps)

                case .stripURLTracking:
                    current = applyStripURLTracking(current)
                    traceSteps.append(TraceStep(
                        ruleName: rule.name, actionName: "stripURLTracking",
                        inputText: inputText, outputText: textContent(current) ?? "",
                        isTerminal: false))

                case .detectSensitive:
                    if containsSensitiveContent(current) { isSensitive = true }
                    traceSteps.append(TraceStep(
                        ruleName: rule.name, actionName: "detectSensitive",
                        inputText: inputText,
                        outputText: isSensitive ? "⚠️ sensitive detected" : "✓ no match",
                        isTerminal: false))

                case .replaceRegex(let pattern, let replacement):
                    current = applyRegexReplace(current, pattern: pattern, replacement: replacement)
                    traceSteps.append(TraceStep(
                        ruleName: rule.name,
                        actionName: "replaceRegex(\(pattern)→\(replacement))",
                        inputText: inputText, outputText: textContent(current) ?? "",
                        isTerminal: false))

                case .trimWhitespace:
                    current = applyTrimWhitespace(current)
                    traceSteps.append(TraceStep(
                        ruleName: rule.name, actionName: "trimWhitespace",
                        inputText: inputText, outputText: textContent(current) ?? "",
                        isTerminal: false))

                case .autoPin:
                    shouldPin = true
                    traceSteps.append(TraceStep(
                        ruleName: rule.name, actionName: "autoPin",
                        inputText: inputText, outputText: inputText, isTerminal: false))

                case .runScript(let source):
                    if let t = textContent(current) {
                        let result = await scriptRunner.evaluate(script: source, content: t,
                                                                sourceBundleID: sourceBundleID)
                        switch result {
                        case .discard:
                            traceSteps.append(TraceStep(
                                ruleName: rule.name, actionName: "runScript",
                                inputText: t, outputText: "", isTerminal: true))
                            return TestResult(output: "", matchedRules: matchedRuleNames,
                                             outcome: "discard", steps: traceSteps)
                        case .modified(let newText):
                            current = replaceText(in: current, with: newText)
                            traceSteps.append(TraceStep(
                                ruleName: rule.name, actionName: "runScript",
                                inputText: t, outputText: newText, isTerminal: false))
                        case .passthrough, .none:
                            traceSteps.append(TraceStep(
                                ruleName: rule.name, actionName: "runScript (passthrough)",
                                inputText: t, outputText: t, isTerminal: false))
                        }
                    }
                }
            }
        }

        let outputText = textContent(current) ?? text
        let outcome = isSensitive ? "sensitive" : (shouldPin ? "pin" : "store")
        return TestResult(output: outputText, matchedRules: matchedRuleNames,
                          outcome: outcome, steps: traceSteps)
    }

    // MARK: - Trigger Matching
    
    private func triggerMatches(_ trigger: RuleTrigger, content: CapturedContent) -> Bool {
        switch trigger {
        case .always:
            return true
        case .contentMatches(let pattern):
            guard let text = textContent(content) else { return false }
            guard let regex = regex(for: pattern) else { return false }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        case .sourceApp(let bundleID):
            return content.sourceBundleID == bundleID
        case .contentType(let type):
            switch (type, content.kind) {
            case (.text, .text): return true
            case (.richText, .richText): return true
            case (.image, .image), (.image, .imageFile): return true
            default: return false
            }
        }
    }
    
    // MARK: - Actions
    
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "mc_cid", "mc_eid", "msclkid", "twclid",
        "yclid", "igshid", "s_cid", "ref", "ref_src", "ref_url",
        "_ga", "_gl", "ncid", "ocid", "spm", "vero_id"
    ]
    
    private func applyStripURLTracking(_ content: CapturedContent) -> CapturedContent {
        guard let text = textContent(content) else { return content }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else { return content }
        
        let cleaned = queryItems.filter { !Self.trackingParams.contains($0.name.lowercased()) }
        components.queryItems = cleaned.isEmpty ? nil : cleaned
        
        guard let cleanedURL = components.string, cleanedURL != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return content }
        return replaceText(in: content, with: cleanedURL)
    }
    
    private static let sensitivePatterns: [(String, NSRegularExpression?)] = {
        let patterns = [
            ("credit_card", #"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b"#),
            ("aws_key", #"AKIA[0-9A-Z]{16}"#),
            ("ssh_key", #"-----BEGIN[A-Z ]*PRIVATE KEY-----"#),
            ("generic_secret", #"(?i)(api[_-]?key|secret[_-]?key|access[_-]?token|private[_-]?key)\s*[:=]\s*['"]?[A-Za-z0-9+/=_\-]{16,}"#)
        ]
        return patterns.map { ($0.0, try? NSRegularExpression(pattern: $0.1, options: [])) }
    }()

    private func regex(for pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        regexCache.setObject(regex, forKey: key)
        return regex
    }
    
    func containsSensitiveContent(_ content: CapturedContent) -> Bool {
        guard let text = textContent(content) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return Self.sensitivePatterns.contains { _, regex in
            regex?.firstMatch(in: text, range: range) != nil
        }
    }
    
    private func applyRegexReplace(_ content: CapturedContent, pattern: String, replacement: String) -> CapturedContent {
        guard let text = textContent(content),
              let regex = regex(for: pattern) else { return content }
        let range = NSRange(text.startIndex..., in: text)
        let replaced = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
        return replaced != text ? replaceText(in: content, with: replaced) : content
    }
    
    private func applyTrimWhitespace(_ content: CapturedContent) -> CapturedContent {
        guard let text = textContent(content) else { return content }
        let trimmed = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != text ? replaceText(in: content, with: trimmed) : content
    }
    
    // MARK: - Helpers
    
    private func textContent(_ content: CapturedContent) -> String? {
        switch content.kind {
        case .text(let t): return t
        case .richText(let t, _): return t
        case .image, .imageFile: return nil
        case .fileURL: return nil
        }
    }
    
    private func replaceText(in content: CapturedContent, with newText: String) -> CapturedContent {
        let newKind: CapturedContent.Kind
        switch content.kind {
        case .text:
            newKind = .text(content: newText)
        case .richText(_, let rtf):
            newKind = .richText(content: newText, rtfData: rtf)
        case .image, .imageFile:
            return content
        case .fileURL:
            return content
        }
        return CapturedContent(kind: newKind, sourceBundleID: content.sourceBundleID, sourceAppName: content.sourceAppName)
    }
}
