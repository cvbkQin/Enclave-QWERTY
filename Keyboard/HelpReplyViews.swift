import SwiftUI

// AI 帮回（帮回并入润色，方案 D v6）的几处视图。帮回的结果就是润色回答卡上的一版，这里只有：
// AI 栏上钉住的帮回键、识意框右边的帮回按钮、卡头的「回」小标和对方的话。

// MARK: - AI 栏上固定的帮回键

/// 问答键后面一颗浅绿「↩ 帮回」（K2：底 #E4EFE9、字 #3F6F5A，深色 #2E3D36 / #A9D1BD），logo 用降饱和的帮回 logo。
/// 有待回的复制时右上角红点。点 = 帮回（用当前润色风格回剪贴板里那句），生成中点了是停止；长按弹「取消固定」。
/// 不占「已固定 N / 5」，默认不钉。
struct PinnedHelpKey: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let title = L("帮回", "Reply", "返信")

    var body: some View {
        let key = KeyboardModel.AIKey.pin(KeyboardModel.helpPinID)
        let running = model.isRunning && model.lastRunPin == KeyboardModel.helpPinID
        let failed = !running && model.quickStatus == .failed && model.lastRunPin == KeyboardModel.helpPinID
        let success = model.keySuccess?.key == key ? model.keySuccess?.at : nil
        let glowing = model.settings.polishAnimation && !reduceMotion
        KeySuccessClock(since: running ? nil : success, reduced: !glowing) { fx in
            face(running: running, glowing: glowing, fx: fx, failed: failed)
        }
        .overlay(alignment: .topTrailing) {
            if model.helpPending, !running {
                Circle().fill(HelpStyle.dot)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.2))
                    .offset(x: 1, y: -1)
                    .allowsHitTesting(false)
            }
        }
        .opacity(model.hasFullAccess ? 1 : 0.45)
        .modifier(EmptyTapShake(trigger: model.keyShakes[key] ?? 0))
        .contentShape(Capsule())
        .onTapGesture { model.pinnedHelpTapped() }
        .onLongPressGesture(minimumDuration: 0.45) {
            model.keyFeedback(for: .space)
            model.pinMenu = KeyboardModel.helpPinID
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PinFrameKey.self, value: [KeyboardModel.helpPinID: geometry.frame(in: .named("keyboard"))])
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(running ? L("停止帮回", "Stop Help Reply", "返信アシストを停止")
                            : L("帮回", "Help Reply", "返信アシスト") + (failed ? L("，失败，轻点重试", ". Failed, tap to retry", "、失敗・タップで再試行") : ""))
        .accessibilityValue(model.helpPending ? L("有刚复制的内容", "New copy to reply to", "新しいコピーあり") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.pinnedHelpTapped() }
        .accessibilityAction(named: L("取消固定", "Unpin", "固定を解除")) { model.toggleHelpPin() }
    }

    private func face(running: Bool, glowing: Bool, fx: KeySuccessFrame?, failed: Bool) -> some View {
        let animating = running || fx?.logoAnimating == true
        let textWidth = ceil((Self.title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14.5, weight: .semibold)]).width)
        return HStack(spacing: 4) {
            Group {
                if failed {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                } else {
                    HelpIcon(size: 15, running: animating, bounce: fx?.logoScale ?? 1, soft: true)
                }
            }
            .frame(width: 16)
            Text(failed ? L("重试", "Retry", "再試行") : Self.title)
                .font(.system(size: 14.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .successText(fx)
                .opacity(running ? 0 : 1)
                .overlay { AIStopIcon(running: running, moving: glowing, tint: HelpStyle.Key.text) }
        }
        .foregroundStyle(failed ? Color.white : HelpStyle.Key.text)
        .padding(.horizontal, 12)
        .frame(height: KeyboardMetrics.chipHeight)
        .overlay {
            if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: 32 + textWidth / 2, y: KeyboardMetrics.chipHeight / 2)) }
        }
        .background {
            Group {
                if failed {
                    Capsule().fill(AIKeyFX.failFill)
                } else {
                    Capsule().fill(HelpStyle.Key.fill)
                }
            }
            .runningShadow(running, answer: false, room: KeyboardMetrics.chipRoom)
        }
    }
}

// MARK: - 识意框右边的「帮回」按钮

/// 回答卡展开、有待回的复制时出现（情况 ③④）：高 28、左右 10，白色回复箭头 +「帮回」。
/// 输入框空：#10B981 实心白字；输入框有字：浅绿描边版（底 12% 绿、1pt #9FDCC4、字 #0E9F6E），logo 用彩色帮回 logo。
struct HelpAskButton: View {
    @ObservedObject var model: KeyboardModel
    let look: KeyboardModel.HelpAskButtonLook

    var body: some View {
        Button { model.helpAskButtonTapped() } label: {
            HStack(spacing: 4) {
                if look == .solid {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 11, weight: .bold))
                } else {
                    HelpIcon(size: 15)
                }
                Text(L("帮回", "Reply", "返信")).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(look == .solid ? Color.white : HelpStyle.outlineText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(look == .solid ? HelpStyle.green : HelpStyle.outlineFill))
            .overlay {
                if look == .outline { Capsule().strokeBorder(HelpStyle.outlineStroke, lineWidth: 1) }
            }
            .fixedSize()
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(L("帮回", "Help Reply", "返信アシスト"))
        .accessibilityHint(L("用当前润色风格回复刚复制的那句话，框里的字是要求", "Reply to what you copied in the current polish style; the text in this box is your request", "コピーした内容に現在のスタイルで返信。この欄の文字は指示になります"))
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

/// 帮回写的一版的卡头（帮回并入润色 §4）：「回」+「AI 帮回 · 正式」（润色紫）+ 灰色「对方的话」，
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
                    .foregroundStyle(Brand.purpleText)
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
