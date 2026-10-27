import Foundation

/// 打字耗时：键盘记下最近的按键从按下字母键到候选显示出来用了多久，「拼音词库」页显示出来，用来判断卡不卡。
/// 顺带记键盘的内存占用（开没开整句模型分开记）和收到系统内存警告的次数，看会不会被系统杀掉。
/// 存在共享存储里，键盘要开了完全访问才写得进去。
enum TypingStats {
    private static let totalKey = "typing.keyTotalMs"
    private static let engineKey = "typing.keyEngineMs"
    private static let memoryKey = "typing.memoryMB"
    private static let memoryModelKey = "typing.memoryModelMB"
    private static let warningsKey = "typing.memoryWarnings"
    private static let launchAppearKey = "typing.launchAppearMs"
    private static let launchReadyKey = "typing.launchReadyMs"
    /// 键盘现在用的词库带不带整句模型，键盘切引擎时设置。
    static var modelInUse = false
    /// 只留最近这么多个按键。
    private static let keep = 200
    private static var total: [Double] = []
    private static var engine: [Double] = []

    /// 键盘里每个按键记一次（秒）：total 从交给引擎到界面更新完，engine 是引擎自己算的时间。攒够一批再写。
    static func record(total seconds: Double, engine engineSeconds: Double) {
        total.append(seconds * 1000)
        engine.append(engineSeconds * 1000)
        if total.count >= 20 { flush() }
    }

    /// 键盘收起时也写一次，免得最后几个键丢了。每次写的时候顺便记一次内存。
    static func flush() {
        guard !total.isEmpty else { return }
        let defaults = SharedStorage.defaults
        let key = modelInUse ? memoryModelKey : memoryKey
        if let memory = footprintMB() {
            let saved = (defaults.array(forKey: key) as? [Double]) ?? []
            defaults.set(Array((saved + [memory]).suffix(keep)), forKey: key)
        }
        let savedTotal = (defaults.array(forKey: totalKey) as? [Double]) ?? []
        let savedEngine = (defaults.array(forKey: engineKey) as? [Double]) ?? []
        defaults.set(Array((savedTotal + total).suffix(keep)), forKey: totalKey)
        defaults.set(Array((savedEngine + engine).suffix(keep)), forKey: engineKey)
        total = []
        engine = []
    }

    // MARK: - 冷启动

    /// 键盘进程是什么时候启动的（系统拉起扩展的那一刻）。读不到时为空，冷启动就不记。
    private static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()
    private static var launchAppear: Double?
    private static var launchReady: Double?
    private static var launchDone = false

    /// 冷启动时键盘第一次弹出来（viewDidAppear）。
    static func noteLaunchAppeared() {
        guard launchAppear == nil else { return }
        launchAppear = sinceLaunch()
        saveLaunch()
    }

    /// 冷启动时拼音引擎第一次准备好（能出候选）。
    static func noteLaunchEngineReady() {
        guard launchReady == nil else { return }
        launchReady = sinceLaunch()
        saveLaunch()
    }

    /// 毫秒。离进程启动太久（系统预先拉起、隔了很久才弹出）就不算冷启动，记 -1。
    private static func sinceLaunch() -> Double {
        guard let processStart else { return -1 }
        let ms = Date().timeIntervalSince(processStart) * 1000
        return ms >= 0 && ms < 20_000 ? ms : -1
    }

    /// 两个时刻都有了才写，每个进程只写一次。
    private static func saveLaunch() {
        guard !launchDone, let appear = launchAppear, let ready = launchReady else { return }
        launchDone = true
        guard appear >= 0, ready >= 0 else { return }
        let defaults = SharedStorage.defaults
        for (key, value) in [(launchAppearKey, appear), (launchReadyKey, ready)] {
            let saved = (defaults.array(forKey: key) as? [Double]) ?? []
            defaults.set(Array((saved + [value]).suffix(30)), forKey: key)
        }
    }

    /// 系统发来内存警告时记一次。
    static func noteMemoryWarning() {
        let defaults = SharedStorage.defaults
        defaults.set(defaults.integer(forKey: warningsKey) + 1, forKey: warningsKey)
    }

    /// 键盘进程现在占的内存（MB），就是系统判断要不要杀掉键盘时看的那个数。
    static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : nil
    }

    struct Summary {
        var count: Int
        /// 毫秒。
        var medianTotal: Double
        var slowTotal: Double
        var slowestTotal: Double
        var medianEngine: Double
        /// 内存（MB），没有记录时为空。
        var memory: Memory?
        var memoryWithModel: Memory?
        var memoryWarnings: Int
        /// 最近几次冷启动，没有记录时为空。
        var launch: Launch?
    }

    /// 冷启动：从键盘进程启动到弹出来、到拼音能打（毫秒，中位数）。
    struct Launch {
        var count: Int
        var appear: Double
        var ready: Double
    }

    struct Memory {
        var median: Double
        var peak: Double
    }

    static var summary: Summary? {
        let defaults = SharedStorage.defaults
        let total = ((defaults.array(forKey: totalKey) as? [Double]) ?? []).sorted()
        let engine = ((defaults.array(forKey: engineKey) as? [Double]) ?? []).sorted()
        guard !total.isEmpty else { return nil }
        return Summary(count: total.count, medianTotal: percentile(total, 0.5), slowTotal: percentile(total, 0.9),
                       slowestTotal: total.last ?? 0, medianEngine: engine.isEmpty ? 0 : percentile(engine, 0.5),
                       memory: memory(forKey: memoryKey), memoryWithModel: memory(forKey: memoryModelKey),
                       memoryWarnings: defaults.integer(forKey: warningsKey), launch: launch)
    }

    private static var launch: Launch? {
        let appear = ((SharedStorage.defaults.array(forKey: launchAppearKey) as? [Double]) ?? []).sorted()
        let ready = ((SharedStorage.defaults.array(forKey: launchReadyKey) as? [Double]) ?? []).sorted()
        guard !appear.isEmpty, !ready.isEmpty else { return nil }
        return Launch(count: appear.count, appear: percentile(appear, 0.5), ready: percentile(ready, 0.5))
    }

    private static func memory(forKey key: String) -> Memory? {
        let values = ((SharedStorage.defaults.array(forKey: key) as? [Double]) ?? []).sorted()
        guard let peak = values.last else { return nil }
        return Memory(median: percentile(values, 0.5), peak: peak)
    }

    static func clear() {
        for key in [totalKey, engineKey, memoryKey, memoryModelKey, warningsKey, launchAppearKey, launchReadyKey] {
            SharedStorage.defaults.removeObject(forKey: key)
        }
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
    }
}
