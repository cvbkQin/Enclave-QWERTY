import SwiftUI

// MARK: - AI 栏的润色键、问答键（AK1–AK5）

/// AI 栏的两颗主键：润色键「✨ 正式 ｜ ⌄」、问答键「? 问答 ｜ ⌄」，紫色 / 蓝色柔和混色底、白字白图标。
/// 收起和展开是同一排键（AK4）。按内容宽，放不下时整排左右滑（AIKeyStrip），不截断。
/// 竖线左边（图标 + 名字）点了就执行：润色键收着时快速润色、展开时按当前风格改输入框里的话（识意框里的要求一起带上）；
/// 问答键展开时回答识意框里的问题，收着时展开回答卡、回答输入框里的话。
/// 竖线右边 ⌄ 那块（28pt，整块都算）弹风格下拉框，选完收起、不执行。生成中点名字是停止。
/// 执行中、成功、失败的动效见 Shared/AIKeyEffects.swift（对齐清单第 61 条）：执行中键下同色投影、logo 动；
/// 成功时文字隐去、绿勾画出停约 1 秒后文字回来，扫光 5 次、logo 一直动，18.2 秒一起结束；快速模式失败时晃一下、红底「↻ 重试」，点它重试。
struct StyleKey: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var answer: Bool { row == .answerStyles }
    private var key: KeyboardModel.AIKey { answer ? .ask : .polish }

    var body: some View {
        let locked = !model.hasFullAccess
        let open = !locked && model.aiRow == row
        let running = model.isRunning && model.lastRunPin == nil
            && model.runOrigin == (answer ? KeyboardModel.RunOrigin.ask : KeyboardModel.RunOrigin.polish)
        let failed = !answer && !running && model.quickStatus == .failed && model.lastRunPin == nil
        let success = model.keySuccess?.key == key ? model.keySuccess?.at : nil
        let title = Self.title(model, answer: answer)
        let layout = Self.layout(title: title)
        ZStack(alignment: .leading) {
            KeySuccessClock(since: running ? nil : success, reduced: !fullMotion) { fx in
                Self.face(answer: answer, title: title, open: open, running: running, glowing: fullMotion,
                          fx: fx, failed: failed, faded: !answer && (model.aiBlocked || model.aiQuotaUsed),
                          // 帮回卡上是帮回结果（RG3 B）：✨ 换成绿色星星，点了润色这条回复。
                          starTint: !answer && model.aiExpanded && model.helpReply?.current != nil ? HelpStyle.star : nil)
            }
            .overlay {
                // 执行中文字周围闪 7 颗小星（对齐清单第 63 条）；减弱动态效果、关了发光动画时不放。
                if fullMotion {
                    KeySparkles(running: running, successAt: success, textX: layout.textX, textWidth: layout.textWidth,
                                seed: answer ? 2 : 1)
                }
            }
            .overlay {
                if open { Capsule().strokeBorder(answer ? Self.answerBorder : Self.rewriteBorder, lineWidth: 1.5) }
            }
            .opacity(locked ? 0.45 : 1)
            .allowsHitTesting(false)
            HStack(spacing: 0) {
                Button {
                    answer ? model.askKeyTapped() : model.polishKeyTapped()
                } label: {
                    // 几乎透明的底：完全透明的地方系统不把触摸交给键盘（混色底不接触摸）。
                    Self.touchFill.frame(width: layout.dividerX)
                }
                .accessibilityLabel(running ? (answer ? L("停止问答", "Stop answering", "質問を停止") : L("停止润色", "Stop polishing", "整えるのを停止"))
                                    : failed ? L("润色失败，轻点重试", "Polish failed. Tap to retry", "失敗しました。タップで再試行")
                                    : (answer ? L("问答", "Ask", "質問") : L("润色：\(title)", "Polish: \(title)", "整える：\(title)")))
                .modifier(CoachKeyTarget(model: model, answer: answer))
                Button {
                    locked ? model.showFullAccessTip() : model.toggleRow(row)
                } label: {
                    Self.touchFill
                }
                .accessibilityLabel((answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル")) + "：" + title)
                .accessibilityValue(open ? L("已展开", "Expanded", "展開中") : L("已收起", "Collapsed", "折りたたみ"))
            }
            .buttonStyle(KeyPressStyle())
        }
        .frame(width: layout.width, height: KeyboardMetrics.chipHeight)
        .modifier(AIKeyBadges(model: model, enabled: !answer))
        .modifier(EmptyTapShake(trigger: model.keyShakes[key] ?? 0))
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RowChipFrameKey.self, value: [row: geometry.frame(in: .named("keyboard"))])
        })
    }

    /// 关了发光动画或开了减弱动态效果：只留星星轻微闪动。
    private var fullMotion: Bool { model.settings.polishAnimation && !reduceMotion }

    /// 几乎透明、但系统认得的点按底。
    static let touchFill = Color.black.opacity(0.001)

    static let rewriteBorder = NebulaFill.color(0xC4B5FD)
    static let answerBorder = NebulaFill.color(0x7DD3FC)

    static let fontSize: CGFloat = 14
    static let chevronSize: CGFloat = 11
    /// ⌄ 那块（竖线右边）的宽，整块都点得中。AI 栏收紧（方案 A，v309）：28 → 24。
    static let chevronZone: CGFloat = 24

    struct Layout {
        var iconX: CGFloat
        var textX: CGFloat
        var textWidth: CGFloat
        var dividerX: CGFloat
        var chevronX: CGFloat
        var width: CGFloat
    }

    /// 按内容宽（AK4，v309 收紧）：左内边 9、图标 16、间距 3、名字 14pt、竖线左边 5、竖线 1、⌄ 区 24。
    static func layout(title: String) -> Layout {
        let textWidth = keyTextWidth(title)
        let dividerX = 9 + 16 + 3 + textWidth + 5
        return Layout(iconX: 17, textX: 28, textWidth: textWidth, dividerX: dividerX,
                      chevronX: dividerX + 1 + chevronZone / 2 - 1, width: dividerX + 1 + chevronZone)
    }

    /// 柔和混色底、白字白图标。润色键的图标收起、展开都是金色 ✨（13:20 cvbk），问答键是问答图标（AskIcon，v306）。
    /// 执行中 logo 动、键下同色投影（不再换成白色方块）；fx 是成功动效这一刻的样子；failed：红底「↻ 重试」。
    static func face(answer: Bool, title: String, open: Bool = false, running: Bool = false, glowing: Bool = false,
                     fx: KeySuccessFrame? = nil, failed: Bool = false, faded: Bool = false, starTint: Color? = nil) -> some View {
        let h = KeyboardMetrics.chipHeight
        let layout = Self.layout(title: title)
        let animating = running || fx?.logoAnimating == true
        let bounce = fx?.logoScale ?? 1
        return ZStack(alignment: .topLeading) {
            Group {
                if failed {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                } else if answer {
                    AskIcon(size: 17, running: animating, glowing: glowing, bounce: bounce)
                } else {
                    PolishStars(size: 17, running: animating, glowing: glowing, doneAt: nil, tint: starTint ?? Brand.gold)
                        .frame(width: 17, height: 17)
                        .scaleEffect(bounce)
                }
            }
            .position(x: layout.iconX, y: h / 2)
            Text(failed ? L("重试", "Retry", "再試行") : title)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .successText(fx)
                .runningFade(running)
                .position(x: layout.textX + layout.textWidth / 2, y: h / 2)
            // 执行中文字换成停止图标（PS6），点一下就停。
            AIStopIcon(running: running, moving: glowing, tint: .white)
                .position(x: layout.textX + layout.textWidth / 2, y: h / 2)
            chevronDivider
                .position(x: layout.dividerX + 0.5, y: h / 2)
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: chevronSize, weight: .semibold))
                .position(x: layout.chevronX, y: h / 2)
        }
        .foregroundStyle(.white)
        .frame(width: layout.width, height: h, alignment: .topLeading)
        .overlay {
            if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: layout.textX + layout.textWidth / 2, y: h / 2)) }
        }
        .background {
            Group {
                if failed {
                    Capsule().fill(AIKeyFX.failFill)
                } else {
                    NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()).opacity(faded ? 0.35 : 1)
                }
            }
            .runningShadow(running, answer: answer, room: KeyboardMetrics.chipRoom)
        }
    }

    /// 名字的宽（14pt 600）。
    static func keyTextWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// 名字和 ⌄ 之间的竖线：1×14、白 45%（FB）。
    static var chevronDivider: some View {
        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
    }

    /// 润色键写当前润色风格的名字；问答键固定写「问答」，不写风格名（KB1）。
    static func title(_ model: KeyboardModel, answer: Bool) -> String {
        if answer { return L("问答", "Ask", "質問") }
        return model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
    }
}

