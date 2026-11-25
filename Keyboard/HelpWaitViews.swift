import SwiftUI

// 帮回开始前的等待条（对齐清单第 94 条，design/help-reply/again 逻辑稿二之二，HW1–HW3）。
// - HelpWaitBrush：上半格（iPad 是左边结果区）的绿色干笔刷、前面的墨晕、走满时尽头的亮光和光点、打断时变灰回收。
//   自己填满给它的 frame，宽度按自己的大小算；iPhone 叠在回答卡上半格，iPad 叠在左边结果区。
// - helpWaitFlash(model:shape:)：走满那一刻白光刷过整张卡、卡边紫 → 绿 → 紫，外面一圈绿色柔光。
// 状态都在 model：helpWait（开始时间、打断时间）、helpWaitLanded（走满的那一刻）、helpWaitFlashing、helpWaitBrushOn。
// 减弱动态效果、App 里关了动画：都不画，卡头写「2 秒后自动回」（见 HelpWaitCardBody），走满时卡边绿光 0.2 秒淡入淡出。

/// 等待条的颜色（逻辑稿二之二第 2 条）。
enum HelpWaitInk {
    /// 帮回绿 #10B981。
    static let green = (r: 16.0, g: 185.0, b: 129.0)
    /// 绿的亮度，去饱和时往它靠。
    static let gray = 0.2126 * 16 + 0.7152 * 185 + 0.0722 * 129
    static let glow = HelpStyle.hex(0x34D399)
    static let purple = HelpStyle.hex(0x8B7CF6)

    /// 笔刷：左边 18% 到右边 24%（深色 24% → 32%），前沿后面 250pt 再浓 16%（深色 20%）。
    static func brush(dark: Bool) -> (left: Double, right: Double, front: Double) {
        dark ? (0.24, 0.32, 0.20) : (0.18, 0.24, 0.16)
    }

    /// 墨晕：浅色 #047857 11%，深色 #6EE7B7 9%。
    static func haze(dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        dark ? (110, 231, 183, 0.09) : (4, 120, 87, 0.11)
    }

    /// 帮回绿往灰靠：amount 0 原色，1 去饱和 65%。
    static func tint(desaturated amount: Double) -> (r: Double, g: Double, b: Double) {
        let k = 0.65 * min(max(amount, 0), 1)
        return (green.r + (gray - green.r) * k, green.g + (gray - green.g) * k, green.b + (gray - green.b) * k)
    }
}

/// 绿色干笔刷（14:11 参考影之刃零加点）：一行行横向笔触长短不齐，前沿没有线；前面跑着一层更淡更糊的墨晕。
/// 节奏照 HelpWait.progress：2 秒，接近右边放慢，碰到右边的那一刻开始帮回。
/// openEdge：哪一边和卡片别的部分相接、不圆角（iPhone 上半格是下边，iPad 左边结果区是右边）。
struct HelpWaitBrush: View {
    @ObservedObject var model: KeyboardModel
    var openEdge: Edge = .bottom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// 光点往右上飘，画布往外多留一圈，不在卡边被切掉。
    private static let spill: CGFloat = 40
    private static let corner: CGFloat = 12

