import Foundation

/// App 仪表盘要的使用记录：按天的计数一律走 DailyStats（polish.*、word.*），
/// 不按天的两样（最近 10 次请求、试过的场景）存在这里。都只在手机上，不上传。
enum UsageStats {
    private static let recentKey = "stats.polishRecent"
    private static let labKey = "stats.labTried"
    private static let recentLimit = 10

    // MARK: 执行提示词（键盘里）

    /// 一次请求结束：成功记 polish.done、耗时和这条提示词，失败记 polish.failed；都进最近 10 次。点停止不算。
    static func recordPolish(ms: Int, ok: Bool, styleID: UUID?) {
        if ok {
            DailyStats.add("polish.done")
            DailyStats.add("polish.ms", ms)
            if let styleID { DailyStats.add("polish.style.\(styleID.uuidString)") }
        } else {
            DailyStats.add("polish.failed")
        }
        recordRequest(ms: ms, ok: ok)
        // 请求不多，每次都写，App 马上能看到。
        DailyStats.flush()
    }

    /// 只进最近 10 次（接口页「测试」也算一次请求），不计入执行次数。
    static func recordRequest(ms: Int, ok: Bool) {
        var recent = polishRecent
        recent.append(Request(ms: ms, ok: ok, at: Date()))
        polishRecent = Array(recent.suffix(recentLimit))
    }

    struct Request: Codable {
        var ms: Int
        var ok: Bool
        var at: Date
    }

    /// 最近 10 次请求，最早的在前。
    static var polishRecent: [Request] {
        get {
            guard let data = SharedStorage.defaults.data(forKey: recentKey) else { return [] }
            return (try? JSONDecoder().decode([Request].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedStorage.defaults.set(data, forKey: recentKey) }
        }
    }

    // MARK: 常用词上屏（键盘里）

    /// 设置 › 隐私「清除使用统计」：按天计数和最近 10 次请求的耗时。
    static func clearStats() {
        DailyStats.clear()
        SharedStorage.defaults.removeObject(forKey: recentKey)
    }

    static func wordCommitted(_ text: String) {
        DailyStats.add("word.commit")
        DailyStats.add(wordKey(text))
    }

    static func wordKey(_ text: String) -> String { "word.text.\(text)" }

    // MARK: 使用指引（App 里）

    /// 试过的场景 id。
    static var labTried: Set<String> {
        Set(SharedStorage.defaults.stringArray(forKey: labKey) ?? [])
    }

    static func markLabTried(_ id: String) {
        var tried = labTried
        guard tried.insert(id).inserted else { return }
        SharedStorage.defaults.set(Array(tried).sorted(), forKey: labKey)
    }

    // MARK: 读（App 里）

    /// 最近 7 天的合计。
    static func week(_ counter: String) -> Int {
        DailyStats.series(counter, days: 7).reduce(0) { $0 + $1.value }
    }

    static func today(_ counter: String) -> Int {
        DailyStats.series(counter, days: 1).first?.value ?? 0
    }
}