/// 使用指引里点 ✨（收着）/ 「执行」（展开）那一步指着润色键的名字，点「问答」那一步指着问答键的名字。
private struct CoachKeyTarget: ViewModifier {
    @ObservedObject var model: KeyboardModel
    var answer: Bool

    func body(content: Content) -> some View {
        if answer {
            content.coachTarget(.ask, active: model.coachDisplay?.target == .ask)
        } else {
            content
                .coachTarget(.sparkle, active: !model.aiExpanded && model.coachDisplay?.target == .sparkle)
                .coachTarget(.run, active: model.aiExpanded && model.coachDisplay?.target == .run)
        }
    }
}

/// 润色键右上角：没开完全访问、今天的次数用完时一个小锁（P01）；试用结束、今天还有次数时剩几次（K4）。
private struct AIKeyBadges: ViewModifier {
    @ObservedObject var model: KeyboardModel
    var enabled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if enabled {
                if !model.hasFullAccess || model.aiQuotaUsed {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Brand.lockFill))
                        .overlay(Circle().strokeBorder(Brand.lockRing, lineWidth: 2))
                        .offset(x: 4, y: -4)
                        .accessibilityLabel(model.aiQuotaUsed
                            ? L("今天的免费次数用完了", "No free uses left today", "今日の無料分は終了")
                            : L("需要允许完全访问", "Needs Allow Full Access", "フルアクセスの許可が必要"))
                        .allowsHitTesting(false)
                } else if model.hasFullAccess, !model.debugUnblocked, let left = model.aiUsesLeft, left > 0 {
                    Text("\(left)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(Brand.lockRing, lineWidth: 2))
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(L("今天还剩 \(left) 次", "\(left) free uses left today", "今日あと \(left) 回"))
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - 固定的风格键（AK5）

/// 固定在 AI 栏上的风格：高 34、圆角 17、左右内边 12、14.5pt 600；改写类浅紫底主色字「✨ 简短」，问答类浅蓝底蓝字「[问答图标] 列要点」；没有 ⌄。
/// 点一下按这个风格执行（不改当前选的风格），长按弹「取消固定」。外面不再加亮边（cvbk 11-02）。
struct PinnedStyleKey: View {
    @ObservedObject var model: KeyboardModel
    let style: StylePreset
    let answer: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let running = model.isRunning && model.lastRunPin == style.id
        let locked = !model.hasFullAccess
        let key = KeyboardModel.AIKey.pin(style.id)
        // 快速模式失败（只有改写类会走快速模式）：晃一下、红底「↻ 重试」，点它照常重来（对齐清单第 61 条）。
        let failed = !answer && !running && model.quickStatus == .failed && model.lastRunPin == style.id
        let success = model.keySuccess?.key == key ? model.keySuccess?.at : nil
        let glowing = model.settings.polishAnimation && !reduceMotion
        KeySuccessClock(since: running ? nil : success, reduced: !glowing) { fx in
            face(running: running, glowing: glowing, fx: fx, failed: failed)
        }
        .overlay {
            // 执行中名字周围闪 7 颗小星（对齐清单第 63 条）：名字从左内边 12 + 图标 16 + 间距 4 开始。
            if glowing {
                KeySparkles(running: running, successAt: success, textX: 32, textWidth: Self.textWidth(style.displayName),
                            seed: 3 + abs(style.id.uuidString.hashValue % 61))
            }
        }
        .opacity(locked ? 0.45 : 1)
        .modifier(EmptyTapShake(trigger: model.keyShakes[key] ?? 0))
        .contentShape(Capsule())
        .onTapGesture { model.pinTapped(style, answer: answer) }
        .onLongPressGesture(minimumDuration: 0.45) {
            model.keyFeedback(for: .space)
            model.pinMenu = style.id
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PinFrameKey.self, value: [style.id: geometry.frame(in: .named("keyboard"))])
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(running ? (answer ? L("停止问答", "Stop answering", "質問を停止") : L("停止润色", "Stop polishing", "整えるのを停止")) + "：" + style.displayName
                            : (answer ? L("固定的问答风格：", "Pinned answer style: ", "固定した回答スタイル：") : L("固定的润色风格：", "Pinned polish style: ", "固定した整えるスタイル："))
                            + style.displayName
                            + (failed ? L("，失败，轻点重试", ". Failed, tap to retry", "、失敗・タップで再試行") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.pinTapped(style, answer: answer) }
        .accessibilityAction(named: L("取消固定", "Unpin", "固定を解除")) { model.togglePin(style) }
    }

    /// 浅色底、主色字「✨ 简短」；执行中 logo 动、键下同色投影；成功时文字隐去、绿勾、扫光；失败红底白字「↻ 重试」（宽度不变）。
    private func face(running: Bool, glowing: Bool, fx: KeySuccessFrame?, failed: Bool) -> some View {
        let animating = running || fx?.logoAnimating == true
        let bounce = fx?.logoScale ?? 1
        let textWidth = Self.textWidth(style.displayName)
        return HStack(spacing: 4) {
            Group {
                if failed {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                } else if answer {
                    AskIcon(size: 16, running: animating, glowing: glowing, bounce: bounce)
                } else {
                    // 改写类和润色键同一组 ✨（13:20 cvbk），浅紫底上用主色。
                    PolishStars(size: 15, running: animating, glowing: glowing, doneAt: nil, tint: Self.rewriteText)
                        .frame(width: 15, height: 15)
                        .scaleEffect(bounce)
                }
            }
            .frame(width: 16)
            Text(style.displayName)
                .font(.system(size: 14.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .opacity(failed ? 0 : 1)
                .overlay {
                    if failed {
                        Text(L("重试", "Retry", "再試行")).font(.system(size: 14.5, weight: .semibold))
                            .lineLimit(1).fixedSize()
                    }
                }
                .successText(fx)
                .runningFade(running)
                .overlay { AIStopIcon(running: running, moving: glowing, tint: answer ? Self.answerText : Self.rewriteText) }
        }
        .foregroundStyle(failed ? Color.white : answer ? Self.answerText : Self.rewriteText)
        .padding(.horizontal, 12)
        .frame(height: KeyboardMetrics.chipHeight)
        .overlay {
            // 绿勾在名字那块正中：左内边 12 + 图标 16 + 间距 4。
            if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: 32 + textWidth / 2, y: KeyboardMetrics.chipHeight / 2)) }
        }
        .background {
            Group {
                if failed {
                    Capsule().fill(AIKeyFX.failFill)
                } else {
                    Capsule().fill(answer ? Self.answerFill : Self.rewriteFill)
                }
            }
            .runningShadow(running, answer: answer, room: KeyboardMetrics.chipRoom)
        }
    }

    /// 名字的宽（14.5pt 600）。
    static func textWidth(_ name: String) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14.5, weight: .semibold)]).width)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
    static let rewriteFill = dynamic(0xECEAFD, 0x2E2766)
    static let rewriteText = dynamic(0x5B4BE8, 0xC9C1FF)
    static let answerFill = dynamic(0xE3EEFE, 0x1D2A44)
    static let answerText = dynamic(0x2F7BF6, 0x8DBBFF)
}

