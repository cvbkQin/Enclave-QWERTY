import Foundation

/// 比两个时间的先后，只比秒数（Double），不调 Foundation 的 Date <= 和 >=。
///
/// Xcode 27.2 的 SDK 里，Date 的 <= 和 >= 是「回溯部署」的新函数：系统版本号到了 27.2 就直接调系统里的那份。
/// iPadOS 27.2 测试版（24B5089g）报的版本号是 27.2，系统里却还没有这两个函数，调用会跳到 0 地址。
/// 11-23 用户的 iPad 一打开 App 就闪退，就是 iCloud 同步合并时比时间先后走到了这里（崩溃日志：SyncMerge.latest +832）。
/// Swift 的 max(a, b) 里面用的也是 >=，所以比时间、取较晚的时间都用这里的写法。< 和 > 没有这个问题。
/// CI 的「Check back-deployed Date comparisons」会检查编出来的 App 和键盘里还有没有这两个函数。
extension Date {
    /// 比 other 晚（严格晚）。
    func isAfter(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate > other.timeIntervalSinceReferenceDate
    }

    /// 比 other 早（严格早）。
    func isBefore(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate < other.timeIntervalSinceReferenceDate
    }

    /// 两个里晚的那个，一样时取 b（和 Swift 的 max(a, b) 一样）。
    static func later(_ a: Date, _ b: Date) -> Date {
        a.isAfter(b) ? a : b
    }
}
