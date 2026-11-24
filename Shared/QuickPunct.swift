import Foundation

/// 26 键空格旁的「，。」键（对齐清单第 80 条，设计稿 design/punct26）：点一下逗号，往上划句号，长按弹一排标点。
/// 中文出全角，英文出半角。只在全键盘的字母页有；九宫格本来就有「，。?!」键。
enum QuickPunct {
    /// 点一下打出的。
    static func tap(chinese: Bool) -> String { chinese ? "，" : "," }
    /// 往上划打出的（键上左上角的小字）。
    static func up(chinese: Bool) -> String { chinese ? "。" : "." }
    /// 长按弹出的一排（T92）：点一下打的那个正对按键、默认选中，左边从近到远「？！、」，右边「。；」。
    /// 弹出来从左到右是 、 ！ ？ ［，］ 。 ；（英文 ' ! ? ［,］ . ;），放在空格左边、右边都是这个顺序。
    static func row(chinese: Bool) -> AlternatesRow {
        chinese
            ? AlternatesRow(main: "，", left: ["？", "！", "、"], right: ["。", "；"])
            : AlternatesRow(main: ",", left: ["?", "!", "'"], right: [".", ";"])
    }
}

/// 「，。」键放在空格哪边（设置 › 键盘 › 中文布局，「打法」下面一行），默认右边。键盘手感类设置，iCloud 不同步。
enum QuickPunctSide: String, Codable, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }

    var title: String {
        self == .left ? L("空格左边", "Left of space", "スペースの左") : L("空格右边", "Right of space", "スペースの右")
    }
}
