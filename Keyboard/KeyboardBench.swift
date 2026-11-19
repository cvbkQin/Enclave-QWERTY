#if DEBUG
import Foundation
import os
import QuartzCore

/// 打字性能基准（debug 选项 bench，只在 Debug 编译里有）：模拟器上由 scripts/bench/run-bench.sh 拉起。
/// 全键盘拼音照 memtest 那组整句一个字母一个字母地打，每个键走和手指按键同一条路：
/// perform(.letter) → feedEngine → 后台引擎 inputLater → applyEngineResults（上屏、纠错、候选菜单、刷新候选）
/// → 下一轮主循环界面画完时 TypingStats.record。耗时就取 record 收到的那个数（「拼音词库」页统计的也是它）：
/// - key：从交给引擎到界面按新候选画完；
/// - engine：其中引擎自己算的时间。
/// 不含系统把触摸送到键盘那一段（KeyTouchView 之前）。一个键的结果回来、界面画完，才按下一个键。
/// 共 3 遍，第一遍是热身（第一句单独记冷启动耗时），后两遍算中位数、P95。内存每个键看一次，记峰值。
/// 输入框里和真打字一样只有带下划线的拼音；每句打完清掉，不选词、不上屏、不学词，几次跑的条件一样。
/// 结果：系统日志一行「ENCLAVE_BENCH_RESULT {json}」（脚本从 log stream 里取，不要求完全访问），
/// 有共享容器时另写 Library/Diagnostics/bench.json。
extension KeyboardModel {
    private static var benchStarted = false
    private static var bench: BenchRun?
    private static var benchWatchdog: DispatchWorkItem?
    private static let benchLog = Logger(subsystem: "app.enclave.keyboard", category: "Bench")

    static let benchSentences = [
        "woxiangqugongsishangban", "jintiantianqizhenhao", "womenyiqiquchifanba", "zhegewentiwomenmingtianzaitaolun",
        "tazuotianwanshangmeiyouhuijia", "qingbangwochayixiahuochepiao", "zhejianshiqingbiwoxiangdeyaofuza",
        "nikanjianwodeshoujilema", "xiawusandianzaihuiyishikaihui", "zhegexiangmudejindubijiaoman",
    ]
    private static let benchRounds = 3

    /// 每个进程只跑一次；等拼音引擎准备好再开始（冷启动时 Rime 在后台加载），最多等 60 秒。
    func startBenchmark(waited: Int = 0) {
        guard !Self.benchStarted else { return }
        guard pinyinReady, engine === QueuedEngine.shared, chineseMode, !showsNineKey, layer == .letters else {
            if waited >= 120 { return benchFailed("engine not ready") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startBenchmark(waited: waited + 1) }
            return
        }
        Self.benchStarted = true
        Self.bench = BenchRun(startMB: TypingStats.footprintMB() ?? -1)
        TypingStats.benchObserver = { [weak self] total, engine in self?.benchKeyShown(totalMs: total, engineMs: engine) }
        // 先等界面稳定一下再开始。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.benchNextKey() }
    }

    /// 按下一个字母键。
    private func benchNextKey() {
        guard var run = Self.bench else { return }
        guard run.round < Self.benchRounds else { return finishBenchmark(run) }
        let sentence = Array(Self.benchSentences[run.sentence])
        if run.letter == 0 { run.sentenceStart = CACurrentMediaTime() }
        Self.bench = run
        if shift != .off { shift = .off }
        // 3 秒还没等到这个键的结果：多半引擎卡住或键盘被收起了，报错收尾，不让脚本干等。
        let watchdog = DispatchWorkItem { [weak self] in self?.benchFailed("key timeout") }
        Self.benchWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: watchdog)
        keyEventTime = CACurrentMediaTime()
        perform(.letter(String(sentence[run.letter])))
    }

    /// 这个键的候选已经画出来了（TypingStats.record 交过来的耗时）。
    private func benchKeyShown(totalMs: Double, engineMs: Double) {
        guard var run = Self.bench else { return }
        Self.benchWatchdog?.cancel()
        if let memory = TypingStats.footprintMB() { run.peakMB = max(run.peakMB, memory) }
        if run.round > 0 {
            run.keyMs.append(totalMs)
            run.engineMs.append(engineMs)
        }
        run.letter += 1
        if run.letter == Self.benchSentences[run.sentence].count {
            if run.round == 0 && run.sentence == 0 { run.coldSentenceMs = (CACurrentMediaTime() - run.sentenceStart) * 1000 }
            if run.round == Self.benchRounds - 1 { run.firstCandidates.append(candidates.first ?? "") }
            // 整句清掉：不选词、不上屏，词库不学这句，下一次跑条件一样。
            QueuedEngine.shared.reset()
            syncEngine()
            run.letter = 0
            run.sentence += 1
            if run.sentence == Self.benchSentences.count {
                run.sentence = 0
                run.round += 1
            }
        }
        Self.bench = run
        DispatchQueue.main.async { [weak self] in self?.benchNextKey() }
    }

    private func benchFailed(_ reason: String) {
        Self.benchStarted = true
        Self.bench = nil
        TypingStats.benchObserver = nil
        QueuedEngine.shared.reset()
        syncEngine()
        Self.benchLog.notice("ENCLAVE_BENCH_RESULT {\"error\":\"\(reason, privacy: .public)\"}")
    }

    private func finishBenchmark(_ run: BenchRun) {
        Self.bench = nil
        TypingStats.benchObserver = nil
        let keys = run.keyMs.sorted(), engines = run.engineMs.sorted()
        let info = Bundle.main.infoDictionary ?? [:]
        let report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "device": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device",
            "layout": "qwerty",
            "model": TypingStats.modelInUse,
            "keys": keys.count,
            "keyMedianMs": Self.round2(Self.percentile(keys, 0.5)),
            "keyP95Ms": Self.round2(Self.percentile(keys, 0.95)),
            "keyMaxMs": Self.round2(keys.last ?? 0),
            "engineMedianMs": Self.round2(Self.percentile(engines, 0.5)),
            "engineP95Ms": Self.round2(Self.percentile(engines, 0.95)),
            "coldSentenceMs": Self.round2(run.coldSentenceMs),
            "memStartMB": Self.round2(run.startMB),
            "memPeakMB": Self.round2(run.peakMB),
            "memEndMB": Self.round2(TypingStats.footprintMB() ?? -1),
            "firstCandidates": run.firstCandidates,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        Self.benchLog.notice("ENCLAVE_BENCH_RESULT \(line, privacy: .public)")
        if let group = SharedStorage.appGroupID.flatMap({ FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }) {
            let out = group.appendingPathComponent("Library/Diagnostics", isDirectory: true)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try? data.write(to: out.appendingPathComponent("bench.json"))
        }
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// 基准跑到哪了、记下的数。
struct BenchRun {
    var round = 0
    var sentence = 0
    var letter = 0
    var sentenceStart: CFTimeInterval = 0
    var keyMs: [Double] = []
    var engineMs: [Double] = []
    var coldSentenceMs: Double = 0
    var startMB: Double
    var peakMB: Double
    var firstCandidates: [String] = []

    init(startMB: Double) {
        self.startMB = startMB
        peakMB = startMB
    }
}
#endif
