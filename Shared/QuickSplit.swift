import CoreGraphics

/// 「常用 / 剪贴板」面板左右两栏的比例（对齐清单第 62 条，CW2）。split 是左栏（常用语）占的比例：
/// 默认各 1/2；松手在 1/3、1/2、2/3 附近（±4%）轻吸附；任一栏小于 1/6 收成 34pt 竖条（split 记成 0 或 1），点竖条恢复 1/2。
enum QuickSplit {
    static let standard: CGFloat = 0.5
    static let snaps: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3]
    static let snapRange: CGFloat = 0.04
    static let collapseBelow: CGFloat = 1.0 / 6
    /// 收起那一栏的竖条宽。
    static let stripWidth: CGFloat = 34

    /// 存着的比例；没存过、坏了都当 1/2。
    static func stored(_ value: Double?) -> CGFloat {
        guard let value, value.isFinite, value >= 0, value <= 1 else { return standard }
        return CGFloat(value)
    }

    /// 松手后定下来的比例和这次有没有吸附（吸附、收起时给一下轻触反馈）。
    static func settle(_ raw: CGFloat) -> (split: CGFloat, snapped: Bool) {
        let value = min(max(raw, 0), 1)
        if value < collapseBelow { return (0, true) }
        if value > 1 - collapseBelow { return (1, true) }
        if let snap = snaps.first(where: { abs($0 - value) <= snapRange }) { return (snap, true) }
        return (value, false)
    }

    /// 左栏收成竖条（0）、右栏收成竖条（1）。
    static func collapsedSide(_ split: CGFloat) -> Side? {
        if split <= 0 { return .phrases }
        if split >= 1 { return .clipboard }
        return nil
    }

    enum Side { case phrases, clipboard }

    /// 两栏的宽：available 是去掉中间分割线后剩下的宽；收起的那栏是竖条，展开的那栏至少也有竖条宽。
    static func widths(split: CGFloat, available: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let width = max(available, stripWidth * 2)
        switch collapsedSide(split) {
        case .phrases: return (stripWidth, width - stripWidth)
        case .clipboard: return (width - stripWidth, stripWidth)
        case nil:
            let left = min(max(width * split, stripWidth), width - stripWidth)
            return (left, width - left)
        }
    }

    /// 拖动时上方小气泡里的比例：在吸附点附近写分数（1/3、1/2、2/3），否则写百分比。
    static func fraction(_ value: CGFloat) -> String {
        let names: [(CGFloat, String)] = [(1.0 / 3, "1/3"), (0.5, "1/2"), (2.0 / 3, "2/3")]
        if let hit = names.first(where: { abs($0.0 - value) <= snapRange }) { return hit.1 }
        return "\(Int((value * 100).rounded()))%"
    }
}
