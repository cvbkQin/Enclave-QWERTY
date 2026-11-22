import Foundation

/// AI 功能能不能用：没开始试用时每天能用 10 次；在解锁页点「开始 14 天免费试用」（0 元的非消耗型内购，审核指南 3.1.1，
/// 05 上架风险报告高 2）后 14 天不限次；到期没买时回到每天 10 次；一次买断后不限。
/// 打字、拼音、常用词不受影响，只有润色、按要求改、帮我写、再润要看这里，每成功拿到一次结果算一次。
/// App 用 StoreKit 读出试用开始日（试用商品的购买日）和是否买过，写进 App Group；键盘只读这份记录。
enum AIAccess: Equatable {
    /// 还没开始试用：每天免费次数，和试用到期后一样。
    case notStarted
    case trial(daysLeft: Int, ends: Date)
    case expired(ended: Date)
    case unlocked(purchased: Date?)

    static let trialDays = 14
    /// 最后几天在首页和键盘里提醒。
    static let reminderDays = 3
    static let productID = "com.gengyunqin.enclave.unlock"
    /// 14 天试用：0 元的非消耗型商品，买了就从购买日起算 14 天。购买记录在 App Store，删了重装、换手机都不会重来。
    static let trialProductID = "com.gengyunqin.enclave.trial14"

    /// 到期后每天能用的次数，本地时间零点重置。
    static let dailyFreeUses = 10

    var allowsAI: Bool {
        usesDailyQuota ? Self.usesLeftToday > 0 : true
    }

    /// 按每天免费次数走：还没开始试用，或试用到期没买。
    var usesDailyQuota: Bool {
        switch self {
        case .notStarted, .expired: return true
        case .trial, .unlocked: return false
        }
    }

    /// 试用最后 3 天。
    var isEndingSoon: Bool {
        if case .trial(let days, _) = self { return days <= Self.reminderDays }
        return false
    }

    /// 试用商品的购买日。0.97 以前按首次下载日自动开始，记在 aiAccess.trialStart，不再读。
    private static let trialStartKey = "aiAccess.trialStartedAt"
    private static let unlockedKey = "aiAccess.unlocked"
    private static let purchaseDateKey = "aiAccess.purchaseDate"
    private static let debugKey = "aiAccess.debug"
    private static let devDefaultedKey = "aiAccess.devDefaulted"
    private static let storeEnvironmentKey = "aiAccess.storeEnvironment"

    /// 试用开始日（试用商品的购买日）；没开始试用时为 nil。
    static var trialStart: Date? {
        SharedStorage.defaults.object(forKey: trialStartKey) as? Date
    }

    /// App 读 App Store 的试用商品记录后调用：有记录写购买日，没有（或退款了）清掉。
    static func recordTrial(start: Date?) {
        if let start {
            SharedStorage.defaults.set(start, forKey: trialStartKey)
        } else {
            SharedStorage.defaults.removeObject(forKey: trialStartKey)
        }
    }

    static func recordPurchase(unlocked: Bool, date: Date?) {
        SharedStorage.defaults.set(unlocked, forKey: unlockedKey)
        if let date { SharedStorage.defaults.set(date, forKey: purchaseDateKey) }
    }

    static var current: AIAccess { current(now: Date()) }

    static func current(now: Date) -> AIAccess {
        if debugAllowed, let debug = SharedStorage.defaults.string(forKey: debugKey), let state = debugState(debug, now: now) {
            return state
        }
        if SharedStorage.defaults.bool(forKey: unlockedKey) {
            return .unlocked(purchased: SharedStorage.defaults.object(forKey: purchaseDateKey) as? Date)
        }
        guard let trialStart else { return .notStarted }
        return trialState(start: trialStart, now: now)
    }

