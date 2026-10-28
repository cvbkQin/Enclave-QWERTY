import Foundation
import MetricKit

/// 内测版的崩溃记录（诊断与反馈 DF1–DF5）：用系统的 MetricKit 收 App 和键盘扩展的闪退、内存超限被系统关闭、卡住超过 2 秒，
/// 存进 App Group 的 Diagnostics 文件夹，由 App 的「诊断与反馈」页读出来。只存本机，不上传、不接第三方、不含任何输入内容。
/// 系统一般在下次启动后（最晚约一天）才把上一次的诊断交过来；最多留 50 条、30 天。
final class CrashLog: NSObject, MXMetricManagerSubscriber {
    struct Entry: Codable, Identifiable, Equatable {
        enum Kind: String, Codable { case crash, memory, hang }

        var id: String { file }
        /// app 或 keyboard。
        var source: String
        var kind: Kind
        var date: Date
        /// 出问题那次的版本，例如「0.90 (90)」。
        var version: String
        var os: String?
        var device: String?
        /// 当时的界面（最后一次 mark 的），例如「抽屉展开 · 分词面板」。
        var screen: String?
        /// 技术摘要：异常类型、信号、终止原因、卡住时长。
        var summary: String
        /// 完整诊断（MetricKit 的 JSON）在 Diagnostics 里的文件名。
        var file: String

        var isKeyboard: Bool { source == "keyboard" }
    }

    static let shared = CrashLog()
    private static let limit = 50
    private static let maxAge: TimeInterval = 30 * 24 * 3600
    private static let indexName = "index.json"
    /// 卡住不到 2 秒的不记。
    private static let minHang: Double = 2

    private var source = "app"
    private var started = false
    /// 上一次运行最后停在的界面：这次启动收到的诊断多半是上一次留下的。
    private var lastScreen: String?
    private let queue = DispatchQueue(label: "enclave.crashlog")

    static var isEnabled: Bool { BuiltinAPI.isInternalBuild }

    /// App 和键盘启动时各调一次；只有内测版收。
    func start(source: String) {
        guard Self.isEnabled, !started else { return }
        started = true
        self.source = source
        lastScreen = SharedStorage.defaults.string(forKey: Self.screenKey(source))
        MXMetricManager.shared.add(self)
        // 订阅之前已经到了的也收一遍。
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    /// 记下现在在哪个界面，出问题时带上。只记界面名，不记文字。
    static func mark(_ screen: String, source: String) {
        guard isEnabled else { return }
        SharedStorage.defaults.set(screen, forKey: screenKey(source))
    }

    private static func screenKey(_ source: String) -> String { "diag.screen.\(source)" }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty, Self.folder != nil else { return }
        let source = source, screen = lastScreen
        queue.async {
            Self.add(payloads.flatMap { Self.items($0, source: source, screen: screen) })
        }
    }

    /// 内存超限被系统关闭多半不出诊断，只在每天的统计里有次数。
    func didReceive(_ payloads: [MXMetricPayload]) {
        guard Self.folder != nil else { return }
        let source = source, screen = lastScreen
        queue.async {
            var found: [(Entry, Data)] = []
            for payload in payloads {
                guard let exits = payload.applicationExitMetrics else { continue }
                let count = exits.foregroundExitData.cumulativeMemoryResourceLimitExitCount
                    + exits.backgroundExitData.cumulativeMemoryResourceLimitExitCount
                guard count > 0 else { continue }
                let meta = payload.metaData
                let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
                let entry = Entry(source: source, kind: .memory, date: payload.timeStampEnd,
                                  version: Self.version(build: meta?.applicationBuildVersion ?? payload.latestApplicationVersion),
                                  os: meta?.osVersion, device: meta?.deviceType, screen: screen,
                                  summary: "MXAppExitMetric · memory resource limit exits: \(count)",
                                  file: "\(source)-memory-\(stamp).json")
                found.append((entry, payload.jsonRepresentation()))
            }
            Self.add(found)
        }
    }