/// 固定键在键盘里的位置，「取消固定」从它下面弹出。
struct PinFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 长按固定键弹出的小框：「取消固定」。
struct UnpinBubble: View {
    @ObservedObject var model: KeyboardModel
    let style: StylePreset

    var body: some View {
        Button { model.togglePin(style) } label: {
            Label(L("取消固定", "Unpin", "固定を解除"), systemImage: "pin.slash")
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey)
                    .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.22), radius: 12, y: 8))
        }
        .buttonStyle(KeyPressStyle())
    }
}

// MARK: - 中间滑动区（AK5）

/// AI 栏中间一段：两颗主键、竖线、固定的风格键，放不下就左右滑；▭ 和撤销重做不动。
/// 哪边还有被遮住的内容，哪边就有约 9% 宽的渐隐（遮罩），滑动中实时跟着，滑到头那边才收掉（cvbk 13:14）。
struct AIKeyStrip<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fade = max(12, width * 0.09)
            let left = offset > 0.5
            let right = offset + width < contentWidth - 0.5
            ScrollView(.horizontal, showsIndicators: false) {
                content
                    // 小锁、执行中投影伸出键外 4–6pt：两头各留一点，不被裁掉。
                    .padding(.horizontal, 5)
                    .frame(height: geo.size.height)
                    // 直接读内容在滚动区里的位置，不走 preference：ScrollView 里别的子视图会带默认值把它冲掉，渐隐就一直不出（0.95_14 验证）。
                    .background(GeometryReader { inner in
                        let frame = inner.frame(in: .named("aiStrip"))
                        Color.clear
                            .onAppear { track(frame) }
                            .onChange(of: frame) { track($0) }
                    })
            }
            // iOS 26 给滚动区边缘加的渐变模糊：这条只有 34 高，会整排糊掉、发暗（真机 0.95_14），关掉，渐隐只用下面的遮罩。
            .hidingScrollEdgeEffect()
            .coordinateSpace(name: "aiStrip")
            .mask(HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: left ? fade : 0)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: right ? fade : 0)
            }
            .animation(.easeOut(duration: 0.15), value: left)
            .animation(.easeOut(duration: 0.15), value: right))
        }
    }

    private func track(_ frame: CGRect) {
        if abs(offset + frame.minX) > 0.25 { offset = -frame.minX }
        if abs(contentWidth - frame.width) > 0.25 { contentWidth = frame.width }
    }
}


