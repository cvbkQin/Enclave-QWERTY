import SwiftUI

/// App 和键盘共用的 AI 画面零件：星团底、识意放大镜图标、✨ 星星组、四角星。
/// App 里的功能演示（模拟键盘）也用它们，和真键盘长得一样。
enum AIVisuals {
    /// 金色 #FDE68A（和 Brand.gold 一样）。
    static let gold = Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255)
    /// 识意自动的紫蓝渐变（和 Brand.askAutoColors 一样）。
    static let askAuto = [Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255),
                          Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255),
                          Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)]
}

/// 星团底：线性底上叠四团椭圆光和三粒小白星，照稿子的 CSS 换成多层径向渐变（百分比相对按钮自己的宽高）。
/// ask 是识意自动时 ✨ 的蓝紫（MG2–MG5）；rewrite、answer 是两颗风格键，join 是收着时合成的那一颗（AB1–AB3）。
/// 0.91 起展开后分出来的三颗（ask、rewrite、answer）改成扁平纯色，只有收着的 join 还是星团。
struct NebulaFill: View {
    enum Palette { case ask, rewrite, answer, join }

    /// 椭圆光：横竖半径（占宽高的比例）、中心、颜色、透明度。CSS 里写在前面的在上层，这里按 CSS 顺序列，画的时候倒过来。
    private typealias Glow = (rx: CGFloat, ry: CGFloat, x: CGFloat, y: CGFloat, color: UInt32, alpha: Double)
    /// 小白星：位置、透明度、半径。
    private typealias Star = (x: CGFloat, y: CGFloat, alpha: Double, r: CGFloat)

    var palette: Palette = .ask

    private var glows: [Glow] {
        switch palette {
        case .ask:
            return [(0.60, 0.75, 0.18, 0.28, 0x8B5CF6, 1), (0.55, 0.80, 0.62, 0.18, 0x38BDF8, 1),
                    (0.50, 0.70, 0.40, 0.88, 0x0EA5E9, 1), (0.55, 0.80, 0.90, 0.70, 0xA855F7, 1)]
        case .rewrite:
            return [(0.60, 0.75, 0.18, 0.28, 0xA855F7, 1), (0.50, 0.70, 0.66, 0.16, 0xC084FC, 0.75),
                    (0.50, 0.70, 0.42, 0.90, 0x7C3AED, 1), (0.55, 0.80, 0.92, 0.72, 0x9333EA, 1)]
        case .answer:
            return [(0.60, 0.75, 0.18, 0.28, 0x38BDF8, 1), (0.50, 0.70, 0.66, 0.16, 0x67E8F9, 0.70),
                    (0.50, 0.70, 0.42, 0.90, 0x0EA5E9, 1), (0.55, 0.80, 0.92, 0.72, 0x3B82F6, 1)]
        case .join:
            return [(0.40, 0.75, 0.14, 0.30, 0x8B5CF6, 1), (0.40, 0.70, 0.50, 0.14, 0xA855F7, 0.80),
                    (0.45, 0.70, 0.70, 0.90, 0x7C3AED, 1), (0.35, 0.80, 0.94, 0.70, 0x9333EA, 1)]
        }
    }

    private var stars: [Star] {
        switch palette {
        case .ask: return [(0.74, 0.30, 0.85, 0.6), (0.22, 0.72, 0.70, 0.5), (0.88, 0.78, 0.60, 0.5)]
        case .rewrite: return [(0.74, 0.30, 0.8, 0.6), (0.24, 0.74, 0.8, 0.5), (0.88, 0.80, 0.8, 0.5)]
        case .answer: return [(0.72, 0.28, 0.8, 0.6), (0.26, 0.76, 0.8, 0.5), (0.90, 0.78, 0.8, 0.5)]
        case .join: return [(0.30, 0.22, 0.8, 0.6), (0.62, 0.78, 0.8, 0.5), (0.84, 0.30, 0.8, 0.5)]
        }
    }

    /// 底：ask、rewrite、answer 是 115°，join 是 90°。
    private var base: LinearGradient {
        let angled = (UnitPoint(x: 0, y: 0.25), UnitPoint(x: 1, y: 0.75))
        func stops(_ list: [(UInt32, CGFloat)]) -> [Gradient.Stop] { list.map { .init(color: Self.color($0.0), location: $0.1) } }
        switch palette {
        case .ask:
            return LinearGradient(stops: stops([(0x5B21B6, 0), (0x4338CA, 0.4), (0x1E40AF, 0.65), (0x6D28D9, 1)]), startPoint: angled.0, endPoint: angled.1)
        case .rewrite:
            return LinearGradient(stops: stops([(0x4C1D95, 0), (0x5B21B6, 0.4), (0x6D28D9, 0.7), (0x4C1D95, 1)]), startPoint: angled.0, endPoint: angled.1)
        case .answer:
            return LinearGradient(stops: stops([(0x0C4A6E, 0), (0x075985, 0.4), (0x0369A1, 0.65), (0x1E3A8A, 1)]), startPoint: angled.0, endPoint: angled.1)
        case .join:
            return LinearGradient(stops: stops([(0x4C1D95, 0), (0x6D28D9, 1)]), startPoint: .leading, endPoint: .trailing)
        }
    }

    /// 扁平的那三颗：识意 #6366F1、改写 #7C3AED、问答 #0284C7。
    static func flatColor(_ palette: Palette) -> Color? {
        switch palette {
        case .ask: return color(0x6366F1)
        case .rewrite: return color(0x7C3AED)
        case .answer: return color(0x0284C7)
        case .join: return nil
        }
    }

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    @ViewBuilder
    var body: some View {
        if let flat = Self.flatColor(palette) {
            Rectangle().fill(flat).allowsHitTesting(false)
        } else {
            nebula
        }
    }

    private var nebula: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let glows = self.glows, stars = self.stars
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
                ForEach(0..<stars.count, id: \.self) { k in
                    let star = stars[k]
                    Circle().fill(Color.white.opacity(star.alpha))
                        .frame(width: 2 * star.r, height: 2 * star.r)
                        .position(x: star.x * w, y: star.y * h)
                }
                if palette != .ask {
                    // 顶上一道淡淡的水光：宽 60%、高 9、白 22%。
                    EllipticalGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0), location: 1)],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: 0.6 * w, height: 9)
                        .position(x: w / 2, y: 1 + 4.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 识意展开、自动时 ✨ 里的图标（方案 E3，design/ask-icon/ask-icon-e3.svg，24×24 画布）：
/// 白色实心镜片的放大镜，镜片里一颗紫粉渐变四角星，右上、左上两颗小黄星。
struct AskIcon: View {
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
            AskIcon.star(&path, center: center, scale: scale)
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
