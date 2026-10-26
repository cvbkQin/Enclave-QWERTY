import Foundation

/// 场景实验室「一键应用」后键盘上的小手指引导（NH1–NH6）。
/// App 点「一键应用」时写一个「刚应用过」标记，键盘下次出现时读到就放一次引导，读完清掉；超过 10 分钟没用就作废。
struct LabCoachMark: Codable {
    /// 引导走哪几步：没要求的场景 ✨ → 替换，有要求的场景 执行 → 替换，错字校对 ✨ → ▲▼。
    enum Flow: String, Codable {
        case sparkle, run, proofread
    }

    var scene: Int
    var flow: Flow
    var at: Date

    private static let key = "lab.coach.v1"
    private static let lifetime: TimeInterval = 10 * 60

    static func write(scene: Int, flow: Flow) {
        guard let data = try? JSONEncoder().encode(LabCoachMark(scene: scene, flow: flow, at: Date())) else { return }
        SharedStorage.defaults.set(data, forKey: key)
    }

    /// 取出并清掉；过期的也清掉，返回 nil。
    static func take() -> LabCoachMark? {
        guard let data = SharedStorage.defaults.data(forKey: key) else { return nil }
        SharedStorage.defaults.removeObject(forKey: key)
        guard let mark = try? JSONDecoder().decode(LabCoachMark.self, from: data),
              Date().timeIntervalSince(mark.at) < lifetime else { return nil }
        return mark
    }
}