/// 两颗风格键在键盘里的位置（键盘坐标），下拉框从它下面弹出。
struct RowChipFrameKey: PreferenceKey {
    static var defaultValue: [KeyboardModel.AIRow: CGRect] = [:]
    static func reduce(value: inout [KeyboardModel.AIRow: CGRect], nextValue: () -> [KeyboardModel.AIRow: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - 风格下拉框（KB1、KB2）

/// 点润色键或问答键的 ⌄：往下弹的下拉框，盖在按键上。宽 196、圆角 12、卡片底色、阴影 0 8 24 rgba(30,40,80,.22)。
/// 小标题「润色风格 · 点图钉固定到 AI 栏」11.5 灰；每项高 36、字 15，当前那条浅紫底 + 主色 600 + ✓，最右一颗图钉（AK5）。
/// 顺序就是 App 列表里的顺序。底下一行「已固定 N / 5 · 长按 AI 栏上的固定键也能取消」。
/// 回答卡收起和展开都一样；点一条就换、框收起；点图钉固定 / 取消，框不收。
struct StyleDropdown: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    /// 键盘里往下还剩多高，放不下时里面滚动。
    var maxHeight: CGFloat

    static let width: CGFloat = 224
    private static let itemHeight: CGFloat = 36
    private static let headerHeight: CGFloat = 26
    private static let footerHeight: CGFloat = 38
    private static let addHeight: CGFloat = 36

    private var answer: Bool { row == .answerStyles }

    var body: some View {
        let styles = answer ? model.settings.answerStyles : model.settings.styles
        let selectedID = answer ? model.settings.selectedAnswerStyle?.id : model.settings.selectedStyle?.id
        let natural = Self.headerHeight + CGFloat(styles.count) * Self.itemHeight + Self.addHeight + Self.footerHeight + 12
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text((answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル"))
                 + L(" · 点图钉固定到 AI 栏", " · Tap the pin to add to the AI bar", " · ピンで AI バーに固定"))
                .font(.system(size: 11.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(DropdownStyle.hint)
                .padding(.horizontal, 10)
                .frame(height: Self.headerHeight, alignment: .leading)
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(styles) { style in
                            item(style, selected: style.id == selectedID).id(style.id)
                        }
                        addRow
                    }
                }
                .scrollDisabled(natural <= maxHeight)
                .onAppear { if let selectedID, natural > maxHeight { reader.scrollTo(selectedID, anchor: .center) } }
            }
            // 满 5 个再点空心图钉：这一行变红写「最多固定 5 个」（按键区顶上的提示会被下拉框盖住）。
            let count = model.settings.pinnedStyles.count, limit = EnclaveSettings.maxPinnedStyles
            Text(model.pinLimitHit
                 ? L("最多固定 \(limit) 个，先点实心图钉取消一个", "Up to \(limit) pins. Unpin one first.", "固定は \(limit) つまで。先に 1 つ解除してください")
                 : L("已固定 \(count) / \(limit) · 长按 AI 栏上的固定键也能取消",
                     "\(count) / \(limit) pinned · Long-press a pinned key to unpin",
                     "固定 \(count) / \(limit) · AI バーで長押しでも解除"))
                .font(.system(size: 11, weight: model.pinLimitHit ? .semibold : .regular))
                .foregroundStyle(model.pinLimitHit ? Color(UIColor.systemRed) : DropdownStyle.hint)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: Self.footerHeight, maxHeight: Self.footerHeight, alignment: .leading)
        }
        .padding(6)
        .frame(width: Self.width, height: max(Self.headerHeight + Self.itemHeight + Self.addHeight + Self.footerHeight + 12, min(natural, maxHeight)), alignment: .top)
        .background(shape.fill(DropdownStyle.fill)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.22), radius: 12, y: 8))
        // 深色下和按键颜色接近：加一圈细边（和拼音键弹框一样）。
        .overlay(shape.strokeBorder(DropdownStyle.stroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル"))
    }

    /// 最后一行「＋ 添加润色风格 / 问答风格」（v308）：打开 App 里对应的风格列表。
    private var addRow: some View {
        Button {
            model.aiRow = nil
            model.openContainingApp(answer ? "enclave://prompts-answer" : "enclave://prompts")
        } label: {
            Label(answer ? L("添加问答风格", "Add answer style", "回答スタイルを追加") : L("添加润色风格", "Add polish style", "整えるスタイルを追加"),
                  systemImage: "plus")
                .font(.system(size: 15))
                .foregroundStyle(DropdownStyle.selectedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: Self.addHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
    }

    private func item(_ style: StylePreset, selected: Bool) -> some View {
        let pinned = model.settings.isPinned(style.id)
        return HStack(spacing: 0) {
            Button {
                answer ? model.selectAnswerStyle(style) : model.selectStyle(style)
            } label: {
                HStack(spacing: 8) {
                    Text(style.displayName)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DropdownStyle.selectedText : DropdownStyle.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DropdownStyle.selectedText)
                    }
                }
                .padding(.leading, 10)
                .frame(height: Self.itemHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
            // 图钉：空心没固定，实心主色已固定。点按区 36×36。
            Button { model.togglePin(style) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(pinned ? DropdownStyle.selectedText : DropdownStyle.hint)
                    .frame(width: 36, height: Self.itemHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel(pinned ? L("取消固定", "Unpin", "固定を解除") : L("固定到 AI 栏", "Pin to AI bar", "AI バーに固定"))
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? DropdownStyle.selectedFill : Color.clear))
    }
}

private enum DropdownStyle {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
    /// 浅色白底；深色 #5C5C60，比按键（#474749）亮一档，盖在按键上分得清（同拼音键弹框）。
    static let fill = dynamic(0xFFFFFF, 0x5C5C60)
    static let stroke = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : .clear })
    static let selectedFill = dynamic(0xECEAFD, 0x2E2766)
    static let selectedText = dynamic(0x5B4BE8, 0xC9C1FF)
    static let text = dynamic(0x1C1C1E, 0xFFFFFF)
    static let hint = dynamic(0x8E8E93, 0xAEAEB2)
}

// MARK: - 识意框：问问题或提要求

/// 识意框（MG2）：回答卡下半格，左右内边 12、15pt 字，一行；问题太长从开头省略，不挤右边的联网按钮。
/// 抽屉展开时键盘打的字进这里，打拼音时候选栏照常出在 AI 栏；重新展开时整段全选，直接打字覆盖。
struct AskField: View {
    @ObservedObject var model: KeyboardModel

    private static let caret: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 19)).image { _ in
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 2, height: 19), cornerRadius: 1).fill()
    }.withRenderingMode(.alwaysTemplate)

    var body: some View {
        let editing = model.target == .instruction
        HStack(spacing: 8) {
            // 帮回（方案 C）：左边「回 这份方案… ⌄」，固定宽度、写要求时也不缩。
            if model.helpReply != nil {
                HelpSentenceCapsule(model: model)
                    .layoutPriority(1)
            }
            Group {
                if editing {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 || model.isComposing
                        line(caretVisible: on)
                    }
                } else {
                    line(caretVisible: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.focusAsk() }
            // VoiceOver：整行读成一个输入框，读出框里的字；轻点两下开始在这里打字。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("识意输入框", "Ask field", "たずねる入力欄"))
            .accessibilityValue(model.instruction.isEmpty ? placeholder : model.instruction + model.composition)
            .accessibilityHint(editing ? L("正在输入", "Typing here", "入力中") : L("轻点两下在这里输入", "Double-tap to type here", "ダブルタップしてここに入力"))
            .accessibilityAddTraits(editing ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.focusAsk() }
            // 未激活、空着：右边 12pt「点这里输入」。
            if !editing, model.instruction.isEmpty, model.helpReply == nil {
                Text(L("点这里输入", "Tap to type", "タップして入力"))
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.askFaint)
                    .lineLimit(1)
                    .fixedSize()
                    .onTapGesture { model.focusAsk() }
                    .accessibilityHidden(true)
            }
            // 帮回：框里不放按钮，写完点键盘上的帮回键或回车执行（RG4）。
            if model.helpReply == nil { searchButton }
        }
        .padding(.horizontal, model.helpReply != nil ? 8 : 12)
        .font(.system(size: 15))
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            // 帮回倒计时：整条从左往右变绿（HB29 挪进识意框）。
            if let ends = model.helpReply?.countdownEnds { HelpCountdownFill(ends: ends) }
        }
    }

    /// 「使用联网查询」（MG6）：28 高、圆角 14，问答浅蓝底、1pt 天蓝 40% 内描边；联网过的回答换成灰字「已联网 · Kimi」（MG7）。
    @ViewBuilder
    private var searchButton: some View {
        if !model.isRunning, model.session?.currentIsAnswer == true, let searchedBy = model.session?.currentSearchedBy {
            Label(L("已联网 · \(searchedBy)", "Searched · \(searchedBy)", "検索済み · \(searchedBy)"), systemImage: "globe")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        } else if model.canForceSearch {
            Button { model.forceWebSearch() } label: {
                Label(L("使用联网查询", "Search the web", "ウェブで調べる"), systemImage: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 7)
                    .padding(.trailing, 9)
                    .frame(height: 28)
                    .foregroundStyle(Brand.modeAnswerText)
                    .background(Capsule().fill(Brand.modeAnswerFill))
                    .overlay(Capsule().strokeBorder(Brand.answerBorder.opacity(0.4), lineWidth: 1))
                    .fixedSize()
            }
            .buttonStyle(KeyPressStyle())
        }
    }

    private var placeholder: String {
        if model.helpReply?.countdownEnds != nil {
            return L("点这里先说要求，不点就自动写", "Tap to add a request, or it writes on its own", "タップして要望を書く。触らなければ自動で作成")
        }
        if model.helpReply != nil {
            return L("想怎么回？比如：委婉拒绝", "How to reply? e.g. say no nicely", "どう返す？例：やんわり断る")
        }
        return L("问个问题，或说说这段话想怎么改", "Ask anything, or say how to change it", "質問するか、どう直すかを書いてください")
    }

    /// 光标前、正在拼的拼音（紫色下划线）、光标、光标后。全选时整段垫浅紫底。写长了从开头省略，光标那头总露着。
    @ViewBuilder
    private func line(caretVisible: Bool?) -> some View {
        let text = model.instruction
        let composing = model.target == .instruction ? model.composition : ""
        if text.isEmpty && composing.isEmpty, let ends = model.helpReply?.countdownEnds {
            HStack(spacing: 5) {
                HelpCountdownBadge(ends: ends)
                Text(placeholder)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        } else if text.isEmpty && composing.isEmpty {
            Text(placeholder)
                .foregroundStyle(caretVisible == nil ? Brand.askFaint : Brand.askPlaceholderActive)
                .lineLimit(1)
                .minimumScaleFactor(model.helpReply != nil ? 0.8 : 1)
                .overlay(alignment: .leading) {
                    if let caretVisible { caretImage(caretVisible).offset(x: -2) }
                }
        } else if model.askSelected {
            HStack(spacing: 0) {
                Text(text)
                    .foregroundStyle(Brand.askText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Brand.askSelection).padding(.vertical, -2))
                Text(composing).foregroundStyle(Brand.askText).underline(color: Brand.askCaret).lineLimit(1)
            }
        } else {
            let split = text.index(text.startIndex, offsetBy: min(model.instructionCaret, text.count))
            let atEnd = split == text.endIndex
            (Text(text[..<split])
                + Text(composing).underline(color: Brand.askCaret)
                + (caretVisible.map { Text(Image(uiImage: Self.caret)).foregroundColor(Brand.askCaret.opacity($0 ? 1 : 0)).baselineOffset(-4) } ?? Text(""))
                + Text(text[split...]))
                // 未激活时留着的字变灰；帮回时执行过的要求是绿字（RG4），再改就变回普通颜色。
                .foregroundStyle(model.helpAskExecuted ? HelpStyle.title : (caretVisible == nil ? Brand.askSub : Brand.askText))
                .fontWeight(model.helpAskExecuted ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(atEnd ? .head : .tail)
        }
    }

    private func caretImage(_ visible: Bool) -> some View {
        Image(uiImage: Self.caret).foregroundStyle(Brand.askCaret.opacity(visible ? 1 : 0))
    }
}


