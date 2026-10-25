import Foundation

/// 打字耗时：键盘记下最近的按键从按下字母键到候选显示出来用了多久，「拼音词库」页显示出来，用来判断卡不卡。
/// 存在共享存储里，键盘要开了完全访问才写得进去。
enum TypingStats {
    private static let totalKey = "typing.keyTotalMs"
    private static let engineKey = "typing.keyEngineMs"
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

    /// 键盘收起时也写一次，免得最后几个键丢了。
    static func flush() {
        guard !total.isEmpty else { return }
        let defaults = SharedStorage.defaults
        let savedTotal = (defaults.array(forKey: totalKey) as? [Double]) ?? []
        let savedEngine = (defaults.array(forKey: engineKey) as? [Double]) ?? []
        defaults.set(Array((savedTotal + total).suffix(keep)), forKey: totalKey)
        defaults.set(Array((savedEngine + engine).suffix(keep)), forKey: engineKey)
        total = []
        engine = []
    }

    struct Summary {
        var count: Int
        /// 毫秒。
        var medianTotal: Double
        var slowTotal: Double
        var slowestTotal: Double
        var medianEngine: Double
    }

    static var summary: Summary? {
        let defaults = SharedStorage.defaults
        let total = ((defaults.array(forKey: totalKey) as? [Double]) ?? []).sorted()
        let engine = ((defaults.array(forKey: engineKey) as? [Double]) ?? []).sorted()
        guard !total.isEmpty else { return nil }
        return Summary(count: total.count, medianTotal: percentile(total, 0.5), slowTotal: percentile(total, 0.9),
                       slowestTotal: total.last ?? 0, medianEngine: engine.isEmpty ? 0 : percentile(engine, 0.5))
    }

    static func clear() {
        SharedStorage.defaults.removeObject(forKey: totalKey)
        SharedStorage.defaults.removeObject(forKey: engineKey)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
    }
}
