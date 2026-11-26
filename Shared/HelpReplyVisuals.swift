import SwiftUI

/// AI 帮回（T16，帮回并入润色）的颜色：键、按钮、小标、App 历史都用这一套绿。
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

    static let green = hex(0x10B981)
    /// 卡头「AI 帮回」、标题字。
    static let title = dynamic(0x0E9F6E, 0x34D399)
    /// 剪贴板长按菜单「帮回这条」的深绿字。
    static let softText = dynamic(0x047857, 0x6EE7B7)
    /// 润色下拉框里帮回那一行，有待回的复制时的浅绿底：浅色 #D1FAE5，深色 #0B3B2C。
    static let doneFill = dynamic(0xD1FAE5, 0x0B3B2C)
    /// 回答卡卡头的「回」小标（帮回并入润色 §7）：底 #D1FAE5、字 #047857；深色底 rgba(16,185,129,.18)、字 #6EE7B7。
    static let badgeFill = dynamicAlpha((0xD1FAE5, 1), (0x10B981, 0.18))
    static let badgeText = dynamic(0x047857, 0x6EE7B7)
    /// 回答卡上是帮回写的一版时（cvbk 11-26：调用的什么功能就用什么颜色）：整块描边 #10B981 / 深色 #34D399。
    static let ring = dynamic(0x10B981, 0x34D399)
    /// 帮回生成中卡片边框的流光：绿一圈（照问答的天蓝一圈）。
    static let flowRing = [hex(0x059669), hex(0x10B981), hex(0xA7F3D0), hex(0x34D399)]
    /// 卡片左边替换键、「完成修改」：帮回绿 135° #22C08A → #0E9F6E（和帮回键同色）。
    static let keyColors = [hex(0x22C08A), hex(0x0E9F6E)]
    /// 帮回键（T96）：和润色、问答同样的星云底，换成帮回绿 #22C08A → #0E9F6E；执行中键下绿色投影。
    static let keyShadow = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.55)

    static func dynamicAlpha(_ light: (UInt32, CGFloat), _ dark: (UInt32, CGFloat)) -> Color {
        func color(_ value: (UInt32, CGFloat)) -> UIColor {
            UIColor(red: CGFloat(value.0 >> 16 & 0xFF) / 255, green: CGFloat(value.0 >> 8 & 0xFF) / 255,
                    blue: CGFloat(value.0 & 0xFF) / 255, alpha: value.1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
}

/// 帮回 logo（T96，design/help-reply/entry-v2/hl.html 第五节）：回复箭头缩到 0.78 放在偏左下（外框 x 2.4–17.5、y 7.6–18.1），
/// 5 颗四角星绕一圈，照润色 ✨ 的排法（右上大、右中、左上、右下、左下）。
/// - 彩色版（App、⌄ 里、开关关着时润色键上）：绿渐变 #4BE08A → #07C160 箭头加 2pt 白描边，金星 #FFD54F 描 0.45 #E89A00，和问答图标的小星一样。
/// - white（键上，绿底）：白箭头、淡金星 #FDE68A，和润色键上的金色 ✦ 一样。
/// running：箭头 1 → 1.05 呼吸、往左「回拨」1.2pt；5 颗星错开闪（0.6 ↔ 1.4 倍、35% ↔ 100%、白色微光），1.6 秒一轮，照 PolishStars 的小星。
/// doneAt：成功那一刻起 1.2 秒星星闪金、轻轻放大，照 PolishStars 完成时。bounce：整个 logo 的轻弹（1 → 1.25 → 1.05 → 1）。
struct HelpIcon: View {
    var size: CGFloat
    var running = false
    var bounce: CGFloat = 1
    var white = false
    var doneAt: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let arrowGradient = LinearGradient(colors: [HelpStyle.hex(0x4BE08A), HelpStyle.hex(0x07C160)],
                                              startPoint: UnitPoint(x: 2 / 24, y: 7 / 24), endPoint: UnitPoint(x: 18 / 24, y: 19 / 24))
    private static let whiteFill = LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom)
    /// 圆心、半径（24×24 画布）、执行中的相位。
    static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, phase: Double)] = [
        (19.6, 4.6, 3.1, 0), (22.2, 13.4, 1.55, 0.35), (4.2, 4.0, 1.5, 0.6), (17.4, 21.8, 1.3, 0.2), (2.4, 21.2, 1.1, 0.8),
    ]
    private static let lightGold = HelpStyle.hex(0xFDE68A)
    private static let gold = HelpStyle.hex(0xFFD54F)
    private static let goldEdge = HelpStyle.hex(0xE89A00)

    var body: some View {
        if (running || doneAt != nil) && !reduceMotion {
            TimelineView(.animation) { context in
                icon(now: context.date)
            }
        } else {
            icon(now: nil)
        }
    }

    private static func wave(_ time: Double, _ phase: Double) -> CGFloat {
        CGFloat((1 - cos(2 * .pi * (time / 1.6 + phase))) / 2)
    }

    /// 成功后闪金的进度（0…1），1.2 秒后为 nil。
    private func doneProgress(_ now: Date?) -> Double? {
        guard let now, let doneAt else { return nil }
        let p = now.timeIntervalSince(doneAt) / 1.2
        return p >= 0 && p < 1 ? p : nil
    }

    private func icon(now: Date?) -> some View {
        let k = size / 24
        let time = running ? now?.timeIntervalSinceReferenceDate : nil
        let w = time.map { Self.wave($0, 0) } ?? 0
        let done = doneProgress(now)
        let gold = done.map { $0 < 0.6 ? 1.0 : 1 - ($0 - 0.6) / 0.4 } ?? 0
        let fill = white ? Self.whiteFill : Self.arrowGradient
        return ZStack {
            ZStack {
                if !white {
                    Arrow().stroke(Color.white, style: StrokeStyle(lineWidth: 2 * 0.78 * k, lineJoin: .round))
                    Arrow().fill(Color.white)
                }
                Shaft().fill(fill)
                Head().fill(fill)
                Head().stroke(fill, style: StrokeStyle(lineWidth: 0.8 * 0.78 * k, lineJoin: .round))
            }
            .scaleEffect(1 + 0.05 * w, anchor: UnitPoint(x: 11 / 24, y: 13 / 24))
            .offset(x: -1.2 * k * w)
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                let ww = time.map { Self.wave($0, star.phase) } ?? 0
                let live = time != nil
                let pop: CGFloat = done.map { 1 + 0.3 * CGFloat(sin(.pi * min(1, $0 * 1.2 / 0.7))) } ?? 1
                ZStack {
                    Sparkle(cx: star.x, cy: star.y, r: star.r).fill(white ? Self.lightGold : Self.gold)
                    if !white {
                        Sparkle(cx: star.x, cy: star.y, r: star.r).stroke(Self.goldEdge, style: StrokeStyle(lineWidth: 0.45 * k, lineJoin: .round))
                    }
                }
                .scaleEffect((live ? 0.6 + 0.8 * ww : 1) * pop, anchor: UnitPoint(x: star.x / 24, y: star.y / 24))
                .opacity(live ? 0.35 + 0.65 * Double(ww) : 1)
                .shadow(color: done != nil ? Self.lightGold.opacity(0.9 * gold) : .white.opacity(live ? 0.9 * Double(ww) : 0),
                        radius: 1.2 + 1.5 * gold)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(bounce)
        .accessibilityHidden(true)
    }

    /// 按 24×24 画布换算。
    fileprivate static func scale(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let k = min(rect.width, rect.height) / 24
        return { x, y in CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
    }

    /// 箭头在画布上的位置：原来占满的箭头缩到 0.78，(2.6, 4.8) 挪到 (2.4, 7.6)，给一圈星星让出地方。
    fileprivate static let arrowScale: CGFloat = 0.78
    fileprivate static func arrowPoint(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let p = scale(rect)
        return { x, y in p(2.4 + (x - 2.6) * arrowScale, 7.6 + (y - 4.8) * arrowScale) }
    }

    /// 箭身（缩放前的画布）：前段粗 4.4（y 8.8–13.2），往右下弯到尾巴，尾巴圆头（圆心 20.2, 16.6，半径 1.7）。
    fileprivate struct Shaft: Shape {
        func path(in rect: CGRect) -> Path {
            let p = HelpIcon.arrowPoint(rect)
            let k = min(rect.width, rect.height) / 24 * HelpIcon.arrowScale
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

    /// 箭头三角（缩放前的画布）：(2.6, 11)、(9.6, 4.8)、(9.6, 17.2)。
    fileprivate struct Head: Shape {
        func path(in rect: CGRect) -> Path {
            let p = HelpIcon.arrowPoint(rect)
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
