import SwiftUI

// MARK: - AI 栏键的执行中与成功动效（对齐清单第 61 条）

// 功能对照表「AI 栏：润色 / 问答键的执行中与成功动效」。时间、曲线照样片源文件 design/polish-success/ps3.html 的 bs()。
// 执行中：被点的那颗键下面一层同色柔投影，logo 动（PolishStars running、AskIcon running），不扫光、不描边。
// 成功：白光一闪、文字淡出模糊、绿勾一笔画出，停约 1 秒后文字回来（cvbk 11-02）；斜向扫光 5 次，logo 一直动，和扫光一起在 18.2 秒结束。
// 键盘的润色键、问答键、固定键和 App 里的功能演示共用这一份。

/// 成功后某一刻按钮上各层的样子。
struct KeySuccessFrame: Equatable {
    /// 全程 18.2 秒（最后一次扫光结束，logo 同时停）；减弱动态效果（或关了发光动画）时 1.6 秒。
    static let duration: Double = 18.2
    static let reducedDuration: Double = 1.6

    /// 白色闪光的透明度。
    var flash: Double = 0
    var textOpacity: Double = 1
    var textBlur: CGFloat = 0
    /// 文字回来时从下面往上回到原位，这一刻还差几 pt。
    var textDrop: CGFloat = 0
    /// 绿勾画到哪（0…1）。
    var check: CGFloat = 0
    var checkOpacity: Double = 0
    var checkScale: CGFloat = 1
    /// 扫光进度（已按 ease-in-out），nil：这一刻在两次扫光之间。
    var sweep: CGFloat?
    /// logo 轻弹一下 1 → 1.25 → 1.05 → 1。
    var logoScale: CGFloat = 1
    /// logo 保持执行中的动画。
    var logoAnimating = false

    static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 成功后过了 elapsed 秒的样子；还没开始或已经结束返回 nil。
    static func at(_ elapsed: Double, reduceMotion: Bool) -> KeySuccessFrame? {
        guard elapsed >= 0 else { return nil }
        var f = KeySuccessFrame()
        if reduceMotion {
            // 不扫光、不画线：绿勾直接淡入（0.2 秒）停 1.2 秒再淡出，文字跟着让开；logo 不动。
            guard elapsed < reducedDuration else { return nil }
            let shown = clamp(elapsed / 0.2) * (1 - clamp((elapsed - 1.4) / 0.2))
            f.check = 1
            f.checkOpacity = shown
            f.textOpacity = 1 - shown
            return f
        }
        guard elapsed < duration else { return nil }
        let ms = elapsed * 1000
        f.logoAnimating = true
        // 0–150 白光 0 → 12%，150–600 退回 0。
        f.flash = ms < 150 ? 0.12 * ms / 150 : 0.12 * (1 - clamp((ms - 150) / 450))
        // 0–300 文字淡出、模糊 0 → 3。
        let out = easeInOut(clamp(ms / 300))
        f.textOpacity = 1 - out
        f.textBlur = 3 * out
        // 80–680 绿勾从左到右一笔画出。
        if ms >= 80 {
            f.check = max(0.001, easeInOut(clamp((ms - 80) / 600)))
            f.checkOpacity = 1
        }
        // 扫光 5 次：每次 3 秒，隔 0.8 秒。
        let cycle = ms.truncatingRemainder(dividingBy: 3800)
        if ms < 18200, cycle < 3000 { f.sweep = easeInOut(cycle / 3000) }
        f.logoScale = bounce(ms / 700)
        // 绿勾画完停约 1 秒（cvbk 11-02）：1680–2080 淡出并缩到 0.92；1880–2280 文字淡回、模糊 3 → 0、从下 3pt 回到原位。
        if ms >= 1680 {
            let k = easeInOut(clamp((ms - 1680) / 400))
            f.checkOpacity = 1 - k
            f.checkScale = 1 - 0.08 * k
        }
        if ms >= 1880 {
            let k = easeInOut(clamp((ms - 1880) / 400))
            f.textOpacity = k
            f.textBlur = 3 * (1 - k)
            f.textDrop = 3 * (1 - k)
        }
        return f
    }

    /// 0.7 秒的轻弹：25% 到 1.25，60% 回到 1.05，结束回 1。
    static func bounce(_ p: Double) -> CGFloat {
        guard p >= 0, p < 1 else { return 1 }
        if p < 0.25 { return 1 + 0.25 * p / 0.25 }
        if p < 0.6 { return 1.25 - 0.2 * (p - 0.25) / 0.35 }
        return 1.05 - 0.05 * (p - 0.6) / 0.4
    }
}

