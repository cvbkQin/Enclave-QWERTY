import Foundation
import MetricKit

/// 内测版的崩溃记录：用系统的 MetricKit 收 App 和键盘扩展的崩溃、卡死、被系统杀掉等诊断，
/// 原样存进 App Group 的 Diagnostics 文件夹，由 App 的「诊断与反馈」页读出来。只存本机，不上传、不接第三方。
/// 系统一般在下次启动后（最晚约一天）才把上一次的诊断交过来。
final class CrashLog: NSObject, MXMetricManagerSubscriber {
    struct Entry: Codable, Identifiable {
        enum Kind: String, Codable { case crash, hang, cpu, disk, launch }

        var id: String { file }
        /// app 或 keyboard。
        var source: String
        var kind: Kind
        var date: Date
        var appVersion: String
        /// 崩溃的异常类型 / 信号，卡死的时长等一行摘要。
        var summary: String
        /// 完整诊断（MetricKit 的 JSON）在 Diagnostics 里的文件名。
        var file: String
    }

    static let shared = CrashLog()
    /// 最多留这么多条，旧的删掉。
    private static let limit = 50
    private static let indexName = "index.json"

    private var source = "app"
    private var started = false
    private let queue = DispatchQueue(label: "enclave.crashlog")

    /// App 和键盘启动时各调一次；只有内测版收。
    func start(source: String) {
        guard BuiltinAPI.isInternalBuild, !started else { return }
        started = true
        self.source = source
        MXMetricManager.shared.add(self)
        // 订阅之前已经到了的也收一遍。
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty, let folder = Self.folder else { return }
        let source = source
        queue.async {
            var entries = Self.entries()
            let known = Set(entries.map(\.file))
            for payload in payloads {
                let data = payload.jsonRepresentation()
                let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
                for (index, (kind, summary, version)) in Self.items(payload).enumerated() {
                    // 同一包重复送来时文件名一样，不重复记。
                    let file = "\(source)-\(kind.rawValue)-\(stamp)-\(index).json"
                    guard !known.contains(file) else { continue }
                    try? data.write(to: folder.appendingPathComponent(file), options: .atomic)
                    entries.append(Entry(source: source, kind: kind, date: payload.timeStampEnd,
                                         appVersion: version, summary: summary, file: file))
                }
            }
            Self.save(entries)
        }
    }

    /// 一个包里可能有好几条：每条崩溃、卡死、CPU / 写盘超限、启动过慢各记一行。
    private static func items(_ payload: MXDiagnosticPayload) -> [(Entry.Kind, String, String)] {
        var out: [(Entry.Kind, String, String)] = []
        for d in payload.crashDiagnostics ?? [] {
            let parts = [d.exceptionType.map { "exception \($0)" }, d.signal.map { "signal \($0)" },
                         d.terminationReason].compactMap { $0 }
            out.append((.crash, parts.isEmpty ? "崩溃" : parts.joined(separator: " · "), d.metaData.applicationBuildVersion))
        }
        for d in payload.hangDiagnostics ?? [] {
            out.append((.hang, "卡住 \(Int(d.hangDuration.converted(to: .seconds).value)) 秒", d.metaData.applicationBuildVersion))
        }
        for d in payload.cpuExceptionDiagnostics ?? [] {
            out.append((.cpu, "CPU 超限 \(Int(d.totalCPUTime.converted(to: .seconds).value)) 秒", d.metaData.applicationBuildVersion))
        }
        for d in payload.diskWriteExceptionDiagnostics ?? [] {
            out.append((.disk, "写盘超限 \(Int(d.totalWritesCaused.converted(to: .megabytes).value)) MB", d.metaData.applicationBuildVersion))
        }
        for d in payload.appLaunchDiagnostics ?? [] {
            out.append((.launch, "启动 \(String(format: "%.1f", d.launchDuration.converted(to: .seconds).value)) 秒", d.metaData.applicationBuildVersion))
        }
        return out
    }

    // MARK: 读写

    static var folder: URL? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let url = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 新的在前。
    static func entries() -> [Entry] {
        guard let url = folder?.appendingPathComponent(indexName), let data = try? Data(contentsOf: url) else { return [] }
        let entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        return entries.sorted { $0.date > $1.date }
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

    private static func save(_ entries: [Entry]) {
        guard let folder else { return }
        let sorted = entries.sorted { $0.date > $1.date }
        let kept = Array(sorted.prefix(limit))
        for old in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old.file))
        }
        if let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: folder.appendingPathComponent(indexName), options: .atomic)
        }
    }
}
