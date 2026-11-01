import SwiftUI

/// App 和键盘共用的 AI 画面零件：混色底、识意放大镜图标、✨ 星星组、四角星。
/// App 里的功能演示（模拟键盘）也用它们，和真键盘长得一样。
enum AIVisuals {
    /// 金色 #FDE68A（和 Brand.gold 一样）。
    static let gold = Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255)
    /// 识意自动的紫蓝渐变（和 Brand.askAutoColors 一样）。
    static let askAuto = [Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255),
                          Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255),
                          Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)]
}

/// 柔和混色底（0.91 FB，方案 B）：亮一点的 115° 线性底上叠两团大而淡的椭圆光，照稿子的 CSS 换成径向渐变（百分比相对按钮自己的宽高）。
/// 扁平：没有小白星、顶上水光和外圈光。
/// ask 是识意自动时 ✨ 的蓝紫（MG2–MG5）；rewrite、answer 是两颗风格键，join 是收着时合成的那一颗（AB1–AB3，和 rewrite 同色）。
struct NebulaFill: View {
    enum Palette { case ask, rewrite, answer, join }

    /// 椭圆光：横竖半径（占宽高的比例）、中心、颜色、透明度。CSS 里写在前面的在上层，这里按 CSS 顺序列，画的时候倒过来。
    private typealias Glow = (rx: CGFloat, ry: CGFloat, x: CGFloat, y: CGFloat, color: UInt32, alpha: Double)

    var palette: Palette = .ask

    private var glows: [Glow] {
        switch palette {
        case .ask:
            return [(0.70, 0.90, 0.16, 0.30, 0xA855F7, 0.8), (0.65, 0.90, 0.86, 0.72, 0x0EA5E9, 0.75)]
        case .rewrite, .join:
            return [(0.70, 0.90, 0.18, 0.30, 0xA855F7, 0.7), (0.60, 0.90, 0.86, 0.74, 0x6366F1, 0.55)]
        case .answer:
            return [(0.70, 0.90, 0.18, 0.30, 0x38BDF8, 0.7), (0.60, 0.90, 0.86, 0.74, 0x3B82F6, 0.5)]
        }
    }

