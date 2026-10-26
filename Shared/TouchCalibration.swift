import CoreGraphics
import Foundation

/// 按手指习惯校准：记下每个字母键（全键盘、九宫格分开）平时按偏到哪儿，判定时把这个键的中心挪过去。
/// 只记打出去、没被删掉的键，记的是落点相对键中心偏了多少（按键宽高算的比例），不记打了什么字。
/// 存在共享存储里，App 里能看到学了多少、能重置；键盘要开完全访问才写得进去。
enum TouchCalibration {
    private static let storeKey = "touch.calibration"
    private static let enabledKey = "touch.calibration.enabled"
    /// 一个键至少按这么多次才开始挪。
    private static let minSamples = 8
    /// 均值只按最近这么多次算，换了握法也能慢慢跟上。
    private static let window = 150.0
    /// 最多挪这么多（键宽高的比例），免得挪到隔壁键上。
    private static let maxShift = 0.3
    /// 偏得太远的那一下多半是手滑，不算。
    private static let maxSampleOffset = 0.6
    /// 还没确认的按键（可能马上被删掉）。
    private static let maxPending = 30

    struct Stat: Equatable {
        var count: Double
        var dx: Double
        var dy: Double
    }

    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: enabledKey) }
    }

    private static var stats: [String: Stat] = [:]
    private static var pending: [(key: String, dx: Double, dy: Double)] = []
    private static var dirty = 0
    /// 判定时用：键盘弹出时读一次，免得每个触摸都查一遍开关。
    private(set) static var active = false

    // MARK: - 键盘

    /// 键盘弹出时：读开关和已学到的偏移（App 里可能刚重置过）。
    static func reload() {
        active = isEnabled
        stats = load()
        pending = []
    }

    /// 键 id 由键盘给（布局 + 字母），offset 是落点减键中心、除以键宽高。
    static func observe(key: String, dx: Double, dy: Double) {
        guard active, abs(dx) < maxSampleOffset, abs(dy) < maxSampleOffset else { return }
        pending.append((key, dx, dy))
        if pending.count > maxPending { accept(pending.removeFirst()) }
    }

    /// 删除键：最后打的那个键不算（多半是按错了）。
    static func undo() {
        _ = pending.popLast()
    }

    /// 上屏、空格、标点等：前面打的键都确认没错。
    static func confirm() {
        guard !pending.isEmpty else { return }
        pending.forEach(accept)
        pending = []
        if dirty >= 20 { save() }
    }

    /// 键盘收起：没确认的不要，学到的写进去。
    static func flush() {
        pending = []
        if dirty > 0 { save() }
    }

    /// 这个键的中心要挪多少（键宽高的比例），学得不够时为零。
    static func shift(for key: String) -> CGVector {
        guard active, let stat = stats[key], stat.count >= Double(minSamples) else { return .zero }
        // 次数少时打个折，越多越信。
        let trust = stat.count / (stat.count + 20)
        func clamp(_ value: Double) -> Double { min(max(value * trust, -maxShift), maxShift) }
        return CGVector(dx: clamp(stat.dx), dy: clamp(stat.dy))
    }

    static var hasShifts: Bool {
        active && stats.values.contains { $0.count >= Double(minSamples) }
    }

    private static func accept(_ sample: (key: String, dx: Double, dy: Double)) {
        var stat = stats[sample.key] ?? Stat(count: 0, dx: 0, dy: 0)
        stat.count = min(stat.count + 1, window)
        stat.dx += (sample.dx - stat.dx) / stat.count
        stat.dy += (sample.dy - stat.dy) / stat.count
        stats[sample.key] = stat
        dirty += 1
    }

    // MARK: - 存储（App 也用）

    static func load() -> [String: Stat] {
        guard let raw = SharedStorage.defaults.dictionary(forKey: storeKey) as? [String: [Double]] else { return [:] }
        return raw.compactMapValues { $0.count == 3 ? Stat(count: $0[0], dx: $0[1], dy: $0[2]) : nil }
    }

    private static func save() {
        SharedStorage.defaults.set(stats.mapValues { [$0.count, $0.dx, $0.dy] }, forKey: storeKey)
        dirty = 0
    }

    /// App 里「重置校准」。
    static func reset() {
        SharedStorage.defaults.removeObject(forKey: storeKey)
        stats = [:]
        pending = []
    }

    /// App 里显示：学了多少次按键、已经在挪的键有几个。
    static var summary: (samples: Int, keys: Int) {
        let all = load().values
        return (Int(all.reduce(0) { $0 + $1.count }), all.filter { $0.count >= Double(minSamples) }.count)
    }

    /// App 里的格子图：每个键学了几次（最多 window 次），键 id 同 observe。
    static var counts: [String: Double] {
        load().mapValues(\.count)
    }

    static var fullCount: Double { window }
}