// MARK: - 停止图标（PS6）

/// 执行中按键上的停止图标：26×15 胶囊（两端半圆），白 18% 底、白 38% 细边；中间 6.4pt 白色圆角方块；
/// 一段白色高光沿边每 1.2 秒绕一圈。开始生成时淡入（略放大），停止 / 完成后淡回文字。logo 和小星照常动。
struct AIStopIcon: View {
    var running: Bool
    /// 关了发光动画或减弱动态效果：高光不绕圈，停在上边。
    var moving: Bool
    var tint: Color

    var body: some View {
        Group {
            if moving {
                // 不在执行时暂停逐帧重画：那时图标透明度是 0，但没暂停的 TimelineView(.animation) 照样每帧刷新，
                // 每颗 AI 键一个，键盘一显示主线程就一直被占（0.96 真机上弹键盘发卡）。暂停后停在最后一帧，淡出时不跳。
                TimelineView(.animation(minimumInterval: nil, paused: !running)) { context in
                    icon(phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2)
                }
            } else {
                icon(phase: 0)
            }
        }
        .frame(width: 26, height: 15)
        .opacity(running ? 1 : 0)
        .scaleEffect(running ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.25), value: running)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func icon(phase: Double) -> some View {
        let length = 0.22
        let start = phase, end = phase + length
        return ZStack {
            Capsule().fill(tint.opacity(0.18))
            Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 1.4)
            // 高光一段占周长 22%，绕到起点时分两截画。
            Capsule().inset(by: 0.8).trim(from: start, to: min(end, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            if end > 1 {
                Capsule().inset(by: 0.8).trim(from: 0, to: end - 1)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(tint).frame(width: 6.4, height: 6.4)
        }
    }
}

private extension View {
    /// 执行中文字淡出（带一点模糊），停止后淡回来，和停止图标交叉淡变。
    func runningFade(_ running: Bool) -> some View {
        opacity(running ? 0 : 1)
            .blur(radius: running ? 2 : 0)
            .animation(.easeInOut(duration: 0.25), value: running)
    }
}