    /// 底：都是 115°。
    private var base: LinearGradient {
        let ends: (UInt32, UInt32)
        switch palette {
        case .ask: ends = (0x7C3AED, 0x2563EB)
        case .rewrite, .join: ends = (0x7C3AED, 0x6D5BF0)
        case .answer: ends = (0x0284C7, 0x0B8FD8)
        }
        return LinearGradient(colors: [Self.color(ends.0), Self.color(ends.1)],
                              startPoint: UnitPoint(x: 0, y: 0.25), endPoint: UnitPoint(x: 1, y: 0.75))
    }

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let glows = self.glows
            ZStack(alignment: .topLeading) {
                base
                ForEach(0..<glows.count, id: \.self) { k in
                    let g = glows[glows.count - 1 - k]
                    let c = Self.color(g.color).opacity(g.alpha)
                    EllipticalGradient(stops: [.init(color: c, location: 0), .init(color: c.opacity(0), location: 0.7)],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: 2 * g.rx * w, height: 2 * g.ry * h)
                        .position(x: g.x * w, y: g.y * h)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 旧的放大镜图标（方案 E3，design/ask-icon/ask-icon-e3.svg，24×24 画布），键盘上已不用，功能演示里还在用（演示晚点再改）：
/// 白色实心镜片的放大镜，镜片里一颗紫粉渐变四角星，右上、左上两颗小黄星。
struct MagnifierIcon: View {
    /// 和 ✨ 同款的四角星，24×24 画布里的路径。
    static func star(_ path: inout Path, center: CGPoint, scale k: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + (x - 12) * k, y: center.y + (y - 12) * k) }
        path.move(to: p(12, 3))
        path.addCurve(to: p(21, 12), control1: p(12.8, 8.5), control2: p(15.5, 11.2))
        path.addCurve(to: p(12, 21), control1: p(15.5, 12.8), control2: p(12.8, 15.5))
        path.addCurve(to: p(3, 12), control1: p(11.2, 15.5), control2: p(8.5, 12.8))
        path.addCurve(to: p(12, 3), control1: p(8.5, 11.2), control2: p(11.2, 8.5))
        path.closeSubpath()
    }

    /// 在 24×24 画布上的一颗星，按实际大小缩放。
    private struct Star: Shape {
        var center: CGPoint
        var scale: CGFloat
        func path(in rect: CGRect) -> Path {
            var path = Path()
            MagnifierIcon.star(&path, center: center, scale: scale)
            return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
        }
    }

    /// 放大镜手柄。
    private struct Handle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 15.41, y: 16.01))
            path.addLine(to: CGPoint(x: 19.41, y: 20.01))
            return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
        }
    }

    // 不用 Canvas：Canvas 在一些第三方 App 里整块画不出来（见 KeysView 键帽的说明），这里只用 Shape。
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            ZStack(alignment: .topLeading) {
                // 镜片：半径 6.8 的白圆加 2pt 白描边。
                Circle().fill(Color.white)
                    .frame(width: 15.6 * k, height: 15.6 * k)
                    .offset(x: (10 - 7.8) * k, y: (10.6 - 7.8) * k)
                Handle().stroke(Color.white, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                Star(center: CGPoint(x: 10, y: 10.6), scale: 0.44)
                    .fill(LinearGradient(colors: AIVisuals.askAuto, startPoint: UnitPoint(x: 6 / 24, y: 6.6 / 24),
                                         endPoint: UnitPoint(x: 14 / 24, y: 14.6 / 24)))
                Star(center: CGPoint(x: 20, y: 3.4), scale: 0.26).fill(AIVisuals.gold)
                Star(center: CGPoint(x: 2.6, y: 3.2), scale: 0.17).fill(AIVisuals.gold)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 润色按钮里的白色星星组：平时不动；润色中大星几乎不动（1.0↔1.08），小星错开闪（0.6↔1.4 倍、35%↔100%）带白色微光；
/// 完成时 1.2 秒内变金色放大一下再回白色。glowing 为 false（关了动画、减弱动态效果）时只轻微闪动。
struct PolishStars: View {
    var size: CGFloat
    var running: Bool
    var glowing: Bool
    var doneAt: Date?
    /// 星星的颜色：收着那一颗是黄色（#FDE68A），别处白色。
    var tint: Color = .white

    private static let stars: [(x: CGFloat, y: CGFloat, d: CGFloat, phase: Double)] = [
        (0.40, 0.58, 0.66, 0),
        (0.80, 0.18, 0.28, 0.0),
        (0.90, 0.60, 0.16, 0.35),
        (0.16, 0.14, 0.16, 0.6),
        (0.70, 0.92, 0.14, 0.2),
        (0.08, 0.88, 0.12, 0.8),
    ]

    var body: some View {
        if running || doneAt != nil {
            TimelineView(.animation) { context in
                cluster(now: context.date)
            }
        } else {
            cluster(now: nil)
        }
    }

    /// 完成闪金的进度（0…1），1.2 秒后为 nil。
    private func doneProgress(_ now: Date) -> Double? {
        guard let doneAt else { return nil }
        let p = now.timeIntervalSince(doneAt) / 1.2
        return p >= 0 && p < 1 ? p : nil
    }

    /// 25% 到顶，60% 回到 1.05，100% 回 1.0。
    private func bump(_ p: Double, peak: CGFloat) -> CGFloat {
        if p < 0.25 { return 1 + (peak - 1) * p / 0.25 }
        if p < 0.6 { return peak - (peak - 1.05) * (p - 0.25) / 0.35 }
        return 1.05 - 0.05 * (p - 0.6) / 0.4
    }

    private func cluster(now: Date?) -> some View {
        let time = now?.timeIntervalSinceReferenceDate
        let done = now.flatMap(doneProgress)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, star in
                let big = index == 0
                let wave = running ? time.map { (1 - cos(2 * .pi * ($0 / 1.6 + star.phase))) / 2 } ?? 0 : 0
                let scale: CGFloat = {
                    if let done { return bump(done, peak: big ? 1.22 : 1.3) }
                    if !running { return 1 }
                    if big { return 1 + 0.08 * wave }
                    return glowing ? 0.6 + 0.8 * wave : 1 - 0.2 * wave
                }()
                let opacity: Double = big || !running ? 1 : (glowing ? 0.35 + 0.65 * wave : 1 - 0.3 * wave)
                let gold = done.map { $0 < 0.6 ? 1.0 : 1 - ($0 - 0.6) / 0.4 } ?? 0
                FourPointStar()
                    .fill(tint)
                    .overlay(FourPointStar().fill(AIVisuals.gold).opacity(gold))
                    .frame(width: size * star.d, height: size * star.d)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .shadow(color: done != nil ? AIVisuals.gold.opacity(0.9 * gold) : .white.opacity(running && glowing ? 0.9 * wave : 0),
                            radius: 3)
                    .position(x: size * star.x, y: size * star.y)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 四角星，logo 星星组的一颗。
struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width / 2, h = rect.height / 2, k: CGFloat = 0.22
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - h))
        path.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        path.closeSubpath()
        return path
    }
}

/// 点按手势线稿（design/lab/tap-hand.svg）：白色填充，#1C1C1E 2.3pt 圆头圆角，淡阴影。深色模式不变。
struct CoachHandShape: Shape {
    static let size = CGSize(width: 51.5, height: 65.5)
    static let fingertip = CGPoint(x: 14.1, y: 1.8)

