import Foundation
import JavaScriptCore

enum ScriptResult: Equatable {
    case passthrough
    case modified(String)
    case discard
}

final class ScriptRuleRunner {
    static let defaultTimeout: TimeInterval = 3.0

    private let timeout: TimeInterval
    private let stateLock = NSLock()
    private var evalQueue = DispatchQueue(label: "ScriptRuleRunner.eval", qos: .userInitiated)
    private var contextCache: [String: JSContext] = [:]
    private var cacheOrder: [String] = []
    private static let maxCacheSize = 20
    private var hungScripts: Set<String> = []

    init(timeout: TimeInterval = ScriptRuleRunner.defaultTimeout) {
        self.timeout = timeout
    }

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
                guard let self else {
                    sync.lock()
                    let won = !resumed
                    resumed = true
                    sync.unlock()
                    guard won else { return }
                    continuation.resume(returning: nil)
                    return
                }
                let result = self.executeInContext(script: script, content: content, sourceBundleID: sourceBundleID)
                sync.lock()
                let timeoutWon = resumed
                resumed = true
                completed = true
                sync.unlock()
                guard !timeoutWon else { return }
                continuation.resume(returning: result)
            }

            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + timeout) { [weak self] in
                sync.lock()
                let won = !resumed && !completed
                resumed = true
                sync.unlock()
                guard won else { return }
                self?.quarantineScript(script, staleQueue: queue)
                continuation.resume(returning: nil)
            }
        }
    }

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

    private func evaluateScriptSetup(_ script: String, ctx: JSContext) {
        let thread = Thread {
            _ = ctx.evaluateScript(script)
        }
        thread.name = "ScriptRuleRunner.setup"
        thread.stackSize = 8 << 20
        thread.start()
    }

    private func getOrCreateContext(for script: String) -> JSContext? {
        stateLock.lock()

        if let cached = contextCache[script] {
            cacheOrder.removeAll { $0 == script }
            cacheOrder.append(script)
            stateLock.unlock()
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
            stateLock.unlock()
            return nil
        }
        stateLock.unlock()

        let setupGroup = DispatchGroup()
        setupGroup.enter()
        let setupThread = Thread {
            _ = ctx.evaluateScript(script)
            setupGroup.leave()
        }
        setupThread.name = "ScriptRuleRunner.setup"
        setupThread.stackSize = 8 << 20
        setupThread.start()

        if setupGroup.wait(timeout: .now() + timeout) == .timedOut {
            quarantineAfterSetupTimeout(script, ctx: ctx)
            return nil
        }
        guard compileError == nil else { return nil }

        stateLock.lock()
        defer { stateLock.unlock() }
        if let cached = contextCache[script] {
            cacheOrder.removeAll { $0 == script }
            cacheOrder.append(script)
            return cached
        }
        if contextCache.count >= Self.maxCacheSize {
            let lruKey = cacheOrder.removeFirst()
            contextCache.removeValue(forKey: lruKey)
        }
        contextCache[script] = ctx
        cacheOrder.append(script)
        return ctx
    }

    private func quarantineAfterSetupTimeout(_ script: String, ctx: JSContext) {
        stateLock.lock()
        hungScripts.insert(script)
        if contextCache[script] != nil {
            contextCache.removeValue(forKey: script)
            cacheOrder.removeAll { $0 == script }
        }
        stateLock.unlock()
    }

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