    /// 从 start 那天起算 14 个自然日（按本地日期，开始那天算第 1 天），到第 15 天 0 点结束。
    static func trialState(start: Date, now: Date, calendar: Calendar = .current) -> AIAccess {
        let first = calendar.startOfDay(for: start)
        let ends = calendar.date(byAdding: .day, value: trialDays, to: first) ?? first
        guard now < ends else { return .expired(ended: ends) }
        let left = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: ends).day ?? 0
        return .trial(daysLeft: max(left, 1), ends: ends)
    }

    /// 试用能用到的最后一天：ends 是第 15 天 0 点，显示减一天，写「用到 12 月 5 日」（11-22 cvbk 定，全 App 统一）。
    static func lastTrialDay(ends: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: ends) ?? ends
    }

    /// 0.94 及以前的 TestFlight 版写过这个值（按已解锁处理，没有购买日期）；0.95 起不再写，App 启动时清掉。
    static let testFlightUnlock = "testflight"

    /// 截图和测试用：-aiAccess notStarted / expired / unlocked / days:2。
    static func setDebug(_ value: String?) {
        SharedStorage.defaults.set(value, forKey: debugKey)
    }

    /// 测试用的购买状态什么时候算数：模拟器 Debug 截图；开发者版装机（DEV_BUILD=YES）且不是 App Store 正式环境。
    /// 别的包（TestFlight、公测、正式）一律按真实购买走，以前留下的测试状态不管写的是什么都不生效。
    static var debugAllowed: Bool {
        #if DEBUG
        return true
        #else
        return BuiltinAPI.isDevBuild && storeEnvironment != "production"
        #endif
    }

    /// App 读 AppTransaction 时记下的环境（production / sandbox / xcode），键盘没法自己读，从 App Group 拿。
    static var storeEnvironment: String? { SharedStorage.defaults.string(forKey: storeEnvironmentKey) }

    static func recordStoreEnvironment(_ value: String) {
        SharedStorage.defaults.set(value, forKey: storeEnvironmentKey)
    }

    /// 开发者版第一次启动、还没在设置里选过：默认已解锁，和用户手上一直用的一样。之后选「跟随真实」也不会再改回去。
    static func applyDevDefault() {
        guard BuiltinAPI.isDevBuild, !SharedStorage.defaults.bool(forKey: devDefaultedKey) else { return }
        SharedStorage.defaults.set(true, forKey: devDefaultedKey)
        if debugValue == nil { setDebug("unlocked") }
    }

    /// 测试用：今天已用的次数清零。
    static func resetUsesToday() {
        SharedStorage.defaults.removeObject(forKey: usesCountKey)
    }

    static var debugValue: String? { SharedStorage.defaults.string(forKey: debugKey) }

    private static func debugState(_ value: String, now: Date) -> AIAccess? {
        let day: TimeInterval = 86_400
        switch value {
        case "notStarted": return .notStarted
        case "expired": return .expired(ended: now.addingTimeInterval(-2 * day))
        case "unlocked": return .unlocked(purchased: now.addingTimeInterval(-day))
        case testFlightUnlock: return .unlocked(purchased: nil)
        default:
            guard value.hasPrefix("days:"), let days = Int(value.dropFirst(5)) else { return nil }
            return .trial(daysLeft: days, ends: now.addingTimeInterval(Double(days) * day))
        }
    }

    // MARK: - 到期后的每日次数

    private static let usesDayKey = "aiAccess.usesDay"
    private static let usesCountKey = "aiAccess.usesCount"

    static var usesToday: Int {
        SharedStorage.defaults.string(forKey: usesDayKey) == dayStamp(Date())
            ? SharedStorage.defaults.integer(forKey: usesCountKey) : 0
    }

    static var usesLeftToday: Int {
        let used = SharedStorage.defaults.string(forKey: usesDayKey) == dayStamp(Date())
            ? SharedStorage.defaults.integer(forKey: usesCountKey) : 0
        return max(dailyFreeUses - used, 0)
    }

    /// 按每天次数走时（没开始试用、试用到期）每成功拿到一次 AI 结果调用一次；失败和取消不算，试用中和已解锁不计数。
    static func recordUse() {
        guard current.usesDailyQuota else { return }
        let today = dayStamp(Date())
        let used = SharedStorage.defaults.string(forKey: usesDayKey) == today
            ? SharedStorage.defaults.integer(forKey: usesCountKey) : 0
        SharedStorage.defaults.set(today, forKey: usesDayKey)
        SharedStorage.defaults.set(used + 1, forKey: usesCountKey)
    }

    // MARK: - 键盘里最后几天的轻提示：每天最多一次，关掉当天不再出

    private static let reminderShownKey = "aiAccess.reminderDay"

    static var reminderDueToday: Bool {
        guard current.isEndingSoon else { return false }
        return SharedStorage.defaults.string(forKey: reminderShownKey) != dayStamp(Date())
    }

    static func markReminderShown() {
        SharedStorage.defaults.set(dayStamp(Date()), forKey: reminderShownKey)
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
