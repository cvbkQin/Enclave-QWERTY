import SwiftUI

// AI 帮回（帮回并入润色，方案 D v6）的几处视图。帮回的结果就是润色回答卡上的一版，这里只有：
// 弹出的帮回键（T96）、卡头的「回」小标和对方的话。

// MARK: - 弹出的帮回键（T96，design/help-reply/entry-v2）

/// 帮回键弹出、收回的动画（第二节第 6 条）。AI 栏横排和 iPad 九宫格竖排共用，让位的方向由各自的布局决定。
/// - 弹出：键从 0.6 倍放大到 1、同时淡入 spring(0.42, 0.72)；位置从 0 展开、后面的键弹簧让位 spring(0.42, 0.8)。
/// - 收回：键缩到 0.8 倍、淡出 0.2 秒；位置收拢 spring(0.4, 0.9)，后面的键往左（往上）补位。
/// - 减弱动态效果：只淡入淡出，不缩放。
enum HelpKeyPop {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.spring(response: 0.42, dampingFraction: 0.72)),
            removal: .scale(scale: 0.8).combined(with: .opacity).animation(.easeIn(duration: 0.2)))
    }

    /// 后面的键让位、补位：用在包着这一排的容器上，.animation(HelpKeyPop.layout(showing:reduceMotion:), value: model.helpKeyShown)。
    static func layout(showing: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return showing ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.4, dampingFraction: 0.9)
    }
}

/// 问答键右边弹出的「帮回」：和润色、问答同高同字号、同样的星云底换成帮回绿，白字、白色帮回 logo（淡金星），不带 ⌄（风格跟润色走）。
/// 点 = 帮回（输入框里的字当「我想说的意思」，回答卡展开时识意框里的字当要求），生成中点了是停止；
/// 执行中、成功、失败和润色键同一套：文字周围闪星、键下绿色投影、logo 星星错开闪；成功时白光、绿勾、扫光，logo 轻弹、星星闪金。
/// 长按弹「取消固定」＝关掉「复制后弹出帮回键」。弹出后 logo 轻轻一跳一次。没有红点。
/// width：iPad 九宫格那一列要和别的键一样宽（竖屏 86、横屏 94），给了就把胶囊撑到这个宽、logo 和字居中；nil 按内容宽（iPhone）。
struct HelpPopKey: View {
    @ObservedObject var model: KeyboardModel
    var width: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popBounce: CGFloat = 1

    /// AIKeyStrip 弹出时滚到它（reveal）。
    static let revealID: AnyHashable = "help-pop-key"
    private static let title = L("帮回", "Reply", "返信")
    private static let iconSize: CGFloat = 17

    /// 和润色键一样：左内边 9、图标 16、间距 3、名字 14pt；没有 ⌄，右内边 12。
    private static var textWidth: CGFloat { StyleKey.keyTextWidth(title) }
    private static var naturalWidth: CGFloat { 9 + 16 + 3 + textWidth + 12 }

