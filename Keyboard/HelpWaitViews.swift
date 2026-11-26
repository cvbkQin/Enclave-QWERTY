import SwiftUI

// 帮回开始前的等待条（对齐清单第 94 条，design/help-reply/again 逻辑稿二之二，HW1–HW3）。
// 11-26 对齐清单第 98 条（逻辑稿二之三，HW4）：等 1.5 秒；到位不再碎成光点、尽头不亮、不另刷白光，改成整张卡闪一下，0.4 秒内接上生成中。
// - HelpWaitBrush：上半格（iPad 是左边结果区）的绿色干笔刷、前面的墨晕；到位时提亮一下再淡掉；打断时变灰回收。
//   自己填满给它的 frame，宽度按自己的大小算；iPhone 叠在回答卡上半格，iPad 叠在左边结果区。
// - helpWaitFlash(model:shape:)：到位那一刻整张卡（含识意框，iPad 含右边识意区）闪一下，卡边变绿再淡成生成中的流光。
// 状态都在 model：helpWait（开始时间、打断时间）、helpWaitLanded（到位的那一刻）、helpWaitFlashing、helpWaitBrushOn。
// 减弱动态效果、App 里关了动画：都不画，卡头写「1.5 秒后自动回」（见 HelpWaitCardBody），到位时卡边绿色 0.2 秒淡入淡出。

/// 等待条的颜色（逻辑稿二之二第 2 条）。
enum HelpWaitInk {
    /// 帮回绿 #10B981。
    static let green = (r: 16.0, g: 185.0, b: 129.0)
    /// 打断时褪成的中性灰 #8E8E93（只按亮度去饱和还偏青，在 18–24% 的透明度下看不出变灰）。
    static let gray = (r: 142.0, g: 142.0, b: 147.0)
    static let glow = HelpStyle.hex(0x34D399)

    /// 笔刷：左边 18% 到右边 24%（深色 24% → 32%），前沿后面 250pt 再浓 16%（深色 20%）。
    static func brush(dark: Bool) -> (left: Double, right: Double, front: Double) {
        dark ? (0.24, 0.32, 0.20) : (0.18, 0.24, 0.16)
    }

    /// 墨晕：浅色 #047857 11%，深色 #6EE7B7 9%。
    static func haze(dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        dark ? (110, 231, 183, 0.09) : (4, 120, 87, 0.11)
    }

    /// 帮回绿往中性灰靠：amount 0 原色，1 是灰。
    static func tint(desaturated amount: Double) -> (r: Double, g: Double, b: Double) {
        let k = min(max(amount, 0), 1)
        return (green.r + (gray.r - green.r) * k, green.g + (gray.g - green.g) * k, green.b + (gray.b - green.b) * k)
    }
}

/// 绿色干笔刷（14:11 参考影之刃零加点）：一行行横向笔触长短不齐，前沿没有线；前面跑着一层更淡更糊的墨晕。
/// 节奏照 HelpWait.progress：1.5 秒，接近右边放慢，碰到右边的那一刻开始帮回。
/// openEdge：哪一边和卡片别的部分相接、不圆角（iPhone 上半格是下边，iPad 左边结果区是右边）。
struct HelpWaitBrush: View {
    @ObservedObject var model: KeyboardModel
    var openEdge: Edge = .bottom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let corner: CGFloat = 12

