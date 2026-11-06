import SwiftUI

/// AI 帮回（T16）的颜色：键、卡片、标签、胶囊、App 都用这一套绿。
enum HelpStyle {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ value: UInt32) -> UIColor {
            UIColor(red: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }

    /// 键、胶囊、选中的标签：#10B981 → #0E9F6E，135°。
    static let gradient = LinearGradient(colors: [hex(0x10B981), hex(0x0E9F6E)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let green = hex(0x10B981)
    /// 卡头「AI 帮回」、标题字。
    static let title = dynamic(0x0E9F6E, 0x34D399)
    /// 卡片边框 #6EE7B7、外圈 16% 绿光。
    static let border = dynamic(0x6EE7B7, 0x10B981)
    static let glow = hex(0x10B981, 0.16)
    /// 上屏后左键浅绿底深绿字、「方向」小标签。
    static let softFill = dynamic(0xD1FAE5, 0x064E3B)
    static let softText = dynamic(0x047857, 0x6EE7B7)
    /// 没选中的标签灰底灰字。
    static let tagFill = dynamic(0xE5E7EB, 0x3A3A3C)
    static let tagText = dynamic(0x6B7280, 0xA1A1AA)
    /// 写好没选中的标签底（HB19）：浅色 #D1FAE5，深色 #0B3B2C。
    static let doneFill = dynamic(0xD1FAE5, 0x0B3B2C)
    /// 写失败的标签：浅红底红字。
    static let failFill = dynamic(0xFEE2E2, 0x3B1418)
    static let failText = dynamic(0xDC2626, 0xF87171)
    /// 生成中正文的三条扫光占位条。
    static let placeholder = dynamic(0xD1FAE5, 0x14532D)
    /// 「回」右上角的红点。
    static let dot = hex(0xF43F5E)
    /// 帮回卡上润色键的星星（RG3 B）：和帮回同一个绿，不加白描边。
    static let star = hex(0x34D399)
    /// 十字里选中「^^ 颜文字」格。
    static let kaomojiCell = hex(0x5B4BE8)
}

/// 帮回 logo（design/help-reply/help-icon.svg）：绿渐变实心回复箭头 + 2pt 白描边，右上两颗白四角星（细绿边）。
/// running：箭头往左「回拨」1.6pt 再回来 + 1→1.05 呼吸（1.6 秒一轮），大星、小星错开闪（相位 .35 / .7），左下偶尔冒一颗白色小星。
struct HelpIcon: View {
    var size: CGFloat
    var running = false
    /// 键上（绿底）用：白描边照画，看得出箭头的轮廓。
    var bounce: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let arrowGradient = LinearGradient(colors: [HelpStyle.hex(0x4BE08A), HelpStyle.hex(0x07C160)],
                                              startPoint: UnitPoint(x: 2 / 24, y: 4 / 24), endPoint: UnitPoint(x: 21 / 24, y: 20 / 24))
    private static let starEdge = HelpStyle.hex(0x07C160)

    var body: some View {
        if running && !reduceMotion {
            TimelineView(.animation) { context in
                icon(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            icon(time: nil)
        }
    }

    private static func wave(_ time: Double?, _ phase: Double) -> CGFloat {
        guard let time else { return 0 }
        return CGFloat((1 - cos(2 * .pi * (time / 1.6 + phase))) / 2)
    }

    private func icon(time: Double?) -> some View {
        let k = size / 24
        let w = Self.wave(time, 0), w2 = Self.wave(time, 0.35), w3 = Self.wave(time, 0.7)
        let live = time != nil
        func anchor(_ x: CGFloat, _ y: CGFloat) -> UnitPoint { UnitPoint(x: x / 24, y: y / 24) }
        return ZStack {
            ZStack {
                Arrow().stroke(Color.white, style: StrokeStyle(lineWidth: 2 * k, lineJoin: .round))
                Arrow().fill(Color.white)
                Shaft().fill(Self.arrowGradient)
                Head().fill(Self.arrowGradient)
                Head().stroke(Self.arrowGradient, style: StrokeStyle(lineWidth: 0.8 * k, lineJoin: .round))
            }
            .scaleEffect((live ? 1 + 0.05 * w : 1) * bounce, anchor: anchor(12, 11))
            .offset(x: live ? -1.6 * k * w : 0)
            star(cx: 19.6, cy: 4.2, r: 3.2, k: k, wave: w2, live: live)
            star(cx: 14.8, cy: 2.2, r: 1.4, k: k, wave: w3, live: live)
            if live {
                Sparkle(cx: 3.2, cy: 20.2, r: 1.3).fill(Color.white)
                    .scaleEffect(0.4 + 0.8 * w2, anchor: anchor(3.2, 20.2))
                    .opacity(0.15 + 0.75 * Double(w2 * w3))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func star(cx: CGFloat, cy: CGFloat, r: CGFloat, k: CGFloat, wave: CGFloat, live: Bool) -> some View {
        ZStack {
            Sparkle(cx: cx, cy: cy, r: r).fill(Color.white)
            Sparkle(cx: cx, cy: cy, r: r).stroke(Self.starEdge, style: StrokeStyle(lineWidth: 0.55 * k, lineJoin: .round))
        }
        .scaleEffect(live ? 0.6 + 0.6 * wave : 1, anchor: UnitPoint(x: cx / 24, y: cy / 24))
        .opacity(live ? 0.45 + 0.55 * Double(wave) : 1)
        .shadow(color: .white.opacity(live ? 0.9 * Double(wave) : 0), radius: 1.2)
    }

    /// 按 24×24 画布换算。
    fileprivate static func scale(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let k = min(rect.width, rect.height) / 24
        return { x, y in CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
    }

    /// 箭身：前段粗 4.4（y 8.8–13.2），往右下弯到尾巴，尾巴圆头（圆心 20.2, 16.6，半径 1.7）。
    fileprivate struct Shaft: Shape {
        func path(in rect: CGRect) -> Path {
            let p = HelpIcon.scale(rect)
            let k = min(rect.width, rect.height) / 24
            var path = Path()
            path.move(to: p(8.6, 13.2))
            path.addLine(to: p(12.6, 13.2))
            path.addCurve(to: p(18.51, 16.81), control1: p(15.4, 13.02), control2: p(18.0, 14.2))
            path.addArc(center: p(20.2, 16.6), radius: 1.7 * k, startAngle: .degrees(172.9), endAngle: .degrees(-7.1), clockwise: true)
            path.addCurve(to: p(17.71, 9.79), control1: p(21.65, 13.4), control2: p(20.0, 11.0))
            path.addCurve(to: p(12.6, 8.81), control1: p(16.2, 9.05), control2: p(14.1, 8.86))
            path.addLine(to: p(8.6, 8.8))
            path.closeSubpath()
            return path
        }
    }

    /// 箭头三角：(2.6, 11)、(9.6, 4.8)、(9.6, 17.2)。
    fileprivate struct Head: Shape {
        func path(in rect: CGRect) -> Path {
            let p = HelpIcon.scale(rect)
            var path = Path()
            path.move(to: p(2.6, 11))
            path.addLine(to: p(9.6, 4.8))
            path.addLine(to: p(9.6, 17.2))
            path.closeSubpath()
            return path
        }
    }

    /// 白描边用：箭身 + 箭头一起。
    fileprivate struct Arrow: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Shaft().path(in: rect)
            path.addPath(Head().path(in: rect))
            return path
        }
    }

    /// 四角星：上下左右四个尖，腰收到 22%（同 svg）。
    fileprivate struct Sparkle: Shape {
        var cx: CGFloat, cy: CGFloat, r: CGFloat
        func path(in rect: CGRect) -> Path {
            let p = HelpIcon.scale(rect)
            let w = r * 0.22
            var path = Path()
            path.move(to: p(cx, cy - r))
            path.addCurve(to: p(cx + r, cy), control1: p(cx + w, cy - w), control2: p(cx + w, cy - w))
            path.addCurve(to: p(cx, cy + r), control1: p(cx + w, cy + w), control2: p(cx + w, cy + w))
            path.addCurve(to: p(cx - r, cy), control1: p(cx - w, cy + w), control2: p(cx - w, cy + w))
            path.addCurve(to: p(cx, cy - r), control1: p(cx - w, cy - w), control2: p(cx - w, cy - w))
            path.closeSubpath()
            return path
        }
    }
}

/// 帮回小方块「回」（App 历史列表左边）。
struct HelpBadge: View {
    var size: CGFloat = 22

    var body: some View {
        Text("回")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(HelpStyle.gradient))
            .accessibilityHidden(true)
    }
}
