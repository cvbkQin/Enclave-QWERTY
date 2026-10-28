import SwiftUI

// 使用指引「一键应用」后的小手指（NH1–NH6）：只有小手和水波，没有文字气泡。

/// 要指的按钮把自己的位置报上来。
struct CoachFramesKey: PreferenceKey {
    static var defaultValue: [KeyboardModel.CoachTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [KeyboardModel.CoachTarget: Anchor<CGRect>], nextValue: () -> [KeyboardModel.CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 标成小手指可以指的按钮；正在指它时 VoiceOver 提示「点这里继续」。
    func coachTarget(_ target: KeyboardModel.CoachTarget, active: Bool) -> some View {
        self
            .anchorPreference(key: CoachFramesKey.self, value: .bounds) { [target: $0] }
            .accessibilityHint(active ? L("点这里继续", "Tap to continue", "ここをタップして続ける") : "")
    }

    /// 键盘最外层：在报上来的按钮上画小手指。
    func coachHandOverlay(_ model: KeyboardModel) -> some View {
        overlayPreferenceValue(CoachFramesKey.self) { anchors in
            GeometryReader { proxy in
                CoachHandLayer(model: model, frames: anchors.mapValues { proxy[$0] }, bounds: proxy.size)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 小手和水波。上下点 1.4 秒一下，每次落下扩出一圈水波；换下一步时沿上拱的弧线 0.6 秒飞过去。
private struct CoachHandLayer: View {
    @ObservedObject var model: KeyboardModel
    var frames: [KeyboardModel.CoachTarget: CGRect]
    var bounds: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 正在飞：从哪儿飞到哪儿、什么时候起飞。
    @State private var flight: (from: CGRect, start: Date)?
    /// 落定开始点按的时间，水波和上下点从这里算节拍。
    @State private var settledAt = Date()
    /// 小手上一次指的按钮，换下一步时从它那儿起飞。
    @State private var shownTarget: KeyboardModel.CoachTarget?

    private static let period = 1.4
    private static let flightDuration = 0.6

    var body: some View {
        if let display = model.coachDisplay, let rect = targetRect(display.target) {
            Group {
                if reduceMotion {
                    // 减弱动态效果：不点、不出水波、不飞，下一步直接淡入到下一颗按钮旁边。
                    resting(rect)
                        .opacity(display.dimmed ? 0.3 : 1)
                        .animation(.easeOut(duration: 0.2), value: display.dimmed)
                } else {
                    TimelineView(.animation) { context in
                        hand(at: context.date, rect: rect, dimmed: display.dimmed)
                    }
                }
            }
            .transition(.opacity)
            .onAppear {
                shownTarget = display.target
                settledAt = Date()
            }
            .onChange(of: display.target) { target in
                if let shownTarget, let from = targetRect(shownTarget) { flight = (from, Date()) }
                shownTarget = target
                settledAt = Date().addingTimeInterval(Self.flightDuration)
            }
        }
    }

    private func targetRect(_ target: KeyboardModel.CoachTarget) -> CGRect? {
        frames[target]
    }

    /// 目标在键盘右半边：整只手左右翻过来，手掌挂在左下方，免得被右边切掉。
    private func flipped(_ rect: CGRect) -> Bool { rect.midX > bounds.width / 2 }

    @ViewBuilder
    private func hand(at date: Date, rect: CGRect, dimmed: Bool) -> some View {
        if let flight, date.timeIntervalSince(flight.start) < Self.flightDuration {
            flying(progress: date.timeIntervalSince(flight.start) / Self.flightDuration, from: flight.from, to: rect)
        } else if dimmed {
            // 等 AI 生成：变淡停在原地，不点、不出水波。
            resting(rect).opacity(0.3)
        } else {
            tapping(rect, phase: Self.phase(since: settledAt, at: date))
        }
    }

    /// 飞：先放大到 1.12、转 -8°，沿往上拱的弧线过去，落下恢复。
    private func flying(progress raw: Double, from: CGRect, to: CGRect) -> some View {
        let r = CGFloat(raw)
        let q: CGFloat = 2 - 2 * r
        let p: CGFloat = r < 0.5 ? 2 * r * r : 1 - q * q / 2
        let start = CGPoint(x: from.midX, y: from.midY + 4)
        let end = CGPoint(x: to.midX, y: to.midY + 4)
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 50)
        let tip = Self.bezier(start, control, end, p)
        let lift: CGFloat = sin(CGFloat.pi * p)
        let flip: Bool = p < 0.5 ? flipped(from) : flipped(to)
        return CoachHandShape.hand(flipped: flip, scale: 1 + 0.12 * lift, angle: Double(-8 * lift))
            .position(handCenter(tip: tip, flipped: flip))
    }

    private func resting(_ rect: CGRect) -> some View {
        let flip = flipped(rect)
        return CoachHandShape.hand(flipped: flip)
            .position(handCenter(tip: CGPoint(x: rect.midX, y: rect.midY + 4), flipped: flip))
    }

    /// 上下点：指尖在中心下方 4pt 落下，抬到上方 3pt 再落下（ease-in-out）；每次落下扩出一圈水波。
    private func tapping(_ rect: CGRect, phase t: CGFloat) -> some View {
        let offset: CGFloat = 4 - 7 * (1 - cos(2 * CGFloat.pi * t)) / 2
        let ripple: CGFloat = 1 - (1 - t) * (1 - t)
        let diameter: CGFloat = 12 + 44 * ripple
        let flip = flipped(rect)
        let tip = CGPoint(x: rect.midX, y: rect.midY + offset)
        return ZStack {
            Circle()
                .fill(Self.rippleColor.opacity(0.16))
                .overlay(Circle().strokeBorder(Self.rippleColor, lineWidth: 2.5))
                .frame(width: diameter, height: diameter)
                .opacity(Double(1 - t))
                .position(x: rect.midX, y: rect.midY)
            CoachHandShape.hand(flipped: flip)
                .position(handCenter(tip: tip, flipped: flip))
        }
    }

    private static let rippleColor = Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255)

    /// 1.4 秒一拍里走到哪儿了（0–1）。
    private static func phase(since start: Date, at date: Date) -> CGFloat {
        let elapsed = max(0, date.timeIntervalSince(start))
        return CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period)
    }

    private static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let x: CGFloat = u * u * a.x + 2 * u * t * c.x + t * t * b.x
        let y: CGFloat = u * u * a.y + 2 * u * t * c.y + t * t * b.y
        return CGPoint(x: x, y: y)
    }

    /// 手的框放在哪儿，指尖才落在 tip 上。
    private func handCenter(tip: CGPoint, flipped: Bool) -> CGPoint {
        let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
        let dx = size.width / 2 - fingertip.x
        return CGPoint(x: tip.x + (flipped ? -dx : dx), y: tip.y + size.height / 2 - fingertip.y)
    }
}
