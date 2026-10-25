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
    }

    /// 后台算完的一个按键。
    struct Result {
        var commit: String?
        var snapshot: Snapshot
        /// 交给队列的时刻，和引擎自己算了多久（秒）。
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

    // MARK: - 后台

    /// 字母、九宫格数字：交给队列就返回，算完后 resultsReady 通知键盘来取。
    func inputLater(_ key: String) {
        pending += 1
        let queuedAt = CACurrentMediaTime()
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

    func updatePhrases(_ entries: [(text: String, code: String)]) {
        queue.async { [inner] in inner.updatePhrases(entries) }
    }

    /// 内存警告：先处理完排着的键，再关掉引擎（正在拼的内容会清掉）。
    func release() { run { $0.release() } }

    // MARK: - 同步（先处理完排着的键）

    func input(_ letter: String) -> String? { run { $0.input(letter) } }
    func backspace() -> Bool { run { $0.backspace() } }
    func select(_ index: Int) -> String? { run { $0.select(index) } }
    func commitComposition() -> String? { run { $0.commitComposition() } }
    func reset() { run { $0.reset() } }
    func replaceInput(_ raw: String) { run { $0.replaceInput(raw) } }

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
        Snapshot(composition: engine.composition, candidates: engine.candidates, rawInput: engine.rawInput)
    }
}