    var body: some View {
        if model.helpWaitBrushOn, model.settings.polishAnimation, !reduceMotion {
            let wait = model.helpWait
            let landed = model.helpWaitLanded
            let dark = colorScheme == .dark
            TimelineView(.animation) { context in
                Canvas { gc, size in
                    HelpWaitPainter(area: CGRect(origin: .zero, size: size), dark: dark, openEdge: openEdge, corner: Self.corner)
                        .paint(&gc, wait: wait, landed: landed, now: context.date)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 一帧怎么画：按状态算出笔刷前沿、透明度、灰度，再画墨晕和笔刷。
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
            // 到位（二之三）：笔刷满格，亮度 1 → 1.45 → 1（0.26 秒），到位后 0.04 秒起 0.38 秒淡掉。不碎成光点，尽头不亮。
            let d = now.timeIntervalSince(landed)
            let fade = 1 - clamp((d - 0.04) / 0.38)
            guard fade > 0 else { return }
            let lift = d < 0.26 ? 1 + 0.45 * sin(.pi * max(d, 0) / 0.26) : 1
            drawBrush(&gc, front: width + 60, alpha: fade, desaturate: 0, haze: 0, lift: lift)
            return
        }
        guard let wait else { return }
        if let stopped = wait.interruptedAt {
            // 打断：顿住，0.06 秒起 0.3 秒褪成灰，同时往回收 70pt（0.64 秒），0.76 秒淡掉。没有闪光和光点。
            // 先不透明地变灰，灰了再淡（0.3–0.76 秒），不然没看清变灰就没了（06 iPad 核对 11-25）。
            let d = now.timeIntervalSince(stopped) - 0.06
            let alpha = 1 - clamp((d - 0.3) / 0.46)
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
    /// lift：到位时提亮，笔刷每一丝的浓度乘上它。
    private func drawBrush(_ gc: inout GraphicsContext, front: Double, alpha: Double, desaturate: Double, haze: Double, lift: Double = 1) {
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
                        return min((base + near) * depth * lift, 1)
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

    // MARK: 工具

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0…1 之间的固定伪随机数：同一行每帧一样。
    private func hash(_ n: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n &* 374_761_393 &+ salt &* 668_265_263))
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x = x ^ (x >> 16)
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - 到位：整张卡闪一下、卡边绿色淡成流光

extension View {
    /// 回答卡到位那一刻（二之三，HW4）：一层亮光盖住整张卡（含识意框、iPad 右边识意区），左淡右亮，0.07 秒到顶、0.42 秒退完；
    /// 卡边 0.11 秒变绿，外面一圈 3pt 绿 30% 加 18pt 绿色柔光 34%，到位后 0.08 秒起绿边 0.32 秒、柔光 0.26 秒淡掉，
    /// 露出底下已经在转的生成中流光（FlowingBorder）。phoneBody、padBody 都加，按整张卡的大小画。
    func helpWaitFlash(model: KeyboardModel, shape: RoundedRectangle) -> some View {
        modifier(HelpWaitFlash(model: model, shape: shape))
    }
}

struct HelpWaitFlash: ViewModifier {
    @ObservedObject var model: KeyboardModel
    var shape: RoundedRectangle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// 闪光、绿边都在这么长里走完（model 里 helpWaitFlashing 留 0.45 秒）。
    static let length = 0.45

    func body(content: Content) -> some View {
        let reduced = reduceMotion || !model.settings.polishAnimation
        content
            .background {
                if model.helpWaitFlashing, !reduced, let landed = model.helpWaitLanded {
                    TimelineView(.animation) { context in
                        let k = Self.halo(context.date.timeIntervalSince(landed))
                        shape.stroke(HelpWaitInk.glow.opacity(0.34 * k), lineWidth: 18).blur(radius: 9)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if model.helpWaitFlashing, let landed = model.helpWaitLanded {
                    TimelineView(.animation) { context in
                        let d = context.date.timeIntervalSince(landed)
                        ZStack {
                            if !reduced { sheen(d) }
                            border(d, reduced: reduced)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    /// 整卡闪光的亮度：0.07 秒到顶，再按 cubic-bezier(.2,.7,.3,1) 退，0.42 秒退完。
    static func flash(_ d: Double) -> Double {
        if d <= 0 || d >= 0.42 { return 0 }
        if d < 0.07 { return d / 0.07 }
        return 1 - CubicBezier.flashOut.value(at: (d - 0.07) / 0.35)
    }

    /// 卡边的绿：0.11 秒变绿，到位后 0.08 秒起 0.32 秒淡掉。
    static func edge(_ d: Double) -> Double {
        guard d > 0 else { return 0 }
        return max(0, min(d / 0.11, 1, 1 - (d - 0.08) / 0.32))
    }

    /// 外面的绿色柔光：和绿边一起亮，到位后 0.08 秒起 0.26 秒收掉，换成流光自己的紫色呼吸光。
    static func halo(_ d: Double) -> Double {
        guard d > 0 else { return 0 }
        return max(0, min(d / 0.11, 1, 1 - (d - 0.08) / 0.26))
    }

    /// 减弱动态效果：卡边绿色 0.2 秒淡入、0.2 秒淡出。
    static func reducedPulse(_ d: Double) -> Double {
        if d < 0 { return 0 }
        if d < 0.2 { return d / 0.2 }
        if d < 0.4 { return 1 - (d - 0.2) / 0.2 }
        return 0
    }

    private func border(_ d: Double, reduced: Bool) -> some View {
        let k = reduced ? Self.reducedPulse(d) : Self.edge(d)
        return ZStack {
            if !reduced { shape.inset(by: -1.5).stroke(HelpWaitInk.glow.opacity(0.3 * k), lineWidth: 3) }
            shape.strokeBorder(HelpWaitInk.glow.opacity(k), lineWidth: 1.5)
        }
    }

    /// 盖住整张卡的亮光，左淡右亮（笔刷碰到的那边最亮）：浅色白 30% → 55% → 右边 #ECFDF5 85%；深色 #D1FAE5 10% → 22% → 38%。
    private func sheen(_ d: Double) -> some View {
        let k = Self.flash(d)
        let dark = colorScheme == .dark
        let mint = HelpStyle.hex(0xD1FAE5)
        let colors: [Color] = dark
            ? [mint.opacity(0.10), mint.opacity(0.22), mint.opacity(0.38)]
            : [.white.opacity(0.30), .white.opacity(0.55), HelpStyle.hex(0xECFDF5).opacity(0.85)]
        return shape.fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .opacity(k)
    }
}

// MARK: - 等的时候卡里写什么

/// 等待时回答卡上半格（HW1 ①）：卡头「回 AI 帮回 · 正式」，正文是要回的那句原话，灰字、左边 2pt 绿竖线，最多两行。
/// 减弱动态效果（或 App 里关了动画）时不画笔刷，卡头右边写「1.5 秒后自动回」；停下来以后不写。
struct HelpWaitCardBody: View {
    @ObservedObject var model: KeyboardModel
    var wait: HelpWait
    var leading: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let head = L("AI 帮回", "AI reply", "AI 返信")
        let style = model.settings.selectedStyle?.displayName
        VStack(alignment: .leading, spacing: KeyboardMetrics.compactCard ? 4 : 6) {
            HStack(spacing: 0) {
                ReplyBadge().padding(.trailing, 5)
                Text(style.map { "\(head) · \($0)" } ?? head)
                    .font(.system(size: KeyboardMetrics.headerFont, weight: .bold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !wait.interrupted, reduceMotion || !model.settings.polishAnimation {
                    Text(L("1.5 秒后自动回", "Replies in 1.5 s", "1.5 秒後に自動で返信"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: KeyboardMetrics.headerHeight)
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
        .padding(.top, KeyboardMetrics.headerTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(head + L("，回复：", ", replying to: ", "、返信先：") + wait.message)
    }
}