    /// 整只手：翻转、放大、旋转都绕指尖。
    static func hand(flipped: Bool, scale: CGFloat = 1, angle: Double = 0) -> some View {
        let anchor = UnitPoint(x: fingertip.x / size.width, y: fingertip.y / size.height)
        return ZStack {
            CoachHandShape(part: .outline).fill(Color.white)
            CoachHandShape(part: .outline)
                .stroke(Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            CoachHandShape(part: .knuckles)
                .stroke(Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 2)
        .scaleEffect(x: flipped ? -1 : 1, y: 1, anchor: anchor)
        .rotationEffect(.degrees(flipped ? -angle : angle), anchor: anchor)
        .scaleEffect(scale, anchor: anchor)
    }

    enum Part { case outline, knuckles }
    var part: Part

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.minY + y) }
        var path = Path()
        switch part {
        case .knuckles:
            path.move(to: p(22.07, 18.94)); path.addLine(to: p(23.18, 29.06))
            path.move(to: p(28.88, 18.39)); path.addLine(to: p(30.72, 27.77))
            path.move(to: p(37.71, 19.50)); path.addLine(to: p(38.99, 25.93))
        case .outline:
            path.move(to: p(17.11, 38.90))
            // 食指
            for point in [(10.21, 6.25), (10.34, 4.74), (11.05, 3.40), (12.21, 2.43), (13.66, 1.98), (15.17, 2.11),
                          (16.51, 2.82), (17.48, 3.98), (17.93, 5.43), (21.34, 15.45),
                          // 中指、无名指、小指的指节
                          (21.82, 14.24), (22.73, 13.29), (23.92, 12.76), (25.23, 12.72), (26.46, 13.18), (27.42, 14.06),
                          (27.98, 15.25), (28.05, 16.55), (28.64, 14.86), (29.84, 13.52), (31.45, 12.75), (33.25, 12.65),
                          (34.94, 13.24), (36.28, 14.43), (37.05, 16.05), (37.15, 17.84), (37.84, 16.22), (39.10, 14.99),
                          (40.73, 14.33), (42.49, 14.35), (44.11, 15.03), (45.34, 16.29), (46.00, 17.92), (45.98, 19.68)] {
                path.addLine(to: p(point.0, point.1))
            }
            path.addCurve(to: p(48.93, 44.69), control1: p(47.82, 28.33), control2: p(49.66, 37.52))
            path.addCurve(to: p(47.27, 58.49), control1: p(48.37, 48.74), control2: p(46.72, 51.50))
            path.addLine(to: p(25.20, 62.72))
            path.addCurve(to: p(11.77, 47.64), control1: p(22.99, 57.57), control2: p(19.13, 52.97))
            // 大拇指
            path.addLine(to: p(4.78, 42.49))
            path.addCurve(to: p(7.36, 33.48), control1: p(0.92, 39.54), control2: p(2.94, 33.48))
            path.addCurve(to: p(17.11, 38.90), control1: p(9.75, 33.48), control2: p(11.59, 34.76))
            path.closeSubpath()
        }
        return path
    }
}

/// 问答图标（v306，用户选 A）：金色对话气泡里一个白色问号，右下一颗四角星、右上一颗小星。
/// 问答键 17pt、问答类固定键 16pt、回答卡标题 15pt。矢量源 design/answer-key/ask-icon.svg（24×24），颜色固定，不随底色变。
/// 执行中（对齐清单第 61 条，照润色 ✨ 的路子）：气泡连问号 1→1.06 呼吸（1.6 秒）；问号下的点透明 .45↔1（相位错开 0.7）；
/// 右下大星、右上小星照润色小星闪（0.6↔1.4 倍、35%↔100%、白色微光，相位 0.35 / 0.7）；左上偶尔冒一颗白色小星（透明 .2→.9）。
/// glowing 为 false（关了发光动画、减弱动态效果）时只让两颗星轻微闪动。
struct AskIcon: View {
    var size: CGFloat
    var running = false
    var glowing = true
    /// 成功时 logo 轻弹的倍数，乘在气泡和右下大星上。
    var bounce: CGFloat = 1

