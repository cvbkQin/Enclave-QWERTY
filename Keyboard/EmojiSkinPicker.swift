import SwiftUI
import UIKit

/// 表情长按选肤色（ES 稿，design/emoji-skin/说明.md）：
/// 单人按住 0.35 秒在手指上方弹 6 格（原色 | 5 种肤色），不松手左右滑选、松手上屏；
/// 两人组合弹一块大面板，松手不收，上下两排分别选两人肤色，点右边预览上屏。

/// 正在选肤色的那个表情和弹层的位置（坐标都在 SymbolPanel 的 emoji 区里）。
struct SkinPick: Equatable {
    let item: EmojiCatalog.Item
    /// 按住那一格。
    let cell: CGRect
    /// 弹层的位置和大小。
    let frame: CGRect
    /// 弹层在格子上面（带小尖）；上面放不下时往下挪盖住那一格，不画小尖。
    let above: Bool
    /// 单人：高亮那一格（0 原色，1–5 肤色）；手指滑出上下 30pt 时是 nil，松手不上屏。
    var index: Int?
    /// 两人：左、右两人选的肤色 1–5。
    var left: Int?
    var right: Int?

    var choices: [String] { [item.emoji] + item.tones.prefix(5).map(\.emoji) }

    var pairEmoji: String? {
        guard let left, let right else { return nil }
        return item.tone("\(left)\(right)")
    }
}

enum SkinPickLayout {
    // 单人：内边距 4，每格 42×46，原色后一条 1pt 竖线。
    static let pad: CGFloat = 4
    static let cellWidth: CGFloat = 42
    static let cellHeight: CGFloat = 46
    static let divider: CGFloat = 1
    static let singleSize = CGSize(width: pad * 2 + cellWidth * 6 + divider, height: pad * 2 + cellHeight)
    // 两人：原色一格、竖线、两排各 5 格（前面「左」「右」）、预览 62×90。
    static let pairCell = CGSize(width: 40, height: 45)
    static let pairOriginal: CGFloat = 48
    static let pairLabel: CGFloat = 14
    static let preview = CGSize(width: 62, height: 90)
    static let gap: CGFloat = 6
    static let pairSize = CGSize(
        width: pad * 2 + pairOriginal + gap + divider + gap + pairLabel + pairCell.width * 5 + gap + preview.width,
        height: pad * 2 + pairCell.height * 2)
    /// 弹层底边离按住那一格上边。
    static let lift: CGFloat = 6
    static let arrow = CGSize(width: 14, height: 8)
    /// 离键盘左右边。
    static let edge: CGFloat = 8
    /// 手指离开弹层上下超过这么多就取消。
    static let cancel: CGFloat = 30

    /// 单人第 i 格的中心 x（相对弹层左边）。
    static func singleCenter(_ i: Int) -> CGFloat {
        pad + cellWidth * CGFloat(i) + cellWidth / 2 + (i >= 1 ? divider : 0)
    }

    /// 弹层放在哪：centerX 对准手指的那个点相对弹层左边的位置；左右放不下往里挪；上面放不下往下挪盖住那一格。
    static func place(size: CGSize, cell: CGRect, centerX: CGFloat, width: CGFloat) -> (CGRect, Bool) {
        var x = cell.midX - centerX
        x = min(max(x, edge), max(edge, width - edge - size.width))
        var y = cell.minY - lift - arrow.height - size.height
        let above = y >= 0
        if !above { y = max(0, cell.midY - size.height / 2) }
        return (CGRect(origin: CGPoint(x: x, y: y), size: size), above)
    }

    /// 单人：手指所在的列。
    static func singleIndex(at point: CGPoint, in frame: CGRect) -> Int? {
        guard point.y >= frame.minY - cancel, point.y <= frame.maxY + arrow.height + cancel else { return nil }
        let x = point.x - frame.minX - pad
        let i = x < cellWidth ? 0 : Int((x - divider) / cellWidth)
        return min(max(i, 0), 5)
    }
}

enum SkinPickStyle {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    /// 角标红点 #FF3B30 / 深色 #FF453A。
    static let badge = dynamic(rgb(0xFF3B30), rgb(0xFF453A))
    /// 按住那一格的浅灰底。
    static let pressed = dynamic(UIColor(white: 0, alpha: 0.08), UIColor(white: 1, alpha: 0.10))
    /// 弹层底：白 / #5A5A5E。
    static let fill = dynamic(.white, rgb(0x5A5A5E))
    /// 高亮实底 #5B4BE8 / #B4A9FF。
    static let accent = dynamic(rgb(0x5B4BE8), rgb(0xB4A9FF))
    /// 两人选中格：浅紫底 #E4E0FC / #2E2766。
    static let selectedFill = dynamic(rgb(0xE4E0FC), rgb(0x2E2766))
    /// 预览「点这里上屏」：浅色白字，深色（浅紫底）黑字。
    static let previewText = dynamic(.white, .black)
    static let divider = dynamic(rgb(0xD1D1D6), rgb(0x6E6E73))
}

