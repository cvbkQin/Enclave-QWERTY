import Foundation

/// iPad 全宽 9 键（PK3、PK4）：九键靠哪一边。另一边是功能键一列和联想 / 候选。
/// 默认右边（11-22 cvbk「九宫格默认放在右侧」）：和 iPhone 横屏九宫格一样，大多数人右手打字，候选从左往右看接着输入框。
enum NineKeySide: String, Codable, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }

    var title: String {
        self == .left ? L("左边", "Left", "左") : L("右边", "Right", "右")
    }
}
