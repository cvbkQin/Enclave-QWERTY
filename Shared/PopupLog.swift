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
    /// 醒来到控制器建出来这段里，键盘主线程真正醒着干活的合计（毫秒）；其余时间主线程睡着，在等系统把弹出交过来。
    var wakeBusy: Double?
    /// 建键盘到显示出来的途中，键盘进程被系统挂起了多久（毫秒，比如弹出动画时切走、锁屏）。这次的耗时不算数。
    var paused: Double?
    /// 控制器建出来之前 2 秒里，键盘主线程卡住（一次超过 50 毫秒没空）最长的一次和合计。nil 是没开监测（旧记录）。
    var stallLongest: Double?
    var stallTotal: Double?
    /// 上次收起后我们在主线程上做的收尾（关词库、写统计、拆视图）和拆旧键盘各用了多久、离这次弹出多久。
    var lastCleanupMs: Double?
    var lastTeardownMs: Double?
    /// 收尾、拆旧键盘做完时离这次控制器建出来还有多少毫秒（负数是建出来以后才做完）。
    var lastCleanupBefore: Double?
    var lastTeardownBefore: Double?
    /// viewDidLoad 里建视图（第一次装 SwiftUI 宿主）。
    var load: Double
    /// viewWillAppear 总共，和其中装宿主、reload（读设置、会话、选引擎）、最后排版三段。
    var willAppear: Double
    var willHost: Double
    var willReload: Double
    var willLayout: Double
    /// 从 viewDidLoad 开始到 viewDidAppear。热启动一般 50–70 毫秒，比弹出动画（约 330 毫秒）短：不含整段动画。
    var loadToAppear: Double
    /// 从 viewDidLoad 开始到第一帧交给系统：弹出前准备做完以后主线程第一次睡下，这时这一圈的 Core Animation 提交已经做完。
    /// 在这之前系统那边只有一块空的键盘底板。
    var firstFrame: Double?
    /// viewDidLoad 到 viewDidAppear 这段里键盘主线程醒着干活的合计（毫秒）；其余时间主线程睡着，在等系统。
    var appearBusy: Double?
    /// 「先显示截图」开着时：第几毫秒（从 viewDidLoad 算）真键盘换下了截图；没用上截图时写为什么；这次截图用了多久。
    var snapshotSwap: Double?
    var snapshotMiss: String?
    var snapshotCapture: Double?
    /// 建键盘后到存这条记录前，键盘视图的高度每变一次记一段（「第 N 毫秒 高度」，用 → 连起来），和我们要的高度。
    /// 查「开着截图时，第一次下拉搜索框先停低了约 24pt、0.4 秒后才跳上去」：系统是不是到动画结束才定下键盘高度。
    var heights: String?
    var wantedHeight: Double?
    /// viewDidAppear 里同步做的事：剪贴板 / 帮回检测、常用词。
    var didClipboard: Double
    var didCommonWords: Double
    /// 拼音引擎这次弹出后多久准备好（从 viewDidLoad 开始算；冷启动才有意义，热启动通常很快）。
    var engineReady: Double?
    /// 拼音引擎这次准备：在引擎队列上排了多久、自己做了多久（毫秒）、做的是什么（RimeEngine.lastPrepareWork，几次的按先后用 → 连起来）。
    var engineWait: Double?
    var engineRun: Double?
    var engineWork: String?
    var memoryMB: Double?
    /// 上次收起到这次弹出隔了几秒；上次收起时的进程和这次是不是同一个；上次收起是怎么收尾的。
    var sinceHide: Double?
    var sameProcess: Bool?
    var lastCleanup: String?
    var nineKey: Bool

    var isCold: Bool { nth == 1 }

    /// 系统提前把键盘进程启动好了（预热）：进程启动到开始建键盘隔了 5 秒以上，那段进程在闲着等，不算我们用的时间。
    var prewarmed: Bool { (processToLoad ?? 0) > PopupLog.prewarmAfter }

    /// 建键盘到显示出来超过 3 秒、又没量到被挂起：多半是弹出途中对方 App 走开了（切走、收起），过一会儿才接着显示。
    /// 主线程每 50 毫秒被卡顿监测叫醒一次，睡不到半秒，「被挂起」那条量不出来。这次的耗时不算数。
    var interrupted: Bool { paused == nil && loadToAppear > PopupLog.interruptedAfter }

    /// 耗时不算数：中途被挂起，或者途中被打断。
    var excluded: Bool { paused != nil || interrupted }

    /// 我们这边一共用了多久（毫秒）：冷启动从进程启动算（系统预热过的从控制器建出来算），
    /// 热启动从进程被叫醒算（没记到醒的时刻就从控制器建出来算），到键盘显示出来。
    var total: Double {
        if let processToLoad, !prewarmed { return processToLoad + loadToAppear }
        return (wakeToInit ?? 0) + initToLoad + loadToAppear
    }

    /// 明显慢：热启动超过 150 毫秒，冷启动超过 800 毫秒（平时热启动 50–70、冷启动 300–400）。
    /// 中途被挂起、被打断的不算：那段时间键盘根本没在弹。
    var isSlow: Bool { !excluded && total >= (isCold ? PopupLog.slowCold : PopupLog.slowWarm) }

    private static func ms(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "-" }

    /// 第一行：什么时候、冷 / 热启动、一共多久、慢不慢。
    var title: String {
        let time = PopupLog.timeFormatter.string(from: at)
        let kind = isCold ? (prewarmed ? "冷启动（系统提前启动过键盘进程）" : "冷启动（键盘进程重新启动）") : "热启动（第 \(nth) 次弹出）"
        var title = "\(time) · \(kind) · 共 \(Self.ms(total)) 毫秒\(isSlow ? " · 慢" : "")"
        if paused != nil { title += " · 中途被挂起，不算" } else if interrupted { title += " · 途中被打断，不算" }
        return title
    }

    /// 下面几行：每一段用了多久，用大白话写。
    var details: [String] {
        var lines: [String] = []
        if let processToLoad, prewarmed {
            lines.append("系统提前 \(String(format: "%.1f", processToLoad / 1000)) 秒启动了键盘进程（预热），这段不算；弹出时建控制器到开始建键盘：\(Self.ms(initToLoad)) 毫秒")
        } else if let processToLoad {
            lines.append("系统启动键盘进程到开始建键盘：\(Self.ms(processToLoad)) 毫秒")
        } else if let wakeToInit {
            var line = "键盘被叫醒（之前闲了 \(String(format: "%.1f", (idleBeforeWake ?? 0) / 1000)) 秒）到开始建键盘：\(Self.ms(wakeToInit + initToLoad)) 毫秒"
            if let wakeBusy {
                line += "；其中键盘主线程干活 \(Self.ms(wakeBusy)) 毫秒，其余 \(Self.ms(max(0, wakeToInit + initToLoad - wakeBusy))) 毫秒在等系统"
            }
            lines.append(line)
        } else {
            lines.append("开始建键盘前的准备：\(Self.ms(initToLoad)) 毫秒（上次收起后键盘没闲下来过，量不到被叫醒的时刻）")
        }
        if let stallLongest {
            lines.append(stallLongest < 50 ? "弹出前 2 秒里键盘主线程没卡住过"
                         : "弹出前 2 秒里键盘主线程卡住过：最长 \(Self.ms(stallLongest)) 毫秒，合计 \(Self.ms(stallTotal)) 毫秒")
        }
        if lastCleanupMs != nil || lastTeardownMs != nil {
            func when(_ before: Double?) -> String {
                guard let before else { return "" }
                return before >= 0 ? "（弹出前 \(Self.ms(before)) 毫秒做完）" : "（弹出后 \(Self.ms(-before)) 毫秒才做完）"
            }
            lines.append("上次收起后的收尾 \(Self.ms(lastCleanupMs)) 毫秒\(when(lastCleanupBefore))，拆掉旧键盘 \(Self.ms(lastTeardownMs)) 毫秒\(when(lastTeardownBefore))")
        }
        var appear = "建键盘到显示出来：\(Self.ms(loadToAppear)) 毫秒（其中建视图 \(Self.ms(load))、弹出前准备 \(Self.ms(willAppear))：读设置 \(Self.ms(willReload))、排版 \(Self.ms(willLayout))）"
        if let paused {
            appear += "，途中键盘进程被系统挂起 \(String(format: "%.1f", paused / 1000)) 秒"
        } else if interrupted {
            appear += "，超过 \(Int(PopupLog.interruptedAfter / 1000)) 秒，多半是弹出途中切走了"
        }
        lines.append(appear)
        var frame: [String] = []
        if let firstFrame { frame.append("建键盘后第 \(Self.ms(firstFrame)) 毫秒把第一帧交给系统") }
        if let appearBusy {
            frame.append("建键盘到显示出来这段，键盘主线程干活 \(Self.ms(appearBusy)) 毫秒，其余 \(Self.ms(max(0, loadToAppear - appearBusy))) 毫秒在等系统")
        }
        if !frame.isEmpty { lines.append(frame.joined(separator: "；")) }
        var shot: [String] = []
        if let snapshotSwap { shot.append("先显示上次的截图，第 \(Self.ms(snapshotSwap)) 毫秒换成真键盘") }
        if let snapshotMiss { shot.append("截图开关开着，这次没用截图：\(snapshotMiss)") }
        if let snapshotCapture { shot.append("这次截了一张图留给下次，用了 \(Self.ms(snapshotCapture)) 毫秒") }
        if !shot.isEmpty { lines.append(shot.joined(separator: "；")) }
        if let heights {
            lines.append("键盘高度：\(heights)\(wantedHeight.map { "（我们要的 \(Self.ms($0))）" } ?? "")")
        }
        var engine = "显示后：剪贴板和帮回检测 \(Self.ms(didClipboard)) 毫秒，拼音能打 \(Self.ms(engineReady)) 毫秒"
        if engineWait != nil || engineRun != nil {
            engine += "（引擎排队 \(Self.ms(engineWait))、准备 \(Self.ms(engineRun))\(engineWork.map { "：" + $0 } ?? "")）"
        }
        lines.append(engine)
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
    private static let keptClearedKey = "debug.popupLogKeptCleared"
    private static let hideKey = "debug.popupLastHide"
    private static let keep = 60
    private static let keepSpecial = 40
    static let slowWarm: Double = 150
    static let slowCold: Double = 800
    /// 建键盘到显示出来超过这么久（毫秒）算途中被打断；进程启动到建键盘超过这么久算系统预热过。
    static let interruptedAfter: Double = 3000
    static let prewarmAfter: Double = 5000

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
    /// 「最近」里的冷启动和慢的也并进来（按 id 去重）：这个保留区是后来加的，之前记的那些也要算上；
    /// 只并上次「清空保留的」之后的。
    static func loadKept() -> [PopupRecord] {
        let kept = read(keptKey)
        let ids = Set(kept.map(\.id))
        let cleared = SharedStorage.defaults.object(forKey: keptClearedKey) as? Date ?? .distantPast
        let missing = load().filter { ($0.isCold || $0.isSlow) && $0.at > cleared && !ids.contains($0.id) }
        guard !missing.isEmpty else { return kept }
        return Array((kept + missing).sorted { $0.at < $1.at }.suffix(keepSpecial))
    }

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
            write(Array((loadKept().filter { $0.id != record.id } + [record]).suffix(keepSpecial)), keptKey)
        }
    }

    /// 只清最近的；冷启动和慢的要另外点「清空保留的」。
    static func clear() {
        SharedStorage.defaults.removeObject(forKey: recordsKey)
    }

    static func clearKept() {
        SharedStorage.defaults.removeObject(forKey: keptKey)
        SharedStorage.defaults.set(Date(), forKey: keptClearedKey)
    }

    // MARK: - 上次收起

    struct Hide: Codable {
        var at: Date
        var pid: Int32
        var cleanup: String
    }

    /// 上次收起（viewWillDisappear）的时刻（CACurrentMediaTime），只在这个进程里有。
    static var lastHideMono: CFTimeInterval = 0
    /// 上次收起后的收尾、拆旧键盘各用了多少毫秒（只在这个进程里有）。
    static var lastCleanupMs: Double?
    static var lastTeardownMs: Double?
    static var lastCleanupDone: CFTimeInterval?
    static var lastTeardownDone: CFTimeInterval?

    /// 测试工具 › 弹出记录里的开关「弹出时先显示截图」（试验，默认关）。只在记弹出记录的包里有用。
    static let snapshotEnabledKey = "debug.popupSnapshot"
    static var snapshotEnabled: Bool {
        get { enabled && SharedStorage.defaults.bool(forKey: snapshotEnabledKey) }
        set { SharedStorage.defaults.set(newValue, forKey: snapshotEnabledKey) }
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
        // 中途被挂起、被打断的那几次耗时不算数，不进「一般多久」。
        let warmTimes = warm.filter { !$0.excluded }.map(\.total)
        let coldTimes = cold.filter { !$0.excluded }.map(\.total)
        if !warm.isEmpty { parts.append("热启动 \(warm.count) 次，一般 \(ms(median(warmTimes))) 毫秒") }
        if !cold.isEmpty { parts.append("冷启动 \(cold.count) 次，一般 \(ms(median(coldTimes))) 毫秒") }
        let slow = records.filter(\.isSlow).count
        parts.append(slow == 0 ? "没有明显慢的" : "明显慢的 \(slow) 次")
        return parts.joined(separator: "；") + "。"
    }

    /// 几个词是什么意思，复制出去和卡片上都带着。
    static let legend = """
    热启动：键盘进程还在，系统直接叫醒它，一般 50–100 毫秒。
    冷启动：键盘进程已经被系统关掉，要重新启动，一般 300–400 毫秒。
    「共 N 毫秒」只算键盘自己用的时间；在这之前系统处理弹出用的时间记不到。
    「主线程卡住」：键盘自己的主线程忙着别的、接不了系统的弹出请求；没卡住却还慢，时间就花在系统那边。
    「在等系统」：键盘进程醒了，主线程却睡着，等系统把弹出请求交过来；这段不是键盘慢。
    「第一帧」：键盘第一次把画好的样子交给系统；在这之前系统那边只有一块空的键盘底板，交晚了就会看到底板先往上滑、键后冒出来。
    「先显示截图」：测试工具里的试验开关。开着时，样子和上次一样就先放一张上次截的图，第一帧马上交出去，真键盘随后换上。
    「中途被挂起」：键盘建到一半，系统把键盘进程挂起了（比如弹出时切走或锁屏），那次的耗时不算数，也不标慢。
    「途中被打断」：建键盘到显示出来超过 \(Int(interruptedAfter / 1000)) 秒，多半是弹出途中切走了、过一会儿才接着显示，同样不算数。
    「系统提前启动过键盘进程」：系统预先把键盘进程启动好放着（预热），进程启动到弹出隔了好几秒，这段不算进冷启动的时间。
    「键盘高度」：弹出后系统给键盘的高度每变一次记一段；刚开始常常是整屏高（还没定），定下来应该等于我们要的高度。
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
    /// 主线程最近一次睡下（RunLoop beforeWaiting）的时刻。
    private(set) static var sleepStart: CFTimeInterval = 0
    /// 主线程最近一次醒来（RunLoop afterWaiting）的时刻：从这以后它一直醒着。
    private(set) static var awakeSince: CFTimeInterval = 0
    /// lastWake 以后主线程醒着的时间合计（不含正在醒着的这一段）：拿来分「我们在忙」和「在等系统」。
    private static var awakeTotal: CFTimeInterval = 0
    private static var awake = false
    private static var installed = false
    static var isInstalled: Bool { installed }
    /// 主线程下一次睡下时调一次（这时这一圈的 Core Animation 提交已经做完）：拿来量第一帧什么时候交给系统。
    static var onNextSleep: (() -> Void)?

    /// lastWake 到现在主线程醒着干活的合计（毫秒）。在主线程调。
    static func busySinceWake(now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        (awakeTotal + (awake ? now - awakeSince : 0)) * 1000
    }

    static func install() {
        guard PopupLog.enabled, !installed else { return }
        installed = true
        // 醒来记得越早越好、睡下记得越晚越好：睡下那个排在最后（order 最大），
        // 不然同一圈里 Core Animation 提交（排版、绘制）和自动释放池在它后面才跑，我们自己的活会被算成「在等系统」。
        let sleeping = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            let now = CACurrentMediaTime()
            if awake { awakeTotal += now - awakeSince }
            awake = false
            sleepStart = now
            if let action = onNextSleep {
                onNextSleep = nil
                action()
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), sleeping, .commonModes)
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            let now = CACurrentMediaTime()
            awakeSince = now
            awake = true
            if sleepStart > 0, now - sleepStart > 0.5 {
                lastWake = now
                lastIdle = now - sleepStart
                awakeTotal = 0
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

/// 键盘主线程有没有卡住：后台每 50 毫秒往主线程派一个空活，主线程隔了多久才做到，就是这段时间没空。
/// 超过 50 毫秒的记下来（最多 40 条）。主线程睡着（闲着或进程被系统挂起）的时间不算，只算醒着却没空的。只在开发版、内测、公测开。
enum MainStalls {
    private struct Stall { var at: CFTimeInterval; var ms: Double }
    private static let lock = NSLock()
    private static var stalls: [Stall] = []
    private static var pingSentAt: CFTimeInterval?
    private static var timer: DispatchSourceTimer?

    static func start() {
        guard PopupLog.enabled, timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "app.enclave.mainstalls", qos: .utility))
        source.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        source.setEventHandler {
            let sent = CACurrentMediaTime()
            lock.lock()
            let waiting = pingSentAt != nil
            if !waiting { pingSentAt = sent }
            lock.unlock()
            guard !waiting else { return }
            DispatchQueue.main.async {
                let now = CACurrentMediaTime()
                // 派出以后主线程要是睡过（闲着或被挂起），睡着那段不算卡，只算醒来以后到做到这个活之间忙的时间。
                let busySince = max(sent, MainWake.awakeSince)
                lock.lock()
                let ms = (now - busySince) * 1000
                if ms > 50, ms < 2000 {
                    stalls.append(Stall(at: busySince, ms: ms))
                    if stalls.count > 40 { stalls.removeFirst() }
                }
                pingSentAt = nil
                lock.unlock()
            }
        }
        source.resume()
        timer = source
    }

    /// from 到 to 之间卡住的：最长一次、合计（毫秒）。没开监测时为 nil。
    static func summary(from: CFTimeInterval, to: CFTimeInterval) -> (longest: Double, total: Double)? {
        guard timer != nil else { return nil }
        lock.lock()
        let hits = stalls.filter { $0.at + $0.ms / 1000 > from && $0.at < to }
        lock.unlock()
        return (hits.map(\.ms).max() ?? 0, hits.map(\.ms).reduce(0, +))
    }
}

/// 一次弹出途中记下的几个时刻（CACurrentMediaTime）。每个键盘控制器一份：原来放在 PopupLog 的静态变量里，
/// 两次弹出挨得很近（0.1 秒）时后一次把前一次的盖掉，前一次的「第一帧」「截图」几行就丢了。
final class PopupMarks {
    /// 把第一帧交给系统、真键盘换下截图的时刻；截一张图用了多少毫秒。
    var firstFrame: CFTimeInterval?
    var snapshotSwap: CFTimeInterval?
    var snapshotCapture: Double?
    /// 键盘视图高度每变一次记一条。
    var heights: [(at: CFTimeInterval, height: Double)] = []

    func noteHeight(_ height: Double, at time: CFTimeInterval) {
        guard heights.last?.height != height, heights.count < 12 else { return }
        heights.append((time, height))
    }

    /// 「第 13 毫秒 667 → 第 62 毫秒 296」，从 start（viewDidLoad 开始）算。
    func heightsText(from start: CFTimeInterval) -> String? {
        guard !heights.isEmpty else { return nil }
        return heights.map { "第 \(String(format: "%.0f", ($0.at - start) * 1000)) 毫秒 \(String(format: "%.0f", $0.height))" }
            .joined(separator: " → ")
    }
}