    static let gold = LinearGradient(colors: [Color(red: 1, green: 0xE2 / 255, blue: 0x7A / 255),
                                              Color(red: 1, green: 0xB0 / 255, blue: 0x20 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        if running {
            TimelineView(.animation) { context in
                icon(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            icon(time: nil)
        }
    }

    /// 1.6 秒一个周期的 0…1 波，phase 错开。
    private static func wave(_ time: Double?, _ phase: Double) -> CGFloat {
        guard let time else { return 0 }
        return CGFloat((1 - cos(2 * .pi * (time / 1.6 + phase))) / 2)
    }

    private func icon(time: Double?) -> some View {
        let w = Self.wave(time, 0), w2 = Self.wave(time, 0.35), w3 = Self.wave(time, 0.7)
        let live = time != nil
        let full = live && glowing
        let bigScale = full ? 0.6 + 0.8 * w2 : 1
        let smallScale = full ? 0.6 + 0.8 * w3 : 1
        let bigOpacity = full ? 0.35 + 0.65 * w2 : (live ? 1 - 0.3 * w2 : 1)
        let smallOpacity = full ? 0.35 + 0.65 * w3 : (live ? 1 - 0.3 * w3 : 1)
        func anchor(_ x: CGFloat, _ y: CGFloat) -> UnitPoint { UnitPoint(x: x / 24, y: y / 24) }
        return ZStack {
            ZStack {
                Bubble().fill(Self.gold)
                Bubble().stroke(Color(red: 0xE8 / 255, green: 0x9A / 255, blue: 0), lineWidth: 0.6 * size / 24)
                Question().stroke(Color.white, style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round))
                Dot().fill(Color.white).opacity(full ? 0.45 + 0.55 * Double(w3) : 1)
            }
            .scaleEffect((full ? 1 + 0.06 * w : 1) * bounce, anchor: anchor(11, 10.5))
            Sparkle(cx: 20.2, cy: 15.8, r: 3.4).fill(Self.gold)
                .scaleEffect(bigScale * bounce, anchor: anchor(20.2, 15.8))
                .opacity(Double(bigOpacity))
                .shadow(color: .white.opacity(full ? 0.9 * Double(w2) : 0), radius: 1.5)
            Sparkle(cx: 21, cy: 3.6, r: 1.7).fill(Color(red: 1, green: 0xD5 / 255, blue: 0x4F / 255))
                .scaleEffect(smallScale, anchor: anchor(21, 3.6))
                .opacity(Double(smallOpacity))
                .shadow(color: .white.opacity(full ? 0.9 * Double(w3) : 0), radius: 1.5)
            if full {
                Sparkle(cx: 2.2, cy: 3, r: 1.2).fill(Color.white)
                    .scaleEffect(0.4 + 0.8 * w2, anchor: anchor(2.2, 3))
                    .opacity(0.2 + 0.7 * Double(w2))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 按 24×24 画布换算。
    private static func scale(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let k = min(rect.width, rect.height) / 24
        return { x, y in CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
    }

    private struct Bubble: Shape {
        func path(in rect: CGRect) -> Path {
            let p = AskIcon.scale(rect)
            let k = min(rect.width, rect.height) / 24
            var path = Path()
            path.move(to: p(3.5, 5.5))
            path.addArc(tangent1End: p(3.5, 2.5), tangent2End: p(6.5, 2.5), radius: 3 * k)
            path.addArc(tangent1End: p(18.5, 2.5), tangent2End: p(18.5, 5.5), radius: 3 * k)
            path.addArc(tangent1End: p(18.5, 15), tangent2End: p(15.5, 15), radius: 3 * k)
            path.addLine(to: p(10, 15))
            path.addLine(to: p(6, 18.6))
            path.addLine(to: p(6, 15))
            path.addQuadCurve(to: p(3.5, 12), control: p(3.5, 15))
            path.closeSubpath()
            return path
        }
    }

    private struct Question: Shape {
        func path(in rect: CGRect) -> Path {
            let p = AskIcon.scale(rect)
            var path = Path()
            // 圆弧：圆心 (11.10, 7.43)、半径 1.9，从 -179° 顺时针（屏幕上）转到 68°。
            let start = -178.98 * Double.pi / 180, end = 68.37 * Double.pi / 180
            for i in 0...16 {
                let a = start + (end - start) * Double(i) / 16
                let point = p(11.0997 + 1.9 * CGFloat(cos(a)), 7.4338 + 1.9 * CGFloat(sin(a)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.addCurve(to: p(10.9, 10.5), control1: p(11.2, 9.5), control2: p(10.9, 9.8))
            return path
        }
    }

    private struct Dot: Shape {
        func path(in rect: CGRect) -> Path {
            let p = AskIcon.scale(rect)
            let k = min(rect.width, rect.height) / 24
            let c = p(10.9, 12.6)
            return Path(ellipseIn: CGRect(x: c.x - 0.95 * k, y: c.y - 0.95 * k, width: 1.9 * k, height: 1.9 * k))
        }
    }

    /// 四角星：上下左右四个尖，腰收到 18%（同 svg）。
    private struct Sparkle: Shape {
        var cx: CGFloat, cy: CGFloat, r: CGFloat
        func path(in rect: CGRect) -> Path {
            let p = AskIcon.scale(rect)
            let w = r * 0.18
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
