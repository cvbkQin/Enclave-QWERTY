import CoreGraphics
import Foundation

/// 长按弹出的一排备选怎么排（T92，对齐清单第 87 条，design/popup-center）：
/// 默认那格正对按键中心、一弹出就选中；其余分左右两串，各自从近到远往两边排；
/// 一边排到键区边上放不下，多出来的接到另一边后面继续往外排，默认那格不动。
/// 这样手指不挪就是默认那格，一挪就从它旁边那格开始换，不会先跳一下。
struct AlternatesRow: Equatable {
    /// 默认那格：点一下就打的那个。
    let main: String
    /// 默认那格左边的，从近到远。
    let left: [String]
    /// 默认那格右边的，从近到远。
    let right: [String]

    /// 排好的一排：从左到右的选项、默认那格的位置、整排左边的 x。
    struct Arranged: Equatable {
        let options: [String]
        let selected: Int
        let minX: CGFloat
    }

    /// centerX：按键中心；containerWidth：键区宽（一排不出 0…containerWidth）。
    func arranged(centerX: CGFloat, cellWidth: CGFloat, containerWidth: CGFloat) -> Arranged {
        let mainX = centerX - cellWidth / 2
        let roomLeft = max(Int((mainX / cellWidth + 0.001).rounded(.down)), 0)
        let roomRight = max(Int(((containerWidth - mainX - cellWidth) / cellWidth + 0.001).rounded(.down)), 0)
        var left = self.left, right = self.right
        if left.count > roomLeft {
            right += left[roomLeft...]
            left = Array(left.prefix(roomLeft))
        } else if right.count > roomRight {
            left += right[roomRight...]
            right = Array(right.prefix(roomRight))
        }
        let options: [String] = Array(left.reversed()) + [main] + right
        var minX = mainX - cellWidth * CGFloat(left.count)
        // 两边加起来都放不下（键区太窄，正常用不到）：才整排往里收。
        let width = cellWidth * CGFloat(options.count)
        minX = min(max(minX, 0), max(containerWidth - width, 0))
        return Arranged(options: options, selected: left.count, minX: minX)
    }

    func uppercased() -> AlternatesRow {
        AlternatesRow(main: main.uppercased(), left: left.map { $0.uppercased() }, right: right.map { $0.uppercased() })
    }

    /// 全键盘字母：声调 / 变音朝键盘中间排（离手指最近的是一声），数字朝外边排。
    /// onLeftHalf：按键中心在键区左半边。
    static func letter(_ letter: String, digit: String?, accents: [String], onLeftHalf: Bool) -> AlternatesRow? {
        guard digit != nil || !accents.isEmpty else { return nil }
        let digits = digit.map { [$0] } ?? []
        return onLeftHalf
            ? AlternatesRow(main: letter, left: digits, right: accents)
            : AlternatesRow(main: letter, left: accents, right: digits)
    }

    /// 只用英文时底栏的逗号键：! ? ［,］ '。
    static let englishComma = AlternatesRow(main: ",", left: ["?", "!"], right: ["'"])
}