    var body: some View {
        if model.helpWaitBrushOn, model.settings.polishAnimation, !reduceMotion {
            let wait = model.helpWait
            let landed = model.helpWaitLanded
            let dark = colorScheme == .dark
            TimelineView(.animation) { context in
                Canvas { gc, size in
                    let area = CGRect(x: Self.spill, y: Self.spill,
                                      width: max(0, size.width - 2 * Self.spill), height: max(0, size.height - 2 * Self.spill))
                    HelpWaitPainter(area: area, dark: dark, openEdge: openEdge, corner: Self.corner)
                        .paint(&gc, wait: wait, landed: landed, now: context.date)
                }
            }
            .padding(-Self.spill)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 一帧怎么画：按状态算出笔刷前沿、透明度、灰度，再画墨晕、笔刷、尽头亮光、光点。
struct HelpWaitPainter {
    var area: CGRect
    var dark: Bool
    var openEdge: Edge
    var corner: CGFloat

    /// 一行笔触 1.5pt 高。
    private static let rowHeight: CGFloat = 1.5

    func paint(_ gc: inout GraphicsContext, wait: HelpWait?, landed: Date?, now: Date) {
        guard area.width > 0, area.height > 0 else { return }
        let width = Double(area.width)
        if let landed {
            // 走满：笔刷满格，到位 0.26 秒后 0.56 秒淡掉；尽头亮光 0.46 秒；28 个光点。
            let d = now.timeIntervalSince(landed)
            guard d < 1.2 else { return }
            let alpha = 1 - clamp((d - 0.26) / 0.56)
            if alpha > 0 { drawBrush(&gc, front: width + 60, alpha: alpha, desaturate: 0, haze: 0) }
            drawFlare(&gc, elapsed: d)
            drawSparks(&gc, elapsed: d)
            return
        }
        guard let wait else { return }
        if let stopped = wait.interruptedAt {
            // 打断：顿住，0.06 秒起 0.3 秒褪成灰，同时往回收 70pt（0.64 秒），0.76 秒淡掉。没有闪光和光点。
            let d = now.timeIntervalSince(stopped) - 0.06
            let alpha = 1 - clamp(d / 0.76)
            guard alpha > 0 else { return }
            let reached = (wait.interruptProgress ?? 0) * width
            let back = 70 * CubicBezier.retract.value(at: clamp(d / 0.64))
            drawBrush(&gc, front: reached - back, alpha: alpha, desaturate: clamp(d / 0.3), haze: alpha)
        } else {
            // 等着：起步 0.16 秒淡入，前沿照曲线往右扫。
            let e = now.timeIntervalSince(wait.startedAt)
            let alpha = clamp(e / 0.16)
            drawBrush(&gc, front: HelpWait.progress(elapsed: e) * width, alpha: alpha, desaturate: 0, haze: alpha)
        }
    }

    // MARK: 笔刷和墨晕

    /// 卡片的这一块：不和别的部分相接的两个角是圆角，相接的那一边往外多画一个圆角，切掉。
    private var clipPath: Path {
        var rect = area
        switch openEdge {
        case .bottom: rect.size.height += corner
        case .trailing: rect.size.width += corner
        case .top: rect.origin.y -= corner; rect.size.height += corner
        case .leading: rect.origin.x -= corner; rect.size.width += corner
        }
        return Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
    }

    /// front：前沿离左边多远（pt）。每一行笔触各自落后一截（长短不齐），落后多少随前沿走而变，所以笔触一直在变。
    private func drawBrush(_ gc: inout GraphicsContext, front: Double, alpha: Double, desaturate: Double, haze: Double) {
        guard front > 0 else { return }
        let width = Double(area.width)
        let rows = Int((area.height / Self.rowHeight).rounded(.up))
        let color = HelpWaitInk.tint(desaturated: desaturate)
        let ink = HelpWaitInk.brush(dark: dark)
        gc.drawLayer { layer in
            layer.clip(to: clipPath)
            // 墨晕：同样一行行，门槛低一些、糊 10pt，比笔刷超前 40pt。
            if haze > 0 {
                let tone = HelpWaitInk.haze(dark: dark)
                layer.drawLayer { hazeLayer in
                    hazeLayer.addFilter(.blur(radius: 10))
                    hazeLayer.opacity = haze
                    let shade = Color(red: tone.r / 255, green: tone.g / 255, blue: tone.b / 255)
                    for row in stride(from: 0, to: rows, by: 3) {
                        let end = front + 40 - lag(row: row + 977, front: front) * 0.7
                        guard end > 0 else { continue }
                        let y = area.minY + CGFloat(row) * Self.rowHeight
                        let rect = CGRect(x: area.minX, y: y, width: CGFloat(min(end, width + 80)), height: Self.rowHeight * 3)
                        let fade = max(0, (end - 60) / end)
                        hazeLayer.fill(Path(rect), with: .linearGradient(
                            Gradient(stops: [.init(color: shade.opacity(tone.a), location: 0),
                                             .init(color: shade.opacity(tone.a), location: fade),
                                             .init(color: shade.opacity(0), location: 1)]),
                            startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                    }
                }
            }
            // 笔刷：横向糊 4pt、纵向 0.6pt 做不到分开，取中间 1.4pt。
            layer.drawLayer { brush in
                brush.addFilter(.blur(radius: 1.4))
                brush.opacity = alpha
                for row in 0..<rows {
                    let end = min(front - lag(row: row, front: front), width + 40)
                    guard end > 2 else { continue }
                    // 笔刷里一丝丝深浅：66%–92%。
                    let depth = 0.66 + 0.26 * hash(row, 31)
                    func a(_ x: Double) -> Double {
                        let base = ink.left + (ink.right - ink.left) * min(max(x / width, 0), 1)
                        let near = ink.front * clamp(1 - (end - x) / 250)
                        return (base + near) * depth
                    }
                    let feather = min(22, end / 2)
                    let shade = Color(red: color.r / 255, green: color.g / 255, blue: color.b / 255)
                    let backStart = max(0, end - 250)
                    var stops: [Gradient.Stop] = [.init(color: shade.opacity(a(0)), location: 0)]
                    if backStart > 0 { stops.append(.init(color: shade.opacity(a(backStart)), location: backStart / end)) }
                    stops.append(.init(color: shade.opacity(a(end - feather)), location: (end - feather) / end))
                    stops.append(.init(color: shade.opacity(0), location: 1))
                    let y = area.minY + CGFloat(row) * Self.rowHeight
                    let rect = CGRect(x: area.minX, y: y, width: CGFloat(end), height: Self.rowHeight + 0.6)
                    brush.fill(Path(rect), with: .linearGradient(Gradient(stops: stops),
                                                                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                                                                endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                }
            }
        }
    }

    /// 这一行比前沿落后多少（pt）：每行固定一截（0–46）加一截随前沿慢慢变的（0–28），像笔毛拖过纸面。
    private func lag(row: Int, front: Double) -> Double {
        let fixed = 46 * pow(hash(row, 7), 1.6)
        let t = front / 70 + hash(row, 13) * 10
        let i = floor(t), f = t - i
        let s = f * f * (3 - 2 * f)
        let wobble = hash(row &* 131 &+ Int(i), 3) * (1 - s) + hash(row &* 131 &+ Int(i) + 1, 3) * s
        return fixed + 28 * wobble
    }

    // MARK: 走满：尽头亮光、光点

    /// 右边一团白到绿的光晕：0.46 秒亮起又散掉。
    private func drawFlare(_ gc: inout GraphicsContext, elapsed d: Double) {
        guard d < 0.46 else { return }
        let k = sin(.pi * d / 0.46)
        let center = CGPoint(x: area.maxX, y: area.midY)
        let radius = max(area.height, 60) * (0.7 + 0.5 * d / 0.46)
        let g = HelpWaitInk.green
        let green = Color(red: g.r / 255, green: g.g / 255, blue: g.b / 255)
        gc.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.9 * k), location: 0),
                                                       .init(color: green.opacity(0.55 * k), location: 0.35),
                                                       .init(color: green.opacity(0), location: 1)]),
                                      center: center, startRadius: 0, endRadius: radius))
    }

    /// 28 个绿色光点（直径 1.6–4.2，白芯绿光晕），从笔刷后半段往右上飘 18–88pt，先放大再缩小消失，0.52–0.94 秒，起点错开 0.2 秒。
    private func drawSparks(_ gc: inout GraphicsContext, elapsed d: Double) {
        let g = HelpWaitInk.green
        let green = Color(red: g.r / 255, green: g.g / 255, blue: g.b / 255)
        for i in 0..<28 {
            let delay = 0.2 * hash(i, 101)
            let duration = 0.52 + 0.42 * hash(i, 103)
            let u = (d - delay) / duration
            guard u > 0, u < 1 else { continue }
            let start = CGPoint(x: area.minX + area.width * (0.5 + 0.5 * hash(i, 107)),
                                y: area.minY + area.height * hash(i, 109))
            let distance = 18 + 70 * hash(i, 113)
            let angle = (20 + 55 * hash(i, 127)) * .pi / 180
            let travel = 1 - pow(1 - u, 2)
            let point = CGPoint(x: start.x + distance * cos(angle) * travel, y: start.y - distance * sin(angle) * travel)
            let size = (1.6 + 2.6 * hash(i, 131)) * (u < 0.35 ? 0.6 + 0.6 * u / 0.35 : 1.2 * (1 - (u - 0.35) / 0.65))
            let fade = u < 0.2 ? u / 0.2 : 1 - max(0, u - 0.6) / 0.4
            let halo = size * 1.9
            gc.fill(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                    with: .radialGradient(Gradient(colors: [green.opacity(0.7 * fade), green.opacity(0)]),
                                          center: point, startRadius: 0, endRadius: halo))
            let core = size / 2
            gc.fill(Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
                    with: .color(.white.opacity(0.95 * fade)))
        }
    }

    // MARK: 工具

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0…1 之间的固定伪随机数：同一行、同一个光点每帧一样。
    private func hash(_ n: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n &* 374_761_393 &+ salt &* 668_265_263))
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x = x ^ (x >> 16)
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - 走满：白光刷过整张卡、卡边绿光

extension View {
    /// 回答卡走满那一刻（HW3）：白色斜光带从左往右刷过整张卡，卡边紫 → 绿 → 紫，外面一圈 22pt 绿色柔光，0.9 秒。
    /// phoneBody、padBody 都加。
    func helpWaitFlash(model: KeyboardModel, shape: RoundedRectangle) -> some View {
        modifier(HelpWaitFlash(model: model, shape: shape))
    }
}

struct HelpWaitFlash: ViewModifier {
    @ObservedObject var model: KeyboardModel
    var shape: RoundedRectangle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let reduced = reduceMotion || !model.settings.polishAnimation
        content
            .background {
                if model.helpWaitFlashing, !reduced, let landed = model.helpWaitLanded {
                    TimelineView(.animation) { context in
                        let k = Self.pulse(context.date.timeIntervalSince(landed))
                        shape.stroke(HelpWaitInk.glow.opacity(0.5 * k), lineWidth: 22).blur(radius: 11)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if model.helpWaitFlashing, let landed = model.helpWaitLanded {
                    TimelineView(.animation) { context in
                        let d = context.date.timeIntervalSince(landed)
                        ZStack {
                            if !reduced { band(d) }
                            border(d, reduced: reduced)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    /// 紫 → 绿 → 紫：0.9 秒里先变绿再变回。
    static func pulse(_ d: Double) -> Double {
        guard d > 0, d < 0.9 else { return 0 }
        return sin(.pi * d / 0.9)
    }

    /// 减弱动态效果：卡边绿光 0.2 秒淡入、0.2 秒淡出。
    static func reducedPulse(_ d: Double) -> Double {
        if d < 0 { return 0 }
        if d < 0.2 { return d / 0.2 }
        if d < 0.4 { return 1 - (d - 0.2) / 0.2 }
        return 0
    }

    private func border(_ d: Double, reduced: Bool) -> some View {
        let k = reduced ? Self.reducedPulse(d) : Self.pulse(d)
        return ZStack {
            shape.strokeBorder(HelpWaitInk.purple.opacity(1 - k), lineWidth: 1.5)
            shape.strokeBorder(HelpWaitInk.glow.opacity(k), lineWidth: 1.5)
        }
    }

    /// 宽 96、斜 16° 的白光带，中间白 78%（深色 26%），0.76 秒，cubic-bezier(.45,0,.25,1)。
    private func band(_ d: Double) -> some View {
        GeometryReader { geo in
            if d < 0.76 {
                let width: CGFloat = 96
                let p = CubicBezier.sweep.value(at: d / 0.76)
                let peak = colorScheme == .dark ? 0.26 : 0.78
                LinearGradient(colors: [.white.opacity(0), .white.opacity(peak), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width, height: geo.size.height * 2)
                    .rotationEffect(.degrees(16))
                    .offset(x: -width + (geo.size.width + width * 2) * p, y: -geo.size.height / 2)
            }
        }
        .clipShape(shape)
    }
}

// MARK: - 等的时候卡里写什么

/// 等待时回答卡上半格（HW1 ①）：卡头「回 AI 帮回 · 正式」，正文是要回的那句原话，灰字、左边 2pt 绿竖线，最多两行。
/// 减弱动态效果（或 App 里关了动画）时不画笔刷，卡头右边写「2 秒后自动回」；停下来以后不写。
struct HelpWaitCardBody: View {
    @ObservedObject var model: KeyboardModel
    var wait: HelpWait
    var leading: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let head = L("AI 帮回", "AI reply", "AI 返信")
        let style = model.settings.selectedStyle?.displayName
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ReplyBadge().padding(.trailing, 5)
                Text(style.map { "\(head) · \($0)" } ?? head)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Brand.purpleText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !wait.interrupted, reduceMotion || !model.settings.polishAnimation {
                    Text(L("2 秒后自动回", "Replying in 2 s", "2 秒後に自動で返信"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: 18)
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(HelpStyle.green).frame(width: 2)
                Text(wait.message)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(head + L("，回复：", ", replying to: ", "、返信先：") + wait.message)
    }
}
