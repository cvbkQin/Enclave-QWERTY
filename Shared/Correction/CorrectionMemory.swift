import Foundation

/// 纠错的开关、拒绝记忆和学习，存在 App Group（App 里改开关，键盘里读写记忆），全在本机。
enum CorrectionMemory {
    private static let qwertyKey = "correction.qwerty"
    private static let nineKeyKey = "correction.nineKey"
    private static let rejectedKey = "correction.rejected"
    private static let biasKey = "correction.bias"
    /// 撤回过的输入最多记这么多条，旧的先忘。
    private static let rejectedLimit = 300
    private static let biasLimit = 500

    /// 「自动纠错」开关，全键盘、九宫格各一个，默认开。
    static func isEnabled(nineKey: Bool) -> Bool {
        SharedStorage.defaults.object(forKey: nineKey ? nineKeyKey : qwertyKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, nineKey: Bool) {
        SharedStorage.defaults.set(enabled, forKey: nineKey ? nineKeyKey : qwertyKey)
    }

    /// 纠正的词上屏后马上按删除撤回过：同样的输入以后不再纠（iOS 被投诉过「删了重打还是被改」）。
    static func isRejected(_ input: String) -> Bool {
        rejected.contains(input)
    }

    static func reject(_ input: String) {
        var list = rejected.filter { $0 != input }
        list.append(input)
        SharedStorage.defaults.set(Array(list.suffix(rejectedLimit)), forKey: rejectedKey)
    }

    private static var rejected: [String] {
        SharedStorage.defaults.stringArray(forKey: rejectedKey) ?? []
    }

    /// 门槛要多加多少（nats）：选过纠正的词就降低（下次更容易纠），总选原样的词就提高。
    static func bias(_ input: String) -> Double {
        biases[input] ?? 0
    }

    /// 选了纠正的词。
    static func accepted(_ input: String) {
        adjust(input, by: -1, low: -3, high: 6)
    }

    /// 纠正的词放在首选，却选了原样的词。
    static func declined(_ input: String) {
        adjust(input, by: 2, low: -3, high: 6)
    }

    private static var biases: [String: Double] {
        SharedStorage.defaults.dictionary(forKey: biasKey) as? [String: Double] ?? [:]
    }

    private static func adjust(_ input: String, by step: Double, low: Double, high: Double) {
        var all = biases
        all[input] = min(high, max(low, (all[input] ?? 0) + step))
        // 超出上限时先丢掉调整得最少的。
        if all.count > biasLimit {
            for key in all.sorted(by: { abs($0.value) < abs($1.value) }).prefix(all.count - biasLimit).map(\.key) {
                all.removeValue(forKey: key)
            }
        }
        SharedStorage.defaults.set(all, forKey: biasKey)
    }
}
