import Foundation
import JavaScriptCore

enum ScriptResult: Equatable {
    case passthrough
    case modified(String)
    case discard
}

final class ScriptRuleRunner {
    /// Maximum execution time for a user script before it is treated as passthrough.
    static let defaultTimeout: TimeInterval = 3.0

    private let timeout: TimeInterval
    /// Serial queue for all JS evaluation. `contextCache` and `cacheOrder` are accessed only from this queue.
    private let evalQueue = DispatchQueue(label: "ScriptRuleRunner.eval", qos: .userInitiated)
    /// Reusable JSContext instances keyed by script source.
    /// Caching avoids re-parsing the script on every clipboard event.
    private var contextCache: [String: JSContext] = [:]
    /// Insertion / access order for true LRU eviction. Least-recently-used key is at index 0.
    private var cacheOrder: [String] = []
    private static let maxCacheSize = 20

    init(timeout: TimeInterval = ScriptRuleRunner.defaultTimeout) {
        self.timeout = timeout
    }

    /// Evaluates a user-provided JS script against clipboard content **without blocking any thread**.
    ///
    /// The script must define: `function process(content, bundleID) { ... }`
    /// - Return a string to modify the content
    /// - Return `null` to discard the item
    /// - Return the original content unchanged for passthrough
    ///
    /// Returns `nil` if the script exceeds `timeout`, throws a JS error, or is malformed.
    func evaluate(script: String, content: String, sourceBundleID: String?) async -> ScriptResult? {
        let timeout = self.timeout
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func tryResume(_ value: ScriptResult?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            evalQueue.async { [weak self] in
                guard let self else { tryResume(nil); return }
                let result = self.executeInContext(script: script, content: content, sourceBundleID: sourceBundleID)
                tryResume(result)
            }

            // Timeout: fires on a background global queue so no thread is blocked.
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + timeout) {
                tryResume(nil)
            }
        }
    }

    // MARK: - Context Cache (accessed only from evalQueue)

    private func getOrCreateContext(for script: String) -> JSContext? {
        if let cached = contextCache[script] {
            // Promote to most-recently-used position.
            cacheOrder.removeAll { $0 == script }
            cacheOrder.append(script)
            return cached
        }

        let ctx = JSContext()!
        var compileError: String?
        ctx.exceptionHandler = { _, exception in compileError = exception?.toString() }
        ctx.evaluateScript("""
        var setTimeout = undefined;
        var setInterval = undefined;
        var XMLHttpRequest = undefined;
        var fetch = undefined;
        var WebSocket = undefined;
        var require = undefined;
        var process = undefined;
        var globalThis = this;
        """)
        if script.count > 50_000 {
            return nil
        }
        ctx.evaluateScript(script)
        guard compileError == nil else { return nil }

        // Evict the least-recently-used entry when cache is full.
        if contextCache.count >= Self.maxCacheSize {
            let lruKey = cacheOrder.removeFirst()
            contextCache.removeValue(forKey: lruKey)
        }
        contextCache[script] = ctx
        cacheOrder.append(script)
        return ctx
    }

    // MARK: - Execution (always runs on evalQueue)

    private func executeInContext(script: String, content: String, sourceBundleID: String?) -> ScriptResult? {
        guard let ctx = getOrCreateContext(for: script) else { return nil }

        var jsError: String?
        ctx.exceptionHandler = { _, exception in jsError = exception?.toString() }

        guard let processFunc = ctx.objectForKeyedSubscript("process"),
              !processFunc.isUndefined else { return nil }

        let bundleArg: Any = sourceBundleID as Any? ?? NSNull()
        guard let result = processFunc.call(withArguments: [content, bundleArg]) else { return nil }
        if jsError != nil { return nil }

        if result.isNull { return .discard }
        if result.isString, let str = result.toString() {
            return str == content ? .passthrough : .modified(str)
        }
        return .passthrough
    }
}