/// 面板里一格表情。能选肤色的带红点，按住 0.35 秒交给面板弹选肤色；单击上屏。
struct EmojiCell: View {
    let emoji: String
    let badge: Bool
    /// 弹层正开着、是这一格。
    let active: Bool
    let tap: () -> Void
    let begin: (CGRect) -> Void
    let move: (CGPoint) -> Void
    let end: () -> Void

    @GestureState private var pressing = false

    var body: some View {
        Text(emoji).font(.system(size: 30)).frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(pressing || active ? SkinPickStyle.pressed : Color.clear))
            .overlay(alignment: .bottomTrailing) {
                if badge {
                    Circle().fill(SkinPickStyle.badge).frame(width: 4.5, height: 4.5).padding(5)
                }
            }
            .overlay(GeometryReader { geo in
                Color.clear.contentShape(Rectangle()).gesture(gesture(geo))
            })
    }

    private func gesture(_ geo: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(SymbolPanel.space)))
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if let drag { move(drag.location) } else { begin(geo.frame(in: .named(SymbolPanel.space))) }
            }
            .onEnded { value in
                if case .second(true, _) = value { end() }
            }
            .exclusively(before: TapGesture().onEnded { tap() })
    }
}

/// 单人：一排 6 格，高亮跟着手指。
struct SingleSkinBar: View {
    let pick: SkinPick

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pick.choices.enumerated()), id: \.offset) { i, emoji in
                if i == 1 {
                    SkinPickStyle.divider.frame(width: SkinPickLayout.divider, height: SkinPickLayout.cellHeight - 16)
                }
                Text(emoji).font(.system(size: 31))
                    .frame(width: SkinPickLayout.cellWidth, height: SkinPickLayout.cellHeight)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(pick.index == i ? SkinPickStyle.accent : Color.clear))
            }
        }
        .padding(SkinPickLayout.pad)
        .modifier(SkinBubble(pick: pick))
    }
}

/// 两人：原色 | 左、右两排各 5 格 | 预览。
struct PairSkinPanel: View {
    let pick: SkinPick
    let choose: (_ left: Int?, _ right: Int?) -> Void
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { commit(pick.item.emoji) } label: {
                VStack(spacing: 4) {
                    Text(pick.item.emoji).font(.system(size: 31))
                    Text(L("原色", "Default", "デフォルト")).font(.system(size: 10)).foregroundStyle(Color.secondary)
                }
                .frame(width: SkinPickLayout.pairOriginal, height: SkinPickLayout.pairCell.height * 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer().frame(width: SkinPickLayout.gap)
            SkinPickStyle.divider.frame(width: SkinPickLayout.divider, height: SkinPickLayout.pairCell.height * 2 - 16)
            Spacer().frame(width: SkinPickLayout.gap)
            VStack(spacing: 0) {
                row(L("左", "L", "左"), left: true)
                row(L("右", "R", "右"), left: false)
            }
            Spacer().frame(width: SkinPickLayout.gap)
            preview
        }
        .padding(SkinPickLayout.pad)
        .modifier(SkinBubble(pick: pick))
    }

    private func row(_ label: String, left: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.secondary)
                .frame(width: SkinPickLayout.pairLabel)
            ForEach(1...5, id: \.self) { tone in
                let selected = (left ? pick.left : pick.right) == tone
                // 这一排的人用这格的肤色，另一个人用另一排选中的（还没选就同色）。
                let code = left ? "\(tone)\(pick.right ?? tone)" : "\(pick.left ?? tone)\(tone)"
                Button {
                    if left { choose(tone, pick.right) } else { choose(pick.left, tone) }
                } label: {
                    Text(pick.item.tone(code) ?? pick.item.emoji).font(.system(size: 28))
                        .frame(width: SkinPickLayout.pairCell.width, height: SkinPickLayout.pairCell.height)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? SkinPickStyle.selectedFill : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? SkinPickStyle.accent : Color.clear, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var preview: some View {
        let ready = pick.pairEmoji
        return Button { if let ready { commit(ready) } } label: {
            VStack(spacing: 6) {
                Text(ready ?? pick.item.emoji).font(.system(size: 34)).opacity(ready == nil ? 0.35 : 1)
                Text(ready == nil ? L("两边都选", "Pick both", "両方選択") : L("点这里上屏", "Tap to insert", "タップで入力"))
                    .font(.system(size: 10, weight: ready == nil ? .regular : .semibold))
                    .foregroundStyle(ready == nil ? Color.secondary : SkinPickStyle.previewText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: SkinPickLayout.preview.width, height: SkinPickLayout.preview.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ready == nil ? Color.clear : SkinPickStyle.accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ready == nil)
    }
}

/// 弹层的底、圆角、阴影和对着手指的小尖（盖住那一格时不画）。
private struct SkinBubble: ViewModifier {
    let pick: SkinPick

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(SkinPickStyle.fill))
            .overlay(alignment: .bottomLeading) {
                if pick.above {
                    SkinArrow().fill(SkinPickStyle.fill)
                        .frame(width: SkinPickLayout.arrow.width, height: SkinPickLayout.arrow.height)
                        .offset(x: pick.cell.midX - pick.frame.minX - SkinPickLayout.arrow.width / 2,
                                y: SkinPickLayout.arrow.height)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
            .frame(width: pick.frame.width, height: pick.frame.height)
    }
}

private struct SkinArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