/// 成功动效期间逐帧重画（TimelineView），其余时候只画一次 content(nil)。
struct KeySuccessClock<Content: View>: View {
    var since: Date?
    var reduced: Bool
    @ViewBuilder var content: (KeySuccessFrame?) -> Content

    var body: some View {
        if let since {
            TimelineView(.animation) { context in
                content(KeySuccessFrame.at(context.date.timeIntervalSince(since), reduceMotion: reduced))
            }
        } else {
            content(nil)
        }
    }
}

/// 成功时盖在按钮上的三层：白色闪光、斜向扫光（clip 在胶囊里）、绿勾（在文字那块正中，不盖 logo、不盖 ⌄）。
struct KeySuccessOverlay: View {
    var frame: KeySuccessFrame
    /// 绿勾的中心，按钮自己的坐标。
    var checkCenter: CGPoint

    /// 扁平绿勾 #4ADE80，微光 rgba(74,222,128,.55)。
    static let green = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let glow = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255).opacity(0.55)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.white.opacity(frame.flash)
                if let sweep = frame.sweep {
                    // 宽 68、斜 35°（「/」），从按钮左边外扫到右边外。
                    SweepBeam()
                        .frame(width: 68, height: 140)
                        .rotationEffect(.degrees(35))
                        .position(x: -56 + sweep * (geo.size.width + 122), y: geo.size.height / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Capsule())
            if frame.checkOpacity > 0 {
                SuccessCheck()
                    .trim(from: 0, to: frame.check)
                    .stroke(Self.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 20)
                    .shadow(color: Self.glow, radius: 2)
                    .scaleEffect(frame.checkScale)
                    .opacity(frame.checkOpacity)
                    .position(checkCenter)
            }
        }
        .allowsHitTesting(false)
    }

    /// 光带：透明 → 白 10% → 白 38%（中间 6% 宽的芯）→ 白 10% → 透明。
    private struct SweepBeam: View {
        var body: some View {
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.10), location: 0.28),
                .init(color: .white.opacity(0.38), location: 0.47),
                .init(color: .white.opacity(0.38), location: 0.53),
                .init(color: .white.opacity(0.10), location: 0.72),
                .init(color: .white.opacity(0), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// 绿勾：24×20 画布上 (3, 10.5) → (9.5, 16.5) → (21, 3.5)。
struct SuccessCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24, sy = rect.height / 20
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3 * sx, y: rect.minY + 10.5 * sy))
        path.addLine(to: CGPoint(x: rect.minX + 9.5 * sx, y: rect.minY + 16.5 * sy))
        path.addLine(to: CGPoint(x: rect.minX + 21 * sx, y: rect.minY + 3.5 * sy))
        return path
    }
}

extension View {
    /// 成功期间文字的样子：淡出、模糊，回来时从下往上 3pt。
    func successText(_ frame: KeySuccessFrame?) -> some View {
        opacity(frame?.textOpacity ?? 1)
            .blur(radius: frame?.textBlur ?? 0)
            .offset(y: frame?.textDrop ?? 0)
    }

    /// 执行中按钮下面的同色柔投影：样片是 y 3、模糊 10。
    /// room：键下面还剩几 pt 不被裁掉。键盘 AI 栏的键在左右滑动区里，上下只剩 (44 − 34) / 2 = 5pt，
    /// 照样片画会在 5pt 处被滑动区齐齐切掉、看着像一块脏边（cvbk 11-02 真机 0.95_19），所以按剩下的地方收小。
    func runningShadow(_ on: Bool, answer: Bool, room: CGFloat = 8) -> some View {
        shadow(color: on ? (answer ? AIKeyFX.askShadow : AIKeyFX.polishShadow) : .clear,
               radius: min(5, room * 0.55), y: min(3, room * 0.35))
    }
}

enum AIKeyFX {
    /// 执行中投影：润色 rgba(124,77,240,.5)、问答 rgba(59,130,246,.5)。
    static let polishShadow = Color(red: 124 / 255, green: 77 / 255, blue: 240 / 255).opacity(0.5)
    static let askShadow = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255).opacity(0.5)
    /// 失败的红底「↻ 重试」。
    static let failFill = LinearGradient(colors: [Color(red: 0xF0 / 255, green: 0x5A / 255, blue: 0x5A / 255),
                                                  Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}
