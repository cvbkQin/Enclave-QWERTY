import SwiftUI
import UIKit

/// 修改 AI 结果时的编辑菜单（T105，design/edit-select ES1，cvbk 11-26 16:53 交付）：自绘，样子照系统气泡。
/// 横排胶囊高 38、圆角 19；浅色近白（#FAFAFC 96%）黑字，深色 #3A3A3C 97% 白字；阴影 0 6 22（浅色 22%、深色 60%）；
/// 项之间 0.5pt 细线；每项左右 14、字 15。顶上 8pt 小箭头朝上，对着选中的字。
/// 弹在选中文字下面（往上弹会被键盘顶边切掉），位置由 ResultCard.editView 算。
struct CardEditMenu: View {
    var items: [KeyboardModel.CardMenuItem]
    /// 箭头尖在菜单里的横坐标。
    var arrowX: CGFloat
    var perform: (KeyboardModel.CardMenuItem) -> Void
    @Environment(\.colorScheme) private var colorScheme

    static let height: CGFloat = 38
    static let arrow: CGFloat = 8
    private static let itemPadding: CGFloat = 14
    private static let fontSize: CGFloat = 15

    /// 菜单宽：每项字宽 + 左右 14，加上项之间的细线。用来算靠边时往里挪多少。
    static func width(_ items: [KeyboardModel.CardMenuItem]) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize)
        let text = items.reduce(CGFloat(0)) { sum, item in
            sum + ceil((item.title as NSString).size(withAttributes: [.font: font]).width) + itemPadding * 2
        }
        return text + CGFloat(max(items.count - 1, 0)) * 0.5
    }

    private static let lightFill = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFC / 255, opacity: 0.96)
    private static let darkFill = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, opacity: 0.97)

    var body: some View {
        let dark = colorScheme == .dark
        let fill = dark ? Self.darkFill : Self.lightFill
        let width = Self.width(items)
        let tip = min(max(arrowX, Self.height / 2), width - Self.height / 2)
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.primary.opacity(dark ? 0.22 : 0.16)).frame(width: 0.5, height: 20)
                }
                Button { perform(item) } label: {
                    Text(item.title)
                        .font(.system(size: Self.fontSize))
                        .foregroundStyle(dark ? Color.white : Color.black)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Self.itemPadding)
                        .frame(height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CardEditMenuPressStyle(dark: dark))
            }
        }
        .frame(width: width, height: Self.height)
        .background(Capsule().fill(fill))
        .clipShape(Capsule())
        .background(alignment: .topLeading) {
            // 小箭头：画在胶囊上沿外面，尖朝上；和胶囊同色，阴影一起投。
            CardEditMenuArrow()
                .fill(fill)
                .frame(width: Self.arrow * 2, height: Self.arrow)
                .offset(x: tip - Self.arrow, y: -Self.arrow + 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.6 : 0.22), radius: 11, y: 6)
        .padding(.top, Self.arrow)
        .accessibilityElement(children: .contain)
    }

    /// 选中的底色、拖柄颜色，跟卡片功能色：问答天蓝 #38BDF8 28%（深色 #7DD3FC 30%）、拖柄 #0EA5E9；润色紫、帮回绿同理。
    static func selectionColors(_ tint: KeyboardModel.CardTint) -> (fill: Color, handle: Color) {
        switch tint {
        case .answer:
            return (HelpStyle.dynamicAlpha((0x38BDF8, 0.28), (0x7DD3FC, 0.30)), HelpStyle.dynamic(0x0EA5E9, 0x38BDF8))
        case .help:
            return (HelpStyle.dynamicAlpha((0x34D399, 0.30), (0x34D399, 0.30)), HelpStyle.dynamic(0x10B981, 0x34D399))
        case .polish:
            return (HelpStyle.dynamicAlpha((0x8B7CF6, 0.26), (0xB4A9FF, 0.30)), Brand.tagSelectedText)
        }
    }
}

/// 菜单项按下时垫一层浅灰（深色垫浅白），和系统菜单一样。
private struct CardEditMenuPressStyle: ButtonStyle {
    var dark: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? (dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)) : .clear)
    }
}

/// 朝上的小三角，尖角稍圆。
private struct CardEditMenuArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 1.5, y: rect.minY + 1))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 1.5, y: rect.minY + 1), control: CGPoint(x: rect.midX, y: rect.minY - 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