    private static func items(_ payload: MXDiagnosticPayload, source: String, screen: String?) -> [(Entry, Data)] {
        var out: [(Entry, Data)] = []
        let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
        func entry(_ kind: Entry.Kind, _ meta: MXMetaData, _ summary: String, _ index: Int) -> Entry {
            Entry(source: source, kind: kind, date: payload.timeStampEnd, version: version(build: meta.applicationBuildVersion),
                  os: meta.osVersion, device: meta.deviceType, screen: screen, summary: summary,
                  file: "\(source)-\(kind.rawValue)-\(stamp)-\(index).json")
        }
        for (index, d) in (payload.crashDiagnostics ?? []).enumerated() {
            let reason = d.terminationReason ?? ""
            var lines = ["MXCrashDiagnostic · " + [d.exceptionType.map { "exceptionType \($0)" }, d.exceptionCode.map { "code \($0)" },
                                                   d.signal.map { "signal \($0)" }].compactMap { $0 }.joined(separator: " · ")]
            if !reason.isEmpty { lines.append("terminationReason: \(reason)") }
            lines += frames(d.callStackTree.jsonRepresentation())
            // 被 jetsam 杀掉的算内存超限。
            let kind: Entry.Kind = reason.localizedCaseInsensitiveContains("jetsam") ? .memory : .crash
            out.append((entry(kind, d.metaData, lines.joined(separator: "\n"), index), d.jsonRepresentation()))
        }
        for (index, d) in (payload.hangDiagnostics ?? []).enumerated() {
            let seconds = d.hangDuration.converted(to: .seconds).value
            guard seconds >= minHang else { continue }
            let lines = [String(format: "MXHangDiagnostic · hangDuration %.1f s", seconds)] + frames(d.callStackTree.jsonRepresentation())
            out.append((entry(.hang, d.metaData, lines.joined(separator: "\n"), 100 + index), d.jsonRepresentation()))
        }
        return out
    }

    /// 出事那条线程最上面几帧：「模块 + 偏移」（没有符号）。
    static func frames(_ json: Data, limit: Int = 5) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return [] }
        let stack = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        var out: [String] = []
        while let current = frame, out.count < limit {
            let binary = current["binaryName"] as? String ?? "?"
            let offset = current["offsetIntoBinaryTextSegment"] as? Int ?? 0
            out.append("\(binary) + 0x\(String(offset, radix: 16))")
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        return out
    }

    /// 只有 build 号；和现在这版一样就写成「0.90 (90)」。
    private static func version(build: String) -> String {
        let info = Bundle.main.infoDictionary
        let current = info?["CFBundleVersion"] as? String
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        return build == current ? "\(short) (\(build))" : "build \(build)"
    }

    // MARK: 读写

    static var folder: URL? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let url = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 新的在前，过了 30 天的不算。
    static func entries() -> [Entry] {
        guard let url = folder?.appendingPathComponent(indexName), let data = try? Data(contentsOf: url) else { return [] }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let all = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        return all.filter { $0.date > cutoff }.sorted { $0.date > $1.date }
    }

    /// 一条的完整诊断 JSON（反馈时附上）。
    static func detail(_ entry: Entry) -> Data? {
        guard let url = folder?.appendingPathComponent(entry.file) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func clear() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    #if DEBUG
    /// 调试用：三种各一条假记录（-diag sample）。
    static func addSamples() {
        let now = Date()
        let samples: [(String, Entry.Kind, TimeInterval, String, String)] = [
            ("keyboard", .crash, -600, "抽屉展开 · 分词面板", "MXCrashDiagnostic · exceptionType 1 · signal 11\nEnclaveKeyboard + 0x1a2b3c"),
            ("keyboard", .memory, -90000, "识意处理中", "MXCrashDiagnostic · terminationReason: Namespace JETSAM"),
            ("app", .hang, -200000, "设置 · keyboard", "MXHangDiagnostic · hangDuration 3.4 s\nEnclave + 0x4d5e6f"),
        ]
        add(samples.map { source, kind, offset, screen, summary in
            let date = now.addingTimeInterval(offset)
            let entry = Entry(source: source, kind: kind, date: date, version: version(build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""),
                              os: "iOS 18.0", device: "iPhone16,1", screen: screen, summary: summary,
                              file: "sample-\(kind.rawValue)-\(Int(date.timeIntervalSince1970)).json")
            return (entry, Data("{\"sample\":true}".utf8))
        })
    }
    #endif

    private static func add(_ found: [(Entry, Data)]) {
        guard !found.isEmpty, let folder else { return }
        var current = entries()
        let known = Set(current.map(\.file))
        for (entry, data) in found where !known.contains(entry.file) {
            try? data.write(to: folder.appendingPathComponent(entry.file), options: .atomic)
            current.append(entry)
        }
        let kept = Array(current.sorted { $0.date > $1.date }.prefix(limit))
        let keptFiles = Set(kept.map(\.file))
        // 不再留的诊断文件一起删掉。
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where name != indexName && !keptFiles.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        if let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: folder.appendingPathComponent(indexName), options: .atomic)
        }
    }
}
