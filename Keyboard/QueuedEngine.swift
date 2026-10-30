import Foundation
import QuartzCore
import os

/// 把拼音引擎放到后台串行队列上跑：字母键交给它就返回，主线程不用等 Rime 算候选，连打时触摸不排队。
/// 算完的结果按按键顺序取回。选词、删除、空格这类要看当前组字状态的操作，先等排着的键算完、上屏，再同步执行，顺序不会乱。
/// Rime 只在这个队列上调用；这个对象本身只在主线程用。
final class QueuedEngine: InputEngine {
    static let shared = QueuedEngine(RimeEngine.shared)

    /// 引擎在某个时刻的样子，主线程显示用。
    struct Snapshot {
        var composition = ""
        var candidates: [String] = []
        var rawInput = ""
        var selections: [InputSelection] = []
        var lastCorrection: CommittedCorrection?
        var pendingCorrection: PendingCorrection?
    }

    /// 后台算完的一个按键。
    struct Result {
        var commit: String?
        var snapshot: Snapshot
        /// 触摸发生（拿不到时是交给队列）的时刻，和引擎自己算了多久（秒）。
        var queuedAt: CFTimeInterval
        var engineTime: CFTimeInterval
        var signpost: OSSignpostIntervalState
    }

    /// Instruments 里看每个键的耗时（os_signpost「key」区间）。
    static let signposter = OSSignposter(subsystem: "app.enclave.keyboard", category: "Typing")

    private let inner: RimeEngine
    private let queue = DispatchQueue(label: "app.enclave.rime", qos: .userInteractive)
    private let lock = NSLock()
    /// 后台写、主线程取，用 lock 保护。
    private var outbox: [Result] = []
    /// 主线程上最近取回的状态。
    private var state = Snapshot()
    /// 交给队列、还没取回结果的按键数。
    private(set) var pending = 0
    /// 交给队列、还没取回结果的按键本身，按顺序。
    private var queuedKeys: [String] = []
    /// 算上还在排队的键，引擎里现在的原始输入（动态热区看上下文用）。
    var expectedRawInput: String { state.rawInput + queuedKeys.joined() }
    /// 有结果算完了（主线程调用）：键盘取回结果，上屏、更新候选。
    var resultsReady: (() -> Void)?
    /// 同步操作前先让键盘把排着的结果处理掉（上屏），这样上屏顺序和按键顺序一致。
    var willSync: (() -> Void)?

    init(_ inner: RimeEngine) {
        self.inner = inner
    }

    var composition: String { state.composition }
    var candidates: [String] { state.candidates }
    var rawInput: String { state.rawInput }
    var selections: [InputSelection] { state.selections }
    var lastCorrection: CommittedCorrection? { state.lastCorrection }
    var pendingCorrection: PendingCorrection? { state.pendingCorrection }

    // MARK: - 后台

    /// 字母、九宫格数字：交给队列就返回，算完后 resultsReady 通知键盘来取。
    /// since：触摸事件的时刻（和 CACurrentMediaTime 同一个时钟），耗时从这里算。
    func inputLater(_ key: String, since: CFTimeInterval? = nil) {
        pending += 1
        queuedKeys.append(key)
        let queuedAt = since ?? CACurrentMediaTime()
        let signpost = Self.signposter.beginInterval("key", id: Self.signposter.makeSignpostID())
        queue.async { [inner] in
            let start = CACurrentMediaTime()
            let commit = inner.input(key)
            let result = Result(commit: commit, snapshot: Self.snapshot(of: inner), queuedAt: queuedAt,
                                engineTime: CACurrentMediaTime() - start, signpost: signpost)
            self.lock.lock()
            self.outbox.append(result)
            self.lock.unlock()
            DispatchQueue.main.async { self.resultsReady?() }
        }
    }

    /// 取回已经算完的结果，按按键顺序。
    func takeResults() -> [Result] {
        lock.lock()
        let results = outbox
        outbox.removeAll()
        lock.unlock()
        guard let last = results.last else { return [] }
        pending -= results.count
        queuedKeys.removeFirst(min(results.count, queuedKeys.count))
        state = last.snapshot
        return results
    }

    /// 等排着的键都算完，再取回结果。
    func drain() -> [Result] {
        if pending > 0 { queue.sync {} }
        return takeResults()
    }

    /// 启动 Rime、切方案、预热都在后台做，键盘先弹出来；完成后在主线程回调（能不能用、词库来源）。
    /// 之后交给队列的按键会排在它后面。
    func prepare(schema: String, useShared: Bool, completion: @escaping (Bool, String?) -> Void) {
        queue.async { [inner] in
            let ok = inner.prepare(schema: schema, useShared: useShared)
            let source = inner.source
            DispatchQueue.main.async { completion(ok, source) }
        }
    }

    /// 键盘收起：在队列上关掉 Rime 会话，放开 App Group 里用户词库的文件锁（见 RimeEngine.closeSession）。
    /// 用 performExpiringActivity 向系统要一点时间，关完再让扩展被挂起，不然挂起时还锁着就会被杀。
    func closeSession() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [inner] in
            inner.closeSession()
            done.signal()
        }
        state = Snapshot()
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Close Rime user dictionary") { expired in
            guard !expired else { return }
            _ = done.wait(timeout: .now() + 3)
        }
    }

    func updatePhrases(_ entries: [(text: String, code: String)]) {
        queue.async { [inner] in inner.updatePhrases(entries) }
    }

    // MARK: - 同步（先处理完排着的键）

    /// 没在组字、也没有排着的键时，删除、选词、上屏、清空都不用碰引擎，直接返回，不等队列。
    /// 冷启动时 Rime 还在后台启动，这时按删除、标点、切中英，连键盘弹出、收起时的清空，都会被 queue.sync 卡住，直到引擎准备好。
    private var idle: Bool { pending == 0 && state.composition.isEmpty }

    func input(_ letter: String) -> String? { run { $0.input(letter) } }

    func backspace() -> Bool {
        guard !idle else { return false }
        return run { $0.backspace() }
    }

    func select(_ index: Int) -> String? {
        guard !idle else { return nil }
        return run { $0.select(index) }
    }

    func deleteCandidate(_ index: Int) -> Bool {
        guard !idle else { return false }
        return run { $0.deleteCandidate(index) }
    }

    func commitComposition() -> String? {
        guard !idle else { return nil }
        return run { $0.commitComposition() }
    }

    func reset() {
        guard idle else {
            run { $0.reset() }
            return
        }
        // 排在后面清一下就行，主线程不等。
        state = Snapshot()
        queue.async { [inner] in inner.reset() }
    }

    func replaceInput(_ raw: String, keeping selections: [InputSelection]) { run { $0.replaceInput(raw, keeping: selections) } }

    func loadMoreCandidates() {
        // 还有键没算完：候选马上就要换，不用补。
        guard pending == 0 else { return }
        run { $0.loadMoreCandidates() }
    }

    private func run<T>(_ body: (RimeEngine) -> T) -> T {
        if pending > 0 { willSync?() }
        let (value, snapshot) = queue.sync { (body(inner), Self.snapshot(of: inner)) }
        state = snapshot
        return value
    }

    private static func snapshot(of engine: RimeEngine) -> Snapshot {
        Snapshot(composition: engine.composition, candidates: engine.candidates, rawInput: engine.rawInput,
                 selections: engine.selections, lastCorrection: engine.lastCorrection,
                 pendingCorrection: engine.pendingCorrection)
    }
}
