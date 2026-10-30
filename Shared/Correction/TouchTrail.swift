import Foundation

/// 纠错第 7 步（触点解码）：记下每个字母 / 数字键的落点，纠错时按落点给「按到邻键」的改法加减罚分。
/// 按在键正中间的，改成邻键要罚得更重；按在两个键交界、偏向某个邻键的，改成它罚得轻。
/// 键盘界面（主线程）记，引擎队列上读，所以加锁。和引擎的输入串按字符对齐，对不上就不用（照 0.94 的固定罚分）。
enum TouchTrail {
    /// 落点相对这个键（按手指习惯挪过的）中心的偏移，按键宽、键高算。
    struct Offset: Equatable {
        var dx: Double
        var dy: Double
    }

    private static let lock = NSLock()
    private static var keys: [Character] = []
    private static var offsets: [Offset] = []
    private static let limit = 64

    /// 打出一个字母（全键盘，小写）或数字 2–9（九宫格）。
    static func record(_ key: Character, _ offset: Offset) {
        lock.lock(); defer { lock.unlock() }
        keys.append(key)
        offsets.append(offset)
        if keys.count > limit {
            keys.removeFirst(keys.count - limit)
            offsets.removeFirst(offsets.count - limit)
        }
    }

    /// 删除键：撤掉最后一个。
    static func dropLast() {
        lock.lock(); defer { lock.unlock() }
        if !keys.isEmpty {
            keys.removeLast()
            offsets.removeLast()
        }
    }

    /// 上屏、换行、标点等：组字结束，清空。
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        keys.removeAll()
        offsets.removeAll()
    }

    /// 和输入串对得上时，返回每个键的落点；对不上（中间切过页、粘贴、选过拼音……）返回 nil。
    static func offsets(for input: String) -> [Offset]? {
        lock.lock(); defer { lock.unlock() }
        let wanted = Array(input)
        guard !wanted.isEmpty, keys.count >= wanted.count, Array(keys.suffix(wanted.count)) == wanted else { return nil }
        return Array(offsets.suffix(wanted.count))
    }

    #if DEBUG
    static func replaceForTesting(_ input: String, _ list: [Offset]) {
        lock.lock(); defer { lock.unlock() }
        keys = Array(input)
        offsets = list
    }
    #endif
}
