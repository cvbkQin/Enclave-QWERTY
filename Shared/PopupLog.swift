import Foundation
import QuartzCore

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
    /// 键盘进程主线程闲了（或被系统挂起）多久后醒来，醒来到系统建出控制器用了多久。
    /// 醒来→建 很小说明我们这边一醒就开始了，空白的时间花在系统把弹出交给我们之前。
    var idleBeforeWake: Double?
    var wakeToInit: Double?
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

    var isCold: Bool { nth == 1 }

    /// 我们这边一共用了多久（毫秒）：冷启动从进程启动算，热启动从进程被叫醒算（没记到醒的时刻就从控制器建出来算），到键盘显示出来。
    var total: Double {
        if let processToLoad { return processToLoad + loadToAppear }
        return (wakeToInit ?? 0) + initToLoad + loadToAppear
    }

    /// 明显慢：热启动超过 150 毫秒，冷启动超过 800 毫秒（平时热启动 50–70、冷启动 300–400）。
    var isSlow: Bool { total >= (isCold ? PopupLog.slowCold : PopupLog.slowWarm) }

    private static func ms(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "-" }

    /// 第一行：什么时候、冷 / 热启动、一共多久、慢不慢。
    var title: String {
        let time = PopupLog.timeFormatter.string(from: at)
        let kind = isCold ? "冷启动（键盘进程重新启动）" : "热启动（第 \(nth) 次弹出）"
        return "\(time) · \(kind) · 共 \(Self.ms(total)) 毫秒\(isSlow ? " · 慢" : "")"
    }

    /// 下面几行：每一段用了多久，用大白话写。
    var details: [String] {
        var lines: [String] = []
        if let processToLoad {
            lines.append("系统启动键盘进程到开始建键盘：\(Self.ms(processToLoad)) 毫秒")
        } else if let wakeToInit {
            lines.append("键盘被叫醒（之前闲了 \(String(format: "%.1f", (idleBeforeWake ?? 0) / 1000)) 秒）到开始建键盘：\(Self.ms(wakeToInit + initToLoad)) 毫秒")
        } else {
            lines.append("开始建键盘前的准备：\(Self.ms(initToLoad)) 毫秒")
        }
        lines.append("建键盘到显示出来：\(Self.ms(loadToAppear)) 毫秒（其中读设置 \(Self.ms(willReload))、排版 \(Self.ms(willLayout))）")
        lines.append("显示后：剪贴板和帮回检测 \(Self.ms(didClipboard)) 毫秒，拼音能打 \(Self.ms(engineReady)) 毫秒")
        var last = "内存 \(memoryMB.map { String(format: "%.0f", $0) } ?? "-") MB · \(nineKey ? "九宫格" : "全键盘")"
        if let sinceHide {
            last += " · 距上次收起 \(Self.duration(sinceHide))"
            if sameProcess == false { last += "，期间键盘进程被系统关掉了" }
        }
        lines.append(last)
        return lines
    }

    private static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.1f 秒", seconds) }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟" }
        return String(format: "%.1f 小时", seconds / 3600)
    }

    /// 复制出去的一条：标题加缩进的明细。
    var text: String { ([title] + details.map { "  " + $0 }).joined(separator: "\n") }
}

enum PopupLog {
    private static let recordsKey = "debug.popupLog"
    /// 冷启动和明显慢的那几次另存一份，不跟着最近的记录被挤掉。
    private static let keptKey = "debug.popupLogKept"
    private static let hideKey = "debug.popupLastHide"
    private static let keep = 60
    private static let keepSpecial = 40
    static let slowWarm: Double = 150
    static let slowCold: Double = 800

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

    /// 最近的（旧的在前）。
    static func load() -> [PopupRecord] { read(recordsKey) }

    /// 冷启动和慢的（旧的在前），最多 40 条。
    static func loadKept() -> [PopupRecord] { read(keptKey) }

    private static func read(_ key: String) -> [PopupRecord] {
        guard let data = SharedStorage.defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([PopupRecord].self, from: data) else { return [] }
        return records
    }

    private static func write(_ records: [PopupRecord], _ key: String) {
        if let data = try? JSONEncoder().encode(records) { SharedStorage.defaults.set(data, forKey: key) }
    }

    static func append(_ record: PopupRecord) {
        guard enabled else { return }
        write(Array((load() + [record]).suffix(keep)), recordsKey)
        if record.isCold || record.isSlow {
            write(Array((loadKept() + [record]).suffix(keepSpecial)), keptKey)
        }
    }

    /// 只清最近的；冷启动和慢的要另外点「清空保留的」。
    static func clear() {
        SharedStorage.defaults.removeObject(forKey: recordsKey)
    }

    static func clearKept() {
        SharedStorage.defaults.removeObject(forKey: keptKey)
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

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// 一句话汇总：热启动、冷启动一般多久，慢的几次。
    static func summary(_ records: [PopupRecord]) -> String {
        let cold = records.filter(\.isCold)
        let warm = records.filter { !$0.isCold }
        func ms(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "-" }
        var parts = ["最近 \(records.count) 次弹出"]
        if !warm.isEmpty { parts.append("热启动 \(warm.count) 次，一般 \(ms(median(warm.map(\.total)))) 毫秒") }
        if !cold.isEmpty { parts.append("冷启动 \(cold.count) 次，一般 \(ms(median(cold.map(\.total)))) 毫秒") }
        let slow = records.filter(\.isSlow).count
        parts.append(slow == 0 ? "没有明显慢的" : "明显慢的 \(slow) 次")
        return parts.joined(separator: "；") + "。"
    }

    /// 几个词是什么意思，复制出去和卡片上都带着。
    static let legend = """
    热启动：键盘进程还在，系统直接叫醒它，一般 50–100 毫秒。
    冷启动：键盘进程已经被系统关掉，要重新启动，一般 300–400 毫秒。
    「共 N 毫秒」只算键盘自己用的时间；在这之前系统处理弹出用的时间记不到。
    明显慢：热启动超过 \(Int(slowWarm)) 毫秒、冷启动超过 \(Int(slowCold)) 毫秒，标「慢」，和冷启动一起另外保留。
    """

    /// 复制出去的全文：汇总、说明、保留的冷启动和慢的、最近的（新的在前）。
    static func report(recent: [PopupRecord], kept: [PopupRecord]) -> String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "EnclaveDevLabel") as? String) ?? ""
        var out = ["飞地输入法 \(version) 弹出记录", summary(recent), "", legend, ""]
        out.append("== 冷启动和明显慢的（一直保留，\(kept.count) 条）==")
        out += kept.reversed().map(\.text)
        out.append("")
        out.append("== 最近的（\(recent.count) 条）==")
        out += recent.reversed().map(\.text)
        return out.joined(separator: "\n")
    }
}

/// 主线程醒来的时刻：主线程 RunLoop 睡了 0.5 秒以上（闲着或整个进程被系统挂起）再醒，记下醒的时刻和睡了多久。
/// 键盘弹出时拿控制器建出来的时刻减它，看我们一醒是不是马上就开始建键盘。
enum MainWake {
    private(set) static var lastWake: CFTimeInterval?
    private(set) static var lastIdle: CFTimeInterval = 0
    private static var sleepStart: CFTimeInterval = 0
    private static var installed = false

    static func install() {
        guard PopupLog.enabled, !installed else { return }
        installed = true
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity([.beforeWaiting, .afterWaiting]).rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .beforeWaiting {
                sleepStart = now
            } else if sleepStart > 0, now - sleepStart > 0.5 {
                lastWake = now
                lastIdle = now - sleepStart
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
