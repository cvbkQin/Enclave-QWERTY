#if DEBUG
import Foundation
import os
import QuartzCore

/// 打字性能基准（debug 选项 bench，只在开发版里有）：模拟器上由 scripts/bench/run-bench.sh 拉起。
/// 全键盘拼音照 memtest 那组整句一个字母一个字母地打，每个键记：
/// - engine：引擎算候选的时间（QueuedEngine.input，和真打字同一个引擎、同一个队列）；
/// - key：引擎 + 把候选交给界面（syncEngine）+ 键盘界面按新候选排完（layoutIfNeeded），接近手机上「按下到候选出来」。
/// 键与键之间让出一轮主循环，界面照常画。共 3 遍，第一遍是热身（第一句单独记冷启动耗时），后两遍算中位数、P95。
/// 内存每个键看一次，记峰值。不改按键路径；输入框里和真打字一样只有带下划线的拼音，每句打完清掉，不上屏。
/// 结果：系统日志一行「ENCLAVE_BENCH_RESULT {json}」（脚本从 log stream 里取，不要求完全访问），
/// 有共享容器时另写 Library/Diagnostics/bench.json。
extension KeyboardModel {
    private static var benchStarted = false
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
        guard pinyinReady, engine === QueuedEngine.shared, chineseMode else {
            if waited >= 120 {
                Self.benchStarted = true
                Self.benchLog.notice("ENCLAVE_BENCH_RESULT {\"error\":\"engine not ready\"}")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startBenchmark(waited: waited + 1) }
            return
        }
        Self.benchStarted = true
        let run = BenchRun(startMB: TypingStats.footprintMB() ?? -1)
        // 先等界面稳定一下再开始。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.benchStep(run) }
    }

    private func benchStep(_ state: BenchRun) {
        var run = state
        let sentences = Self.benchSentences
        guard run.round < Self.benchRounds else { return finishBenchmark(run) }
        let sentence = Array(sentences[run.sentence])
        let engine = QueuedEngine.shared
        if run.letter == 0 {
            engine.reset()
            run.sentenceStart = CACurrentMediaTime()
        }
        let letter = String(sentence[run.letter])
        let start = CACurrentMediaTime()
        _ = engine.input(letter)
        let engineDone = CACurrentMediaTime()
        syncEngine()
        controller?.view.layoutIfNeeded()
        let done = CACurrentMediaTime()
        if let memory = TypingStats.footprintMB() { run.peakMB = max(run.peakMB, memory) }
        if run.round > 0 {
            run.keyMs.append((done - start) * 1000)
            run.engineMs.append((engineDone - start) * 1000)
        }
        run.letter += 1
        if run.letter == sentence.count {
            if run.round == 0 && run.sentence == 0 { run.coldSentenceMs = (done - run.sentenceStart) * 1000 }
            if run.round == Self.benchRounds - 1 { run.firstCandidates.append(engine.candidates.first ?? "") }
            engine.reset()
            syncEngine()
            run.letter = 0
            run.sentence += 1
            if run.sentence == sentences.count {
                run.sentence = 0
                run.round += 1
            }
        }
        let next = run
        DispatchQueue.main.async { [weak self] in self?.benchStep(next) }
    }

    private func finishBenchmark(_ run: BenchRun) {
        let keys = run.keyMs.sorted(), engines = run.engineMs.sorted()
        let info = Bundle.main.infoDictionary ?? [:]
        let report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "device": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device",
            "layout": showsNineKey ? "nine" : "qwerty",
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
    var peakMB: Double = 0
    var firstCandidates: [String] = []

    init(startMB: Double) {
        self.startMB = startMB
        peakMB = startMB
    }
}
#endif
