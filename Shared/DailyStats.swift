import Foundation

/// 按天汇总的使用次数，给 App 首页的仪表盘用。只存在共享存储里，只留最近 30 天。
/// 存成 ["2026-10-26": ["prediction.shown": 12, ...]]；键盘要开完全访问才写得进去。
enum DailyStats {
    private static let key = "stats.daily"
    private static let keepDays = 30
    /// 攒在内存里，键盘收起时写一次，免得每次上屏都写共享存储。
    private static var pending: [String: Int] = [:]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func add(_ counter: String, _ amount: Int = 1) {
        guard amount > 0 else { return }
        pending[counter, default: 0] += amount
    }

    static func flush() {
        guard !pending.isEmpty else { return }
        let defaults = SharedStorage.defaults
        var all = (defaults.dictionary(forKey: key) as? [String: [String: Int]]) ?? [:]
        let today = dayFormatter.string(from: Date())
        var day = all[today] ?? [:]
        for (counter, amount) in pending { day[counter, default: 0] += amount }
        all[today] = day
        // 日期字符串按字典序就是时间顺序，只留最近 30 天。
        for old in all.keys.sorted().dropLast(keepDays) { all[old] = nil }
        defaults.set(all, forKey: key)
        pending = [:]
    }

    static func clear() {
        pending = [:]
        SharedStorage.defaults.removeObject(forKey: key)
    }

    /// App 里读：最近 days 天这个计数的每天数值（没有记录的天为 0），最早的在前。
    static func series(_ counter: String, days: Int = 7) -> [(day: String, value: Int)] {
        let all = (SharedStorage.defaults.dictionary(forKey: key) as? [String: [String: Int]]) ?? [:]
        let calendar = Calendar(identifier: .gregorian)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let day = dayFormatter.string(from: date)
            return (day, all[day]?[counter] ?? 0)
        }
    }
}