    var body: some View {
        let key = KeyboardModel.AIKey.pin(KeyboardModel.helpPinID)
        let running = model.isRunning && model.lastRunPin == KeyboardModel.helpPinID
        let failed = !running && model.quickStatus == .failed && model.lastRunPin == KeyboardModel.helpPinID
        let success = model.keySuccess?.key == key ? model.keySuccess?.at : nil
        let glowing = model.settings.polishAnimation && !reduceMotion
        let keyWidth = max(width ?? 0, Self.naturalWidth)
        let textX = (keyWidth - Self.naturalWidth) / 2 + 28
        KeySuccessClock(since: running ? nil : success, reduced: !glowing) { fx in
            face(running: running, glowing: glowing, fx: fx, failed: failed, success: success, keyWidth: keyWidth, textX: textX)
        }
        .overlay {
            // 执行中文字周围闪 7 颗小星，约 60% 淡黄、其余白，和润色、问答一样。
            if glowing {
                KeySparkles(running: running, successAt: success, textX: textX, textWidth: Self.textWidth, seed: 7)
            }
        }
        .overlay {
            // 识意框里有还没用过的要求（HW1 ③）：外面亮一圈 2pt #34D399 加柔光，提示点它。
            if model.helpKeyRing {
                Capsule()
                    .strokeBorder(HelpStyle.hex(0x34D399), lineWidth: 2)
                    .padding(-3)
                    .shadow(color: HelpStyle.hex(0x34D399, 0.6), radius: 4)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.helpKeyRing)
        .opacity(model.hasFullAccess ? 1 : 0.45)
        .modifier(EmptyTapShake(trigger: model.keyShakes[key] ?? 0))
        .contentShape(Capsule())
        .onTapGesture { model.helpKeyTapped() }
        .onLongPressGesture(minimumDuration: 0.45) {
            model.keyFeedback(for: .space)
            model.pinMenu = KeyboardModel.helpPinID
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PinFrameKey.self, value: [KeyboardModel.helpPinID: geometry.frame(in: .named("keyboard"))])
        })
        .onAppear { popLogo() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(running ? L("停止帮回", "Stop Help Reply", "返信アシストを停止")
                            : L("帮回刚复制的那句话", "Help Reply to what you copied", "コピーした内容に返信")
                            + (failed ? L("，失败，轻点重试", ". Failed, tap to retry", "、失敗・タップで再試行") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.helpKeyTapped() }
        .accessibilityAction(named: L("关掉复制后弹出帮回键", "Turn off Show Help Reply key after copying", "コピー後に返信アシストキーを表示をオフ")) {
            model.toggleHelpPopup()
        }
    }

    /// 弹出后 logo 轻轻一跳（1 → 1.12 → 1），和成功时那一下同款；减弱动态效果不跳。
    private func popLogo() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.14).delay(0.32)) { popBounce = 1.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            withAnimation(.easeInOut(duration: 0.22)) { popBounce = 1 }
        }
    }

    private func face(running: Bool, glowing: Bool, fx: KeySuccessFrame?, failed: Bool, success: Date?,
                      keyWidth: CGFloat, textX: CGFloat) -> some View {
        let h = KeyboardMetrics.chipHeight
        let animating = running || fx?.logoAnimating == true
        let textCenter = textX + Self.textWidth / 2
        return ZStack(alignment: .topLeading) {
            Group {
                if failed {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                } else {
                    HelpIcon(size: Self.iconSize, running: animating, bounce: (fx?.logoScale ?? 1) * popBounce, white: true,
                             doneAt: glowing ? success : nil)
                }
            }
            .position(x: textX - 11, y: h / 2)
            Text(failed ? L("重试", "Retry", "再試行") : Self.title)
                .font(.system(size: StyleKey.fontSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .successText(fx)
                .runningFade(running)
                .position(x: textCenter, y: h / 2)
            // 执行中文字换成停止图标，点一下就停。
            AIStopIcon(running: running, moving: glowing, tint: .white)
                .position(x: textCenter, y: h / 2)
        }
        .foregroundStyle(.white)
        .frame(width: keyWidth, height: h, alignment: .topLeading)
        .overlay {
            if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: textCenter, y: h / 2)) }
        }
        .background {
            Group {
                if failed {
                    Capsule().fill(AIKeyFX.failFill)
                } else {
                    NebulaFill(palette: .help).clipShape(Capsule())
                }
            }
            // 执行中键下同色投影（绿），和润色、问答一样按 AI 栏剩下的地方收小。
            .shadow(color: running ? HelpStyle.keyShadow : .clear,
                    radius: min(5, KeyboardMetrics.chipRoom * 0.55), y: min(3, KeyboardMetrics.chipRoom * 0.35))
        }
    }
}

// MARK: - 卡头：「回」小标 + 风格 + 对方的话

/// 16×16、圆角 4 的「回」（底 #D1FAE5、字 #047857；深色底 18% 绿、字 #6EE7B7）。
struct ReplyBadge: View {
    var body: some View {
        Text(L("回", "R", "返"))
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(HelpStyle.badgeText)
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HelpStyle.badgeFill))
            .accessibilityHidden(true)
    }
}

/// 帮回写的一版的卡头（帮回并入润色 §4）：「回」+「AI 帮回 · 正式」（帮回绿，cvbk 11-26）+ 灰色「对方的话」，
/// 原话最多占卡头宽度的 55%，超出省略；点卡头在下面浮出整句，再点收起。
struct ReplyResultHeader: View {
    var style: String?
    var message: String
    @State private var expanded = false

    var body: some View {
        let head = L("AI 帮回", "AI reply", "AI 返信")
        let quote = "「" + message.replacingOccurrences(of: "\n", with: " ") + "」"
        GeometryReader { geo in
            HStack(spacing: 0) {
                ReplyBadge().padding(.trailing, 5)
                Text(style.map { "\(head) · \($0)" } ?? head)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(quote)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: geo.size.width * 0.55, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .frame(height: 18)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
        .overlay(alignment: .topLeading) {
            if expanded {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KeyStyle.charKey)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3))
                    .offset(y: 22)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded = false } }
                    .transition(.opacity)
            }
        }
        .zIndex(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((style.map { "\(head) · \($0)" } ?? head) + L("，回复：", ", replying to: ", "、返信先：") + message)
    }
}
