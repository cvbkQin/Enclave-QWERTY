import Foundation

/// 键盘把自己看到的状态记进共享存储，App 的「准备情况」读出来显示。
/// App 读不到「允许完全访问」开关，只能等键盘出现过一次后由键盘记下来。
enum KeyboardStatus {
    private static let fullAccessKey = "status.fullAccess"
    private static let seenKey = "status.keyboardSeen"

    /// nil 表示键盘还没出现过（或共享存储不可用），不知道。
    static var fullAccess: Bool? {
        get { SharedStorage.defaults.object(forKey: fullAccessKey) as? Bool }
        set { SharedStorage.defaults.set(newValue, forKey: fullAccessKey) }
    }

    /// 键盘出现过一次就记下来，App 用它判断键盘已经加好。没开完全访问时键盘写不进共享存储，所以不一定有。
    static var keyboardSeen: Bool {
        get { SharedStorage.defaults.bool(forKey: seenKey) }
        set { if newValue != keyboardSeen { SharedStorage.defaults.set(newValue, forKey: seenKey) } }
    }
}
