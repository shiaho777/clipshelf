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
    /// Guards `evalQueue`, `contextCache`, `cacheOrder` and `hungScripts`.
    /// The queue itself must be replaceable because a script that never
    /// returns blocks its worker thread forever; everything reachable from
    /// more than one thread lives behind this lock.
    private let stateLock = NSLock()
    /// Serial queue for all JS evaluation. Rotated to a fresh queue when a
    /// script hangs, so later evaluations are not queued behind the stuck one.
    private var evalQueue = DispatchQueue(label: "ScriptRuleRunner.eval", qos: .userInitiated)
    /// Reusable JSContext instances keyed by script source.
    /// Caching avoids re-parsing the script on every clipboard event.
    private var contextCache: [String: JSContext] = [:]
    /// Insertion / access order for true LRU eviction. Least-recently-used key is at index 0.
    private var cacheOrder: [String] = []
    private static let maxCacheSize = 20
    /// Script sources that previously failed to return within `timeout`
    /// (e.g. contain an infinite loop). JavaScriptCore has no public API to
    /// preempt a running script, so these are skipped instead of burning a
    /// fresh thread and another timeout window on every clipboard event.
    private var hungScripts: Set<String> = []

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
    /// Returns `nil` if the script exceeds `timeout`, threw a JS error,
    /// is malformed, or previously hung and is quarantined.
    func evaluate(script: String, content: String, sourceBundleID: String?) async -> ScriptResult? {
        stateLock.lock()
        if hungScripts.contains(script) {
            stateLock.unlock()
            return nil
        }
        let queue = evalQueue
        stateLock.unlock()

        let timeout = self.timeout
        return await withCheckedContinuation { continuation in
            let sync = NSLock()
            var resumed = false
            var completed = false

            queue.async { [weak self] in
                guard let self else { tryResume(nil, finished: false); return }
                let result = self.executeInContext(script: script, content: content, sourceBundleID: sourceBundleID)
                tryResume(result, finished: true)
            }

            // Timeout: fires on a background global queue so no thread is blocked.
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + timeout) { [weak self] in
                let didTimeOut = tryResume(nil, finished: false)
                if didTimeOut {
                    // The script is still spinning on `queue`. Quarantine it and
                    // rotate to a fresh queue so subsequent rules keep working;
                    // the blocked thread is abandoned.
                    self?.quarantineScript(script, staleQueue: queue)
                }
            }

            func tryResume(_ value: ScriptResult?, finished: Bool) -> Bool {
                sync.lock()
                let isFirst = !resumed
                resumed = true
                if finished { completed = true }
                let alreadyCompleted = completed
                sync.unlock()
                guard isFirst else { return false }
                continuation.resume(returning: value)
                // True when *this* caller won the race and the script had not
                // finished — i.e. the timeout handler observing a live script.
                return !finished && !alreadyCompleted
            }
        }
    }

    // MARK: - Quarantine

    private func quarantineScript(_ script: String, staleQueue: DispatchQueue) {
        stateLock.lock()
        defer { stateLock.unlock() }
        hungScripts.insert(script)
        if contextCache[script] != nil {
            contextCache.removeValue(forKey: script)
            cacheOrder.removeAll { $0 == script }
        }
        if evalQueue === staleQueue {
            evalQueue = DispatchQueue(label: "ScriptRuleRunner.eval", qos: .userInitiated)
        }
    }

    // MARK: - Context Cache

    private func getOrCreateContext(for script: String) -> JSContext? {
        stateLock.lock()
        defer { stateLock.unlock() }

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

    // MARK: - Execution (runs on the current evalQueue)

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
