import Foundation

/// 使用指引（原场景实验室）「一键应用」后键盘上的小手指引导（NH1–NH6、LM1–LM8）。
/// App 点「一键应用」时写一个「刚应用过」标记，键盘下次出现时读到就按标记设好键盘、放一次引导，读完清掉；超过 10 分钟没用就作废。
struct LabCoachMark: Codable {
    /// 小手要指的按钮，按顺序一步步走。
    enum Step: String, Codable {
        case sparkle, run, versions, replace, insert
    }

    var scene: Int
    var steps: [Step]
    /// 结果区展开（替换 / 插入场景）；快速场景收起。
    var expanded: Bool
    /// 提示词面板打开（有要求的场景）。
    var menuOpen: Bool
    var at = Date()

    private static let key = "lab.coach.v2"
    private static let lifetime: TimeInterval = 10 * 60

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SharedStorage.defaults.set(data, forKey: Self.key)
    }

    /// 取出并清掉；过期的也清掉，返回 nil。
    static func take() -> LabCoachMark? {
        guard let data = SharedStorage.defaults.data(forKey: key) else { return nil }
        SharedStorage.defaults.removeObject(forKey: key)
        guard let mark = try? JSONDecoder().decode(LabCoachMark.self, from: data),
              Date().timeIntervalSince(mark.at) < lifetime, !mark.steps.isEmpty else { return nil }
        return mark
    }
}
