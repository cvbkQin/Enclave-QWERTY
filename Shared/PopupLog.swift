import Foundation

/// 键盘每次弹出记一条：是冷启动还是热启动、各段耗时、内存、上次收起后隔了多久。
/// 只在开发版、内测、公测包里记（正式版不记），App 的「测试工具 › 弹出记录」里看、一键复制。用来查「呼出卡」。
/// 存在共享存储里，键盘要开了完全访问才写得进去。
struct PopupRecord: Codable, Identifiable {
    var id = UUID()
    var at: Date
    /// 这次是这个键盘进程的第几次弹出（1 = 冷启动）。
    var nth: Int
    /// 冷启动：从进程启动到 viewDidLoad 开始（系统拉起扩展、加载代码的时间）。热启动为 nil。
    var processToLoad: Double?
    /// 控制器建出来到 viewDidLoad。
    var initToLoad: Double
    /// viewDidLoad 里建视图（第一次装 SwiftUI 宿主）。
    var load: Double
    /// viewWillAppear 总共，和其中装宿主、reload（读设置、会话、选引擎）、最后排版三段。
    var willAppear: Double
    var willHost: Double
    var willReload: Double
    var willLayout: Double
    /// 从 viewDidLoad 开始到 viewDidAppear（含系统的弹出动画，约 250–350 毫秒）。
    var loadToAppear: Double
    /// viewDidAppear 里同步做的事：剪贴板 / 帮回检测、常用词。
    var didClipboard: Double
    var didCommonWords: Double
    /// 拼音引擎这次弹出后多久准备好（从 viewDidLoad 开始算；冷启动才有意义，热启动通常很快）。
    var engineReady: Double?
    var memoryMB: Double?
    /// 上次收起到这次弹出隔了几秒；上次收起时的进程和这次是不是同一个；上次收起是怎么收尾的。
    var sinceHide: Double?
    var sameProcess: Bool?
    var lastCleanup: String?
    var nineKey: Bool

    /// 复制出去的一行。
    var line: String {
        func ms(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "-" }
        let time = PopupLog.timeFormatter.string(from: at)
        var parts = ["\(time) #\(nth)\(nth == 1 ? " 冷" : " 热")"]
        if let processToLoad { parts.append("进程→load \(ms(processToLoad))") }
        parts.append("建→load \(ms(initToLoad))")
        parts.append("load \(ms(load))")
        parts.append("will \(ms(willAppear))(宿主\(ms(willHost)) reload\(ms(willReload)) 排版\(ms(willLayout)))")
        parts.append("load→出现 \(ms(loadToAppear))")
        parts.append("剪贴板 \(ms(didClipboard)) 常用词 \(ms(didCommonWords))")
        parts.append("引擎 \(ms(engineReady))")
        parts.append("内存 \(memoryMB.map { String(format: "%.0f", $0) } ?? "-")MB")
        if let sinceHide {
            let process = sameProcess == true ? "同进程" : "换了进程"
            parts.append("距收起 \(String(format: "%.1f", sinceHide))s \(process) 收尾:\(lastCleanup ?? "-")")
        }
        parts.append(nineKey ? "九宫格" : "全键盘")
        return parts.joined(separator: " · ")
    }
}

enum PopupLog {
    private static let recordsKey = "debug.popupLog"
    private static let hideKey = "debug.popupLastHide"
    private static let keep = 60

    /// 正式版不记。
    static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return BuiltinAPI.isDevBuild || BuiltinAPI.isInternalBuild || BuiltinAPI.isPublicBuild
        #endif
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    static func load() -> [PopupRecord] {
        guard let data = SharedStorage.defaults.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([PopupRecord].self, from: data) else { return [] }
        return records
    }

    static func append(_ record: PopupRecord) {
        guard enabled else { return }
        let records = Array((load() + [record]).suffix(keep))
        if let data = try? JSONEncoder().encode(records) { SharedStorage.defaults.set(data, forKey: recordsKey) }
    }

    static func clear() {
        SharedStorage.defaults.removeObject(forKey: recordsKey)
    }

    // MARK: - 上次收起

    struct Hide: Codable {
        var at: Date
        var pid: Int32
        var cleanup: String
    }

    static func noteHide(cleanup: String) {
        guard enabled else { return }
        let hide = Hide(at: Date(), pid: ProcessInfo.processInfo.processIdentifier, cleanup: cleanup)
        if let data = try? JSONEncoder().encode(hide) { SharedStorage.defaults.set(data, forKey: hideKey) }
    }

    static var lastHide: Hide? {
        guard let data = SharedStorage.defaults.data(forKey: hideKey) else { return nil }
        return try? JSONDecoder().decode(Hide.self, from: data)
    }

    /// 复制出去的全文：最近的在前，开头一行汇总。
    static func report(_ records: [PopupRecord]) -> String {
        let cold = records.filter { $0.nth == 1 }
        let warm = records.filter { $0.nth > 1 }
        func median(_ values: [Double]) -> String {
            guard !values.isEmpty else { return "-" }
            let sorted = values.sorted()
            return String(format: "%.0f", sorted[sorted.count / 2])
        }
        let header = "弹出 \(records.count) 次：冷启动 \(cold.count)（load→出现 中位 \(median(cold.map(\.loadToAppear))) ms，"
            + "进程→load 中位 \(median(cold.compactMap(\.processToLoad))) ms），热启动 \(warm.count)（load→出现 中位 \(median(warm.map(\.loadToAppear))) ms）"
        let version = (Bundle.main.object(forInfoDictionaryKey: "EnclaveDevLabel") as? String) ?? ""
        return ([header, "版本 \(version)"] + records.reversed().map(\.line)).joined(separator: "\n")
    }
}
