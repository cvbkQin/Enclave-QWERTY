import SwiftUI

/// 键盘主体。
/// AI 栏永远紧贴按键上方，收起和展开是同一条：[展开/收起] [✨] [润色▾] … [撤销|重做]；打拼音时这一行换成候选。
/// 展开时 AI 栏上面是结果卡片和动作行（替换、插入）；打开「正式▾」时 AI 栏上面再加风格浮层。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    private var inset: CGFloat { KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX }

    var body: some View {
        VStack(spacing: 0) {
            if let gate = model.gate {
                // 提示卡单独占上方，结果卡片和风格菜单先让开。
                GateCard(model: model, gate: gate)
                    .frame(height: KeyboardMetrics.gateHeight(gate))
                    .padding(.horizontal, inset)
                    .padding(.top, KeyboardMetrics.panelTop)
            } else if model.aiExpanded {
                VStack(spacing: KeyboardMetrics.panelSpacing) {
                    ResultCard(model: model)
                        .frame(height: KeyboardMetrics.cardHeight(tall: model.cardTall, aiLabel: model.showsAILabel))
                    actionRow
                        .frame(height: KeyboardMetrics.actionRow)
                }
                .padding(.horizontal, inset)
                .padding(.top, KeyboardMetrics.panelTop)
            }
            if model.gate == nil, model.styleMenuOpen {
                StyleMenu(model: model)
                    .frame(height: KeyboardMetrics.menuHeight(requestLines: model.requestLines))
                    .padding(.horizontal, inset)
                    .padding(.top, model.aiExpanded ? KeyboardMetrics.panelSpacing : KeyboardMetrics.panelTop)
            }
            if model.showsTrialReminder {
                TrialReminderStrip(model: model)
                    .frame(height: KeyboardMetrics.trialReminderHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, KeyboardMetrics.panelTop)
            }
            ZStack {
                // 候选栏一直留着、不打字时藏起来：放在 if 里的话每打完一个词它就被拆掉，下一个字母再整个重建（连同里面的滚动视图）。
                candidateBar
                    .opacity(showsCandidateBar ? 1 : 0)
                    .allowsHitTesting(showsCandidateBar)
                    .accessibilityHidden(!showsCandidateBar)
                if !showsCandidateBar {
                    if model.target == .card {
                        cardEditHint
                    } else {
                        aiBar
                    }
                }
            }
            .frame(height: KeyboardMetrics.topRow)
            KeysView(model: model)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
                .layoutPriority(1)
        }
        // 系统给的高度不够时从顶上裁，按键始终完整贴在底部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 使用指引「一键应用」后的小手指，画在键盘里面。
        .coachHandOverlay(model)
        .clipped()
    }

    // MARK: - AI 栏

    /// 在卡片里改结果时 AI 栏换成提示。
    private var cardEditHint: some View {
        HStack(spacing: 8) {
            Label(L("正在修改结果", "Editing result", "結果を編集中"), systemImage: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Brand.returnSoftFill))
            Text(L("打字进卡片，按住空格左右滑动移光标", "Typing goes into the card. Touch and hold space and slide to move the cursor", "カードに入力します。スペースを長押ししてスライドでカーソル移動"))
                .font(.system(size: 13))
                .foregroundStyle(Brand.cardNote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset)
    }

    private var aiBar: some View {
        HStack(spacing: 6) {
            PanelToggleButton(expanded: model.aiExpanded, hasNew: model.showsNewResult) {
                model.endCoach()
                model.setAIExpanded(!model.aiExpanded)
            }
            PolishButton(model: model)
            // 风格按钮优先完整显示，地方不够时失败提示换成短的。
            // 快速模式替换成功后 3 秒，这个位置换成「AI 生成 · 已替换」（CP9），点它展开看结果。
            if model.quickStatus == .done, !model.aiExpanded {
                ReplacedPill { model.setAIExpanded(true) }
                    .layoutPriority(1)
                    .transition(.opacity)
            } else {
                StyleChip(model: model).layoutPriority(1)
            }
            if model.quickStatus == .failed, !model.aiExpanded {
                QuickRetryLabel(model: model)
            }
            Spacer(minLength: 0)
            UndoRedoPair(model: model)
        }
        .padding(.horizontal, inset)
    }

    /// 打拼音、或者上屏后有联想时显示候选栏。
    private var showsCandidateBar: Bool { model.isComposing || model.showsPredictions }

    /// 打拼音时的候选栏，右边的箭头展开整页候选；显示联想时箭头换成关闭。
    private var candidateBar: some View {
        let predicting = !model.isComposing
        return HStack(spacing: 0) {
            // 点击判定在 UIKit 里做，见 CandidateStrip。
            CandidateStrip(model: model)
            Divider().frame(height: 22)
            Button {
                if predicting { model.dismissPredictions() } else { model.candidatesExpanded.toggle() }
            } label: {
                Image(systemName: predicting ? "xmark" : (model.candidatesExpanded ? "chevron.up" : "chevron.down"))
                    // 联想时的关闭键小一号、灰色：联想只是建议，关闭键不和字抢眼（UI 稿 KP1）。
                    .font(.system(size: predicting ? 15 : 17, weight: predicting ? .medium : .regular))
                    .foregroundStyle(predicting ? Color.secondary : Color.primary)
                    // 放宽到 54pt，靠右边缘也好按。
                    .frame(width: 54)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
        }
    }

    // MARK: - 动作行

    /// 结果卡片下面只有替换和插入；用过以后按钮显示「✓ 已替换」「✓ 已插入」。
    @ViewBuilder
    private var actionRow: some View {
        if model.target == .card {
            HStack(spacing: 6) {
                PanelButton(title: L("取消修改", "Cancel", "キャンセル"), systemImage: nil, kind: .plain) { model.cancelCardEdit() }
                PanelButton(title: L("完成修改", "Done", "完了"), systemImage: "checkmark", kind: .primary) { model.finishCardEdit() }
            }
        } else {
            useRow
        }
    }

    private var useRow: some View {
        let replaced = model.resultUse == .replaced
        let inserted = model.resultUse == .inserted
        return HStack(spacing: 6) {
            PanelButton(title: replaced ? L("已替换", "Replaced", "置き換え済み") : L("替换", "Replace", "置き換え"),
                        systemImage: replaced ? "checkmark" : "arrow.left.arrow.right",
                        kind: replaced ? .done : .primary) { model.replace() }
                .disabled(!model.hasResult || replaced)
                .coachTarget(.replace, active: model.coachDisplay?.target == .replace)
            PanelButton(title: inserted ? L("已插入", "Inserted", "挿入済み") : L("插入", "Insert", "挿入"),
                        systemImage: inserted ? "checkmark" : "text.insert",
                        kind: inserted ? .done : .outlined) { model.insert() }
                .disabled(!model.hasResult || inserted)
                .coachTarget(.insert, active: model.coachDisplay?.target == .insert)
        }
    }
}

// MARK: - AI 栏的按钮

/// 展开/收起 AI 面板（结果卡片 + 替换 / 插入），AI 栏最左边 44×34 的面板图标胶囊（方案 B）。
/// 收起时有没看过的新结果：图标变紫、右上角紫点；展开时浅紫底紫描边，和选择器打开时一样。
struct PanelToggleButton: View {
    var expanded: Bool
    var hasNew: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "rectangle.tophalf.inset.filled")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(expanded ? Brand.toggleOpenIcon : (hasNew ? Brand.newResultIcon : Color.primary))
                .frame(width: 44, height: KeyboardMetrics.chipHeight)
                .background(Capsule().fill(expanded ? Brand.toggleOpenFill : KeyStyle.charKey))
                .overlay(Capsule().strokeBorder(Brand.toggleOpenStroke, lineWidth: expanded ? 1.5 : 0))
                .overlay(alignment: .topTrailing) {
                    if hasNew {
                        Circle().fill(Brand.newResultDot)
                            .frame(width: 10, height: 10)
                            .padding(2)
                            .background(Circle().fill(Brand.keyboardBack))
                            .offset(x: 3, y: -3)
                    }
                }
                // 点按区上下各扩 5pt，至少 44×44。
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = expanded ? L("收起结果", "Hide result", "結果を隠す") : L("展开结果", "Show result", "結果を表示")
        return hasNew ? base + L("，有新结果", ", new result", "、新しい結果あり") : base
    }
}

/// 「✨」主按钮（D1）：只放图标，58×34 渐变胶囊，按当前提示词改输入框里的话；收起和展开都是这一颗。
/// 生成中同位置变成深灰底白色方块「停止」，再点一下取消；流光描边、闪光照旧放在这颗按钮上。
struct PolishButton: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var doneAt: Date?

    /// 这次是点「润色」开始的：收起和展开都在按钮上放特效；「再润」时这里不动。
    private var quickRunning: Bool { model.isRunning && model.runOrigin == .polish }
    /// 关了发光动画或开了减弱动态效果：只留星星轻微闪动。
    private var fullMotion: Bool { model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        let shape = Capsule()
        Button {
            model.isRunning ? model.stop() : model.sparkleTapped()
        } label: {
            Group {
                if model.isRunning {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.white).frame(width: 12, height: 12)
                } else {
                    PolishStars(size: 20, running: false, glowing: fullMotion, doneAt: fullMotion ? doneAt : nil)
                }
            }
            .frame(width: KeyboardMetrics.polishButtonWidth, height: KeyboardMetrics.chipHeight)
            .background(shape.fill(fill))
            .overlay {
                if quickRunning && fullMotion {
                    PolishButtonGlow().clipShape(shape)
                }
            }
            .overlay(alignment: .topLeading) {
                // 没开完全访问、试用结束后今天的次数用完：右上角一个小锁（P01）。
                if !model.hasFullAccess || model.aiQuotaUsed {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Brand.lockFill))
                        .overlay(Circle().strokeBorder(Brand.lockRing, lineWidth: 2))
                        .offset(x: KeyboardMetrics.polishButtonWidth - 12, y: -4)
                        .accessibilityLabel(model.aiQuotaUsed
                            ? L("今天的免费次数用完了", "No free uses left today", "今日の無料分は終了")
                            : L("需要允许完全访问", "Needs Allow Full Access", "フルアクセスの許可が必要"))
                }
            }
            .overlay(alignment: .topTrailing) {
                // 试用结束、今天还有免费次数：右上角显示剩几次（K4）。
                if let left = freeUsesLeft {
                    Text("\(left)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(Brand.lockRing, lineWidth: 2))
                        .offset(x: 6, y: -7)
                        .accessibilityLabel(L("今天还剩 \(left) 次", "\(left) free uses left today", "今日あと \(left) 回"))
                }
            }
            // 点按区上下各扩 5pt，至少 58×44。
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(model.isRunning ? L("正在生成，轻点取消", "Working. Tap to cancel", "生成中。タップでキャンセル") : L("执行当前提示词", "Run prompt", "プロンプトを実行"))
        .coachTarget(.sparkle, active: model.coachDisplay?.target == .sparkle)
        .onChange(of: model.finished) { finished in
            if finished?.origin == .polish { flashDone(at: finished?.at) }
        }
    }

    /// 完成时星星闪金 1.2 秒，之后清掉：doneAt 一直留着的话，星星里的 TimelineView 会一直按屏幕刷新率重画，打字时也在耗电、抢主线程。
    private func flashDone(at date: Date?) {
        doneAt = date
        guard let date else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if doneAt == date { doneAt = nil }
        }
    }

    /// 试用结束、今天还有次数时的剩余次数；试用中、已购买、用完时为 nil。
    private var freeUsesLeft: Int? {
        guard model.hasFullAccess, !model.debugUnblocked, let left = model.aiUsesLeft else { return nil }
        return left > 0 ? left : nil
    }

    private var fill: AnyShapeStyle {
        if model.isRunning { return AnyShapeStyle(Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)) }
        let gradient = LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]], startPoint: .leading, endPoint: .trailing)
        return (model.aiBlocked || model.aiQuotaUsed) ? AnyShapeStyle(gradient.opacity(0.35)) : AnyShapeStyle(gradient)
    }
}

/// 生成中按钮里的动画：1.5pt 流光描边（1.6 秒一圈，外面不加光晕）、60pt 白色光带扫过、一圈白色小闪光。
/// 「润色」用品牌色描边和 10 颗闪光；「再润」用粉紫描边和 7 颗。
struct PolishButtonGlow: View {
    typealias Sparkle = (x: CGFloat, y: CGFloat, d: CGFloat, period: Double, offset: Double)

    /// 小闪光的位置（相对 84×34 的按钮，x、y、大小）和周期。
    static let polishSparkles: [Sparkle] = [
        (4, 8, 6, 1.5, 0.0), (9, 22, 5, 1.7, 0.6), (21, 2, 6, 1.9, 1.1), (29, 26, 5, 1.6, 0.3), (39, 1, 5, 1.8, 0.9),
        (52, 27, 6, 1.5, 1.3), (60, 1, 5, 1.7, 0.2), (72, 6, 6, 1.9, 0.7), (76, 20, 6, 1.6, 1.5), (65, 26, 5, 1.8, 0.4),
    ]
    /// 「再润」73×30 按钮上的 7 颗。
    static let rerunSparkles: [Sparkle] = [
        (4, 7, 5, 1.5, 0.0), (9, 20, 4, 1.7, 0.6), (20, 2, 5, 1.9, 1.1), (46, 1, 4, 1.6, 0.3),
        (56, 22, 5, 1.8, 0.9), (64, 5, 5, 1.5, 1.3), (36, 23, 4, 1.7, 0.2),
    ]
    /// 「再润」描边：#A855F7 → #EC4899 → #FDE68A → #F0ABFC。
    static let rerunRing: [Color] = [
        Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255),
        Color(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255),
        Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255),
        Color(red: 0xF0 / 255, green: 0xAB / 255, blue: 0xFC / 255),
    ]

    var ring: [Color] = Brand.gradient
    var sparkles: [Sparkle] = Self.polishSparkles
    /// 闪光坐标对应的按钮大小。
    var designSize = CGSize(width: 84, height: 34)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
                let sx = geo.size.width / designSize.width, sy = geo.size.height / designSize.height
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.32), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 60, height: geo.size.height)
                        .blur(radius: 4)
                        .offset(x: -60 + (geo.size.width + 60) * phase)
                    ForEach(Array(sparkles.enumerated()), id: \.offset) { _, s in
                        let t = (time + s.offset).truncatingRemainder(dividingBy: s.period) / s.period
                        let scale = sin(.pi * t)
                        FourPointStar()
                            .fill(Color.white)
                            .frame(width: s.d, height: s.d)
                            .scaleEffect(scale)
                            .rotationEffect(.degrees(20 * t))
                            .shadow(color: .white.opacity(0.8), radius: 1.5)
                            .position(x: (s.x + s.d / 2) * sx, y: (s.y + s.d / 2) * sy)
                    }
                    Capsule().strokeBorder(AngularGradient(colors: ring + [ring[0]], center: .center,
                                                           angle: .degrees(phase * 360)),
                                           lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 润色按钮里的白色星星组：平时不动；润色中大星几乎不动（1.0↔1.08），小星错开闪（0.6↔1.4 倍、35%↔100%）带白色微光；
/// 完成时 1.2 秒内变金色放大一下再回白色。glowing 为 false（关了动画、减弱动态效果）时只轻微闪动。
struct PolishStars: View {
    var size: CGFloat
    var running: Bool
    var glowing: Bool
    var doneAt: Date?

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
                    .fill(Color.white)
                    .overlay(FourPointStar().fill(Brand.gold).opacity(gold))
                    .frame(width: size * star.d, height: size * star.d)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .shadow(color: done != nil ? Brand.gold.opacity(0.9 * gold) : .white.opacity(running && glowing ? 0.9 * wave : 0),
                            radius: 3)
                    .position(x: size * star.x, y: size * star.y)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 「润色▾」：显示当前提示词的名字，写了要求时显示「按要求」并描紫边；点开提示词面板。宽 72–140，超出截断。
struct StyleChip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let locked = !model.hasFullAccess
        let highlighted = !locked && (model.styleMenuOpen || !model.instruction.isEmpty)
        Button { locked ? model.showFullAccessTip() : model.toggleStyleMenu() } label: {
            HStack(spacing: 0) {
                Text(title).lineLimit(1).truncationMode(.tail)
                // 名字和 ▾ 之间的竖线，只是视觉上分开，整颗还是一个按钮；线和箭头不参与截断。
                Rectangle()
                    .fill(highlighted ? Brand.chipDividerOn : Brand.chipDivider)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 8)
                    .layoutPriority(1)
                Image(systemName: model.styleMenuOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .layoutPriority(1)
            }
            .font(.system(size: 14, weight: highlighted ? .semibold : .regular))
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(minWidth: 72, maxWidth: 140)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: KeyboardMetrics.chipHeight)
            .foregroundStyle(highlighted ? Brand.menuText : Color.primary)
            .background(Capsule().fill(highlighted ? Brand.menuFill : KeyStyle.charKey))
            .overlay(Capsule().strokeBorder(Brand.menuStroke, lineWidth: highlighted ? 1.2 : 0))
            .opacity(locked ? 0.45 : 1)
        }
        .buttonStyle(KeyPressStyle())
    }

    private var title: String {
        guard model.instruction.isEmpty else { return L("按要求", "Custom", "指示あり") }
        return model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
    }
}

/// 撤销和重做拼成一个胶囊，中间一条细线。AI 栏最右边，收起和展开都在。
struct UndoRedoPair: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 0) {
            half("arrow.uturn.backward", enabled: model.canUndo) { model.undo() }
            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).padding(.vertical, 9)
            half("arrow.uturn.forward", enabled: model.canRedo) { model.redo() }
        }
        .frame(width: 76, height: KeyboardMetrics.chipHeight)
        .background(Capsule().fill(KeyStyle.charKey))
    }

    private func half(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
    }
}

/// 动作行的按钮。primary 是实心紫（替换），outlined 是紫色描边（插入），done 是用过之后的淡紫底。
struct PanelButton: View {
    /// plain：白底深灰字（「取消修改」）。
    enum Kind { case primary, outlined, done, plain }

    var title: String
    var systemImage: String?
    var kind: Kind
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground)
            .background(shape.fill(fill))
        }
        .buttonStyle(KeyPressStyle())
    }

    /// 替换用润色的蓝紫渐变，插入用青到靛蓝，都是白字；不能点时一律灰底灰字，不做半透明。
    private var fill: AnyShapeStyle {
        guard kind == .done || kind == .plain || isEnabled else { return AnyShapeStyle(Brand.disabledFill) }
        switch kind {
        case .primary: return AnyShapeStyle(LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        case .outlined: return AnyShapeStyle(Brand.insertGradient)
        case .done: return AnyShapeStyle(Brand.returnSoftFill)
        case .plain: return AnyShapeStyle(KeyStyle.charKey)
        }
    }

    private var foreground: Color {
        if kind == .done { return Brand.deepPurple }
        if kind == .plain { return Brand.cardBody }
        return isEnabled ? .white : Brand.disabledText
    }
}

// MARK: - 「正式▾」浮层

/// 提示词面板，尖角指向「润色▾」：上面一行选提示词，下面一行写要求和「执行」。
/// 点提示词只切换，不马上改；点「执行」或回车「执行」才开始，面板不收起，再点「润色▾」才收。
struct StyleMenu: View {
    @ObservedObject var model: KeyboardModel

    /// 尖角对准「润色▾」：展开键 + 间距 + ✨ 键 + 间距，再往右到按钮中间附近。
    private let arrowX: CGFloat = KeyboardMetrics.chipHeight + 6 + KeyboardMetrics.polishButtonWidth + 6 + 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                rowLabel(L("提示词", "Prompts", "プロンプト"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(model.settings.styles) { style in
                            MenuStyleTag(title: style.displayName, selected: style.id == model.settings.selectedStyle?.id) {
                                model.selectStyle(style)
                            }
                        }
                    }
                }
                .hidingScrollEdgeEffect()
            }
            .frame(height: 32)
            // 要求框写长了往下变高：「要求」对齐第一行，「执行」贴着框的底部。
            HStack(alignment: .top, spacing: 8) {
                rowLabel(L("要求", "Prompt", "指示"))
                    .frame(height: 32)
                RequestField(model: model)
                MenuPolishButton(model: model)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 1)
            }
            .frame(height: KeyboardMetrics.requestFieldHeight(lines: model.requestLines))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8 + MenuBubble.arrowHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 清爽紫：纯白底不描紫边，一圈极淡的轮廓加柔和投影。
        .background(MenuBubble(arrowX: arrowX).fill(Brand.panelFill)
            .shadow(color: .black.opacity(0.06), radius: 0.5)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.10), radius: 10, y: 6))
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Brand.panelLabel)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 34, alignment: .leading)
    }
}

/// 面板里的「执行」：实心胶囊，紫到粉的渐变；按选好的提示词和要求开始改，生成中样子不变，再点一下取消。
/// 面板收起时直接替换输入框，展开时进结果卡片。
struct MenuPolishButton: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var doneAt: Date?

    /// 这次是点「再润」开始的：特效放在这个按钮上，和「润色」同一套，换成粉紫。
    private var running: Bool { model.isRunning && model.runOrigin == .rerun }
    private var fullMotion: Bool { model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        Button {
            model.isRunning ? model.stop() : model.menuPolishTapped()
        } label: {
            HStack(spacing: 4) {
                PolishStars(size: 13, running: running, glowing: fullMotion, doneAt: fullMotion ? doneAt : nil)
                Text(L("执行", "Run", "実行")).lineLimit(1).fixedSize()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            // 英文、日文更长时按内容撑开，不缩字号。
            .padding(.horizontal, 10)
            .frame(minWidth: 72, minHeight: 30, maxHeight: 30)
            .background(Capsule().fill(Brand.rerunGradient))
            .overlay {
                if running && fullMotion {
                    PolishButtonGlow(ring: PolishButtonGlow.rerunRing, sparkles: PolishButtonGlow.rerunSparkles,
                                     designSize: CGSize(width: 73, height: 30))
                        .clipShape(Capsule())
                }
            }
            .opacity(model.aiBlocked && !model.isRunning ? 0.4 : 1)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(model.isRunning ? L("正在生成，轻点取消", "Working. Tap to cancel", "生成中。タップでキャンセル") : L("执行", "Run", "実行"))
        .coachTarget(.run, active: model.coachDisplay?.target == .run)
        .onChange(of: model.finished) { finished in
            if finished?.origin == .rerun { flashDone(at: finished?.at) }
        }
    }

    /// 同「润色」按钮：闪金完就清掉，免得星星一直重画。
    private func flashDone(at date: Date?) {
        doneAt = date
        guard let date else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if doneAt == date { doneAt = nil }
        }
    }
}

/// 点「润色」时 AI 栏上方的提示卡。
/// 没开完全访问（P02）：说明打字不受影响，「去开启」打开 App 再跳到系统设置。
/// 首次发送前确认（P03/P04）：写明发到哪个地址、发什么，「同意并润色」记下地址并开始。
struct GateCard: View {
    @ObservedObject var model: KeyboardModel
    let gate: KeyboardModel.AIGate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch gate {
            case .fullAccess: fullAccess
            case .privacy: privacy
            case .noKey: noKey
            case .consent(let endpoint, let previous): consent(endpoint, previous: previous)
            case .quotaUsed: quotaUsed
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.panelFill)
            .shadow(color: .black.opacity(0.06), radius: 0.5)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.10), radius: 10, y: 6))
    }

    @ViewBuilder
    private var fullAccess: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Brand.returnSoftFill))
            Text(L("AI 润色需要开启「允许完全访问」", "AI Polish needs Allow Full Access", "AI 機能には「フルアクセスを許可」が必要です")).font(.system(size: 14, weight: .semibold))
        }
        Text(L("打字不受影响。开启后才能用 AI 润色，App 里的键盘设置也会同步过来。", "Typing still works. Turn it on to use AI Polish and to sync keyboard settings from the app.", "入力はそのまま使えます。オンにすると AI 機能が使え、アプリのキーボード設定も同期されます。"))
            .font(.system(size: 13))
            .foregroundStyle(Brand.cardBody)
            .fixedSize(horizontal: false, vertical: true)
        // 没开完全访问时 iOS 不让键盘打开任何 App，只能把路径写出来。
        VStack(alignment: .leading, spacing: 3) {
            Text(L("在系统设置里开启", "Turn it on in Settings", "設定でオンにする")).font(.system(size: 11.5)).foregroundStyle(Brand.disabledText)
            settingsPath.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.tagFill))
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Text(L("也可以打开飞地输入法 App 按指引开启", "Or open the Enclave app for a guide", "Enclave アプリの案内からも設定できます"))
                .font(.system(size: 12))
                .foregroundStyle(Brand.disabledText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            GateButton(title: L("知道了", "Got it", "OK"), primary: true) { model.dismissGate() }
        }
    }

    /// 仅基础功能时点 ✨ /「执行」（CP7）：不发请求，说明去 App 里同意。点卡片或开始打字就收起。
    private var privacy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.returnSoftFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("打开「飞地输入法」App，在「设置 › 隐私」里点「阅读并同意」。拼音输入不受影响。",
                       "Open the Enclave app and tap Read and Agree in Settings › Privacy. Pinyin input still works.",
                       "Enclave アプリの「設定 › プライバシー」で「読んで同意する」をタップしてください。ピンイン入力はそのまま使えます。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.cardBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.dismissGate() }
    }

    /// 还没填 API Key 时点 ✨ /「执行」（OB9）：不发请求，引导去 App 首页跟着教程设置。点卡片或开始打字就收起。
    private var noKey: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0xE9 / 255, blue: 0xA8 / 255))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(
                    colors: [Color(red: 0x8A / 255, green: 0x7B / 255, blue: 1), Brand.purple],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("AI 要先填你自己的 API Key", "Add your own API key to use AI", "AI を使うには自分の API キーが必要です"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("打开「飞地输入法」App，首页点「跟着教程设置」，大约 3 分钟。拼音输入不受影响。",
                       "Open the Enclave app and tap Follow the Guide on Home. About 3 minutes. Pinyin input still works.",
                       "Enclave アプリのホームで「ガイドで設定」をタップ。約 3 分です。ピンイン入力はそのまま使えます。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.cardBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.dismissGate() }
    }

    /// 试用结束后今天的免费次数用完（K2）：打字照常，明天 0 点恢复，或去 App 里买断。
    @ViewBuilder
    private var quotaUsed: some View {
        let uses = AIAccess.dailyFreeUses
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Brand.returnSoftFill))
            Text(L("今天的 \(uses) 次用完了", "You’ve used today’s \(uses) free uses", "今日の無料分（\(uses) 回）を使い切りました"))
                .font(.system(size: 14, weight: .semibold))
        }
        Text(L("试用结束后每天可以免费用 \(uses) 次，明天 0 点恢复。在飞地输入法 App 里一次买断，就不限次数。打字、拼音、常用词一直免费。",
               "After the trial you get \(uses) free uses a day, reset at midnight. Unlock once in the Enclave app for unlimited use. Typing, pinyin and My Words are always free.",
               "無料体験のあとも 1 日 \(uses) 回まで無料で使えます（0 時にリセット）。Enclave アプリで購入すると回数無制限に。入力・ピンイン・ユーザ辞書はずっと無料です。"))
            .font(.system(size: 13))
            .foregroundStyle(Brand.cardBody)
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 3) {
            Text(L("在 App 里解锁", "Unlock in the app", "アプリで購入")).font(.system(size: 11.5)).foregroundStyle(Brand.disabledText)
            (Text(L("打开飞地输入法", "Open Enclave", "Enclave を開く")).foregroundColor(Brand.cardBody)
                + Text(" › ").foregroundColor(Brand.pathSeparator)
                + Text(L("设置", "Settings", "設定")).foregroundColor(Brand.cardBody)
                + Text(" › ").foregroundColor(Brand.pathSeparator)
                + Text("AI").fontWeight(.semibold).foregroundColor(Brand.deepPurple))
                .font(.system(size: 13))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.tagFill))
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Text(L("买过了？在 App 里点「恢复购买」", "Already bought? Tap Restore Purchases in the app", "購入済みの場合はアプリで「購入を復元」"))
                .font(.system(size: 12))
                .foregroundStyle(Brand.disabledText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            GateButton(title: L("知道了", "Got it", "OK"), primary: true) { model.dismissGate() }
        }
    }

    /// 设置 › 通用 › 键盘 › 键盘 › Enclave › 允许完全访问：分隔符浅灰，最后一项深紫加粗。
    private var settingsPath: Text {
        let steps = [L("设置", "Settings", "設定"), L("通用", "General", "一般"), L("键盘", "Keyboard", "キーボード"), L("键盘", "Keyboards", "キーボード"), "Enclave"]
        var text = Text("")
        for step in steps {
            text = text + Text(step).foregroundColor(Brand.cardBody) + Text(" > ").foregroundColor(Brand.pathSeparator)
        }
        return text + Text(L("允许完全访问", "Allow Full Access", "フルアクセスを許可")).fontWeight(.semibold).foregroundColor(Brand.deepPurple)
    }

    @ViewBuilder
    private func consent(_ endpoint: String, previous: String?) -> some View {
        HStack(spacing: 6) {
            SparkleMark(size: 14, color: Brand.tagSelectedText)
            Text(previous == nil ? L("润色前确认一下", "Before you polish", "整える前に確認") : L("接口地址变了，再确认一次", "The API URL changed. Please confirm again", "API の URL が変わりました。もう一度確認してください")).font(.system(size: 14, weight: .semibold))
        }
        HStack(spacing: 6) {
            Text(L("文字会发送到", "Text will be sent to", "文章の送信先")).font(.system(size: 13)).foregroundStyle(Brand.cardBody)
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
                Text(endpoint).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).lineLimit(1)
            }
            .foregroundStyle(Brand.deepPurple)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(Brand.returnSoftFill))
        }
        if let previous {
            (Text(L("原来是 ", "Was ", "以前は ")) + Text(previous).strikethrough())
                .font(.system(size: 12))
                .foregroundStyle(Brand.panelLabel.opacity(0.7))
        }
        Text(L("只在你点「✨」或「执行」时发送：输入框里的文字（选中时只发选中的部分）和你写的要求。由这个接口处理后返回结果；飞地输入法没有自己的服务器，也不保存你的文字。", "Sent only when you tap ✨ or Run: the text in the field (just the selection, if any) and your prompt. This API processes it and returns the result. Enclave has no servers and doesn't keep your text.", "「✨」か「実行」をタップしたときだけ、入力欄の文章（選択時はその部分だけ）と指示を送ります。この API が処理して結果を返します。Enclave はサーバーを持たず、文章を保存しません。"))
            .font(.system(size: 12))
            .foregroundStyle(Brand.cardNote)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Button { model.openContainingApp("enclave://privacy-policy") } label: {
                Text(L("隐私政策", "Privacy Policy", "プライバシーポリシー")).font(.system(size: 12)).foregroundStyle(Brand.tagSelectedText)
            }
            .buttonStyle(.plain)
            Spacer()
            GateButton(title: L("取消", "Cancel", "キャンセル"), primary: false) { model.dismissGate() }
            GateButton(title: L("同意并润色", "Agree and Polish", "同意して整える"), primary: true) { model.acceptConsent() }
        }
    }
}

/// 试用最后 3 天 AI 栏上方的白条（K3）：一句提示 + ✕，每天最多出现一次。
struct TrialReminderStrip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.cardBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button { model.dismissTrialReminder() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.disabledText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("关闭", "Close", "閉じる"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.panelFill))
    }

    private var text: String {
        let days: Int
        if case .trial(let left, _) = AIAccess.current { days = left } else { days = 0 }
        let uses = AIAccess.dailyFreeUses
        return L("AI 试用还剩 \(days) 天，之后每天免费 \(uses) 次", "\(days) days left in your trial, then \(uses) free uses a day",
                 "無料体験は残り \(days) 日。その後は 1 日 \(uses) 回まで無料")
    }
}

/// 提示卡右下的按钮：高 30、圆角 15，主按钮用润色的蓝紫渐变。
struct GateButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Brand.cardBody)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    if primary {
                        Capsule().fill(LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]],
                                                      startPoint: .leading, endPoint: .trailing))
                    } else {
                        Capsule().fill(Brand.tagFill)
                    }
                }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 结果卡片里点到第几个字，以及修改时的光标图形。和卡片文字一样用 15pt 系统字体排版。
enum CardTextHit {
    /// 2pt 宽的光标，模板图，颜色跟着文字前景色。
    static let caret: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 18)).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 18))
    }.withRenderingMode(.alwaysTemplate)

    static func index(at point: CGPoint, in text: String, width: CGFloat) -> Int {
        guard !text.isEmpty, width > 0 else { return 0 }
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15)])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        if point.y > layout.usedRect(for: container).maxY { return text.count }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        var utf16 = layout.characterIndexForGlyph(at: glyph)
        if fraction > 0.5 { utf16 += 1 }
        // UTF-16 位置换成第几个字（表情等占两个单位）。
        var count = 0
        var offset = 0
        for character in text {
            if offset >= utf16 { break }
            offset += character.utf16.count
            count += 1
        }
        return count
    }
}

/// 浮层的形状：圆角矩形，底边一个小尖角。
struct MenuBubble: Shape {
    static let arrowHeight: CGFloat = 6
    var arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.arrowHeight)
        var path = Path(roundedRect: body, cornerRadius: 12, style: .continuous)
        let x = min(max(arrowX, 20), rect.width - 20)
        path.move(to: CGPoint(x: x - 7, y: body.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + 7, y: body.maxY))
        path.closeSubpath()
        return path
    }
}

/// 浮层里的风格：没选中浅灰底黑字，选中浅紫底深紫字、细描边。
struct MenuStyleTag: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .foregroundStyle(selected ? Brand.tagSelectedLabel : Brand.tagLabel)
                .background {
                    if selected {
                        Capsule().fill(Brand.tagSelectedFill)
                        Capsule().strokeBorder(Brand.tagSelectedStroke, lineWidth: 1)
                    } else {
                        Capsule().fill(Brand.tagFill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 要求框：没激活时灰底，激活时白底加紫色内描边。键盘打的字进这里，回车就执行。
/// 描边一直都画着（没激活时和底色相同），激活前后框的大小和文字位置不动。
struct RequestField: View {
    @ObservedObject var model: KeyboardModel
    /// 最后一次打字的时间：打字时光标常亮，停下 0.5 秒后才开始闪。
    @State private var lastTyped = Date()
    /// 文字区在框里的位置，点按和长按拖动时换算成第几行、第几个字。
    @State private var textFrame = CGRect.zero
    /// 这次按下的时间；按住超过 0.3 秒就进入拖动光标，否则松手算点一下。
    @State private var pressStart: Date?

    private static let font = UIFont.systemFont(ofSize: 14)
    private static let lineHeight = KeyboardMetrics.requestLineHeight

    static let caret: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 17)).image { _ in
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 2, height: 17), cornerRadius: 1).fill()
    }.withRenderingMode(.alwaysTemplate)

    private var placeholder: String {
        L("写任何要求：翻成日语、改成朋友圈语气…", "Ask for anything: translate, make it casual…", "何でも指示できます：英語に、やわらかく…")
    }

    var body: some View {
        let editing = model.target == .instruction
        let text = model.instruction
        let layout = self.layout
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "pencil").font(.system(size: 13, weight: .medium))
                .foregroundStyle(editing || !text.isEmpty ? Brand.purpleText : Brand.fieldPlaceholder)
                .frame(height: Self.lineHeight)
            Group {
                if editing {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        lines(layout, caretOpacity: caretOpacity(at: context.date))
                    }
                } else {
                    lines(layout, caretOpacity: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { textFrame = geometry.frame(in: .named("requestField")) }
                    .onChange(of: geometry.frame(in: .named("requestField"))) { textFrame = $0 }
            })
            .overlay(alignment: .trailing) {
                if layout.scrolls { scrollBar(layout) }
            }
            if !text.isEmpty {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Brand.fieldClear))
                    // 贴在框的右上；点击区放大到 44pt 宽。
                    .frame(width: 44, height: Self.lineHeight, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { model.setInstruction("") }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, (KeyboardMetrics.requestFieldHeight(lines: layout.shown) - Self.lineHeight * CGFloat(layout.shown)) / 2)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardMetrics.requestFieldHeight(lines: layout.shown))
        .background {
            shape.fill(editing ? Brand.fieldActiveFill : Brand.tagFill)
            shape.strokeBorder(editing ? Brand.fieldActiveLine : Brand.tagFill, lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.15), value: editing)
        .contentShape(Rectangle())
        .coordinateSpace(name: "requestField")
        .gesture(press)
        .onAppear { model.requestLines = layout.shown }
        .onChange(of: layout.shown) { model.requestLines = $0 }
        .onChange(of: model.instruction) { _ in lastTyped = Date() }
        .onChange(of: model.composition) { _ in lastTyped = Date() }
        .onChange(of: editing) { _ in lastTyped = Date() }
    }

    // MARK: 折行

    /// 框里要显示的东西：文字（拼音插在光标处）按宽度折好的行，光标在第几个字、第几行，从第几行开始显示。
    struct Layout {
        var chars: [Character]
        var lines: [Range<Int>]
        /// 拼音在 chars 里的范围，光标在它后面。
        var composing: Range<Int>
        var caret: Int
        var caretLine: Int
        /// 最多显示几行：编辑时 3 行，不编辑时 2 行。
        var limit: Int
        var first: Int
        var shown: Int { max(1, min(lines.count, limit)) }
        /// 编辑时超过 3 行：框里上下滚，右边画细滚动条。
        var scrolls: Bool { limit == 3 && lines.count > 3 }
        /// 不编辑、超过 2 行：第 2 行后面接上剩下的字，由 Text 在尾部加省略号。
        var truncates: Bool { limit == 2 && lines.count > 2 }
    }

    private var layout: Layout {
        let editing = model.target == .instruction
        let text = Array(model.instruction)
        let composing = editing ? Array(model.composition) : []
        let caret = min(model.instructionCaret, text.count)
        let chars = Array(text[..<caret]) + composing + Array(text[caret...])
        let caretIndex = caret + composing.count
        let lines = Self.wrap(chars, width: textFrame.width - 4)
        let caretLine = lines.lastIndex { $0.lowerBound <= caretIndex } ?? 0
        let limit = editing ? 3 : 2
        // 光标那一行尽量放在中间，总之始终露出来。
        let first = editing && lines.count > limit ? min(max(caretLine - 1, 0), lines.count - limit) : 0
        return Layout(chars: chars, lines: lines, composing: caret..<(caret + composing.count),
                      caret: caretIndex, caretLine: caretLine, limit: limit, first: first)
    }

    /// 贪心折行；英文尽量在空格后断开。宽度还不知道时整段算一行。
    /// 每加一个字量一次整行的宽度（逐字相加会比实际排版窄，中文标点尤其明显，行尾就被截成「…」）。
    static func wrap(_ chars: [Character], width: CGFloat) -> [Range<Int>] {
        guard width > 20, !chars.isEmpty else { return [0..<chars.count] }
        var lines: [Range<Int>] = []
        var start = 0, lastSpace: Int?
        var index = 0
        while index < chars.count {
            // 光标图片 2pt 加一点余量。
            if index > start, Self.width(String(chars[start...index])) + 4 > width {
                var breakAt = index
                if let space = lastSpace, space > start, chars[index] != " " { breakAt = space + 1 }
                lines.append(start..<breakAt)
                start = breakAt
                lastSpace = nil
                continue
            }
            if chars[index] == " " { lastSpace = index }
            index += 1
        }
        lines.append(start..<chars.count)
        return lines
    }

    /// 显示的几行。没写字时是占位字，光标叠在它左边。
    @ViewBuilder
    private func lines(_ layout: Layout, caretOpacity: Double?) -> some View {
        if layout.chars.isEmpty {
            Text(placeholder).foregroundColor(Brand.fieldPlaceholder)
                .lineLimit(1)
                .frame(height: Self.lineHeight)
                .overlay(alignment: .leading) {
                    if let caretOpacity {
                        Image(uiImage: Self.caret).foregroundStyle(Brand.fieldActiveLine.opacity(caretOpacity))
                            .offset(x: -2)
                    }
                }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(layout.first..<(layout.first + layout.shown), id: \.self) { line in
                    let last = line == layout.first + layout.shown - 1
                    let range = last && layout.truncates ? layout.lines[line].lowerBound..<layout.chars.count : layout.lines[line]
                    if last && layout.truncates {
                        lineText(range, line: line, layout: layout, caretOpacity: caretOpacity)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: Self.lineHeight)
                    } else {
                        // 折行已经按宽度算好，这里不许再截断：宽一点点也整行画出来。
                        lineText(range, line: line, layout: layout, caretOpacity: caretOpacity)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(height: Self.lineHeight)
                    }
                }
            }
        }
    }

    /// 一行：拼音带下划线，光标插在这一行里。
    private func lineText(_ range: Range<Int>, line: Int, layout: Layout, caretOpacity: Double?) -> Text {
        var result = Text("")
        var run = ""
        var runComposing = false
        func flush() {
            guard !run.isEmpty else { return }
            result = result + (runComposing
                ? Text(run).foregroundColor(Brand.fieldText).underline(color: Brand.fieldActiveLine)
                : Text(run).foregroundColor(Brand.fieldText))
            run = ""
        }
        let caretHere = caretOpacity != nil && line == layout.caretLine
        for index in range {
            if caretHere && index == layout.caret {
                flush()
                result = result + caretText(caretOpacity ?? 1)
            }
            let composing = layout.composing.contains(index)
            if composing != runComposing { flush(); runComposing = composing }
            run.append(layout.chars[index])
        }
        flush()
        if caretHere && layout.caret == range.upperBound { result = result + caretText(caretOpacity ?? 1) }
        return result
    }

    private func caretText(_ opacity: Double) -> Text {
        Text(Image(uiImage: Self.caret)).foregroundColor(Brand.fieldActiveLine.opacity(opacity)).baselineOffset(-3)
    }

    /// 右边 3pt 的细滚动条：底 #F2F2F7，滑块 #C7C7CC，按显示的是第几行到第几行画。
    private func scrollBar(_ layout: Layout) -> some View {
        GeometryReader { geometry in
            let total = CGFloat(layout.lines.count)
            let height = geometry.size.height
            ZStack(alignment: .top) {
                Capsule().fill(Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255))
                Capsule().fill(Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255))
                    .frame(height: height * CGFloat(layout.shown) / total)
                    .offset(y: height * CGFloat(layout.first) / total)
            }
        }
        .frame(width: 3)
        .offset(x: 4)
    }

    // MARK: 点按

    /// 点一下：激活且有字时把光标放到点的位置，其他时候切换激活。
    /// 按住 0.3 秒后拖动：光标跟着手指走（没激活时先激活）。用一个手势自己计时，点按和长按不会互相吃掉。
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("requestField"))
            .onChanged { value in
                let start = pressStart ?? Date()
                if pressStart == nil { pressStart = start }
                guard Date().timeIntervalSince(start) > 0.3 else { return }
                if model.target != .instruction { model.toggleInstructionEditing() }
                if !model.isComposing { placeCaret(at: value.location) }
            }
            .onEnded { value in
                let held = Date().timeIntervalSince(pressStart ?? Date()) > 0.3
                pressStart = nil
                if model.target == .instruction, !model.instruction.isEmpty, !model.isComposing {
                    placeCaret(at: value.location)
                } else if !(held && model.target == .instruction) {
                    // 长按已经激活了就不再切回去。
                    model.toggleInstructionEditing()
                }
            }
    }

    /// 点到的位置换算成第几行、第几个字：落在哪个字的左半边光标就放在它前面，右半边放在后面。
    private func placeCaret(at point: CGPoint) {
        let layout = self.layout
        guard !layout.lines.isEmpty else { return }
        let row = min(max(Int((point.y - textFrame.minY) / Self.lineHeight), 0), layout.shown - 1)
        let range = layout.lines[layout.first + row]
        let local = point.x - textFrame.minX
        var offset: CGFloat = 0
        var position = range.lowerBound
        for index in range {
            let width = Self.width(String(layout.chars[index]))
            if local < offset + width / 2 { break }
            offset += width
            position += 1
        }
        // 折行处的空格之后再往右点，光标停在这一行的末尾（下一行开头之前）。
        if position == range.upperBound, range.upperBound < layout.chars.count, layout.chars[range.upperBound - 1] == " " {
            position -= 1
        }
        model.moveInstructionCaret(by: position - model.instructionCaret)
        lastTyped = Date()
    }

    private static func width(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// 打字或拼音时常亮；停下 0.5 秒后亮 0.5 秒、灭 0.5 秒，亮灭之间约 80ms 渐变。
    private func caretOpacity(at date: Date) -> Double {
        if model.isComposing { return 1 }
        let idle = date.timeIntervalSince(lastTyped) - 0.5
        guard idle > 0 else { return 1 }
        let phase = idle.truncatingRemainder(dividingBy: 1)
        let fade = 0.08
        switch phase {
        case ..<0.5: return 1
        case ..<(0.5 + fade): return 1 - (phase - 0.5) / fade
        case ..<(1 - fade): return 0
        default: return (phase - (1 - fade)) / fade
        }
    }
}

// MARK: - 结果卡片

/// 结果卡片：提示、出错、首次使用清单也都显示在这个位置。
/// 有结果时右边一列是 ✦ 状态、复制、展开，多个版本时再加一列 ▲ 2/3 ▼。
struct ResultCard: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 文字区宽度，点文字时换算成第几个字。
    @State private var textWidth: CGFloat = 200

    private enum Look { case checklist, error(String), hint(String?), running, fresh, faded, editing }

    private var look: Look {
        if model.aiBlocked { return .checklist }
        if model.target == .card { return .editing }
        if let error = model.errorMessage { return .error(error) }
        if model.isRunning { return .running }
        if model.session?.current != nil {
            return model.resultUse != nil || model.resultStale ? .faded : .fresh
        }
        return .hint(model.notice)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    /// 只在生成中播放；App 里关了动画或系统开了「减弱动态效果」就不播。
    private var animating: Bool { model.isRunning && model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        let look = look
        Group {
            switch look {
            case .checklist: checklist
            case .error(let message): errorView(message)
            case .hint(let notice): hintView(notice)
            case .running, .fresh, .faded: resultView(faded: { if case .faded = look { return true } else { return false } }())
            case .editing: editView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // 修改中：外面一圈 4pt 淡紫光。
            if case .editing = look { shape.inset(by: -4).fill(Brand.tagSelectedText.opacity(0.14)) }
            shape.fill(KeyStyle.charKey)
            if case .error = look { shape.fill(Color.red.opacity(0.07)) }
        }
        .overlay {
            if animating { SweepBand().clipShape(shape) }
        }
        .overlay { border(look) }
        .overlay {
            if model.copied {
                Label(L("已复制", "Copied", "コピーしました"), systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Brand.purple))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 结果

    private func resultView(faded: Bool) -> some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
            // 左上角「AI 生成」（CP8），只在界面上标，不往正文里插任何标记。
            AIGeneratedTag()
                .padding(.leading, 10)
                .padding(.top, 8)
            resultText(faded: faded)
                .padding(.leading, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                // 不展开时上下滑翻版本（展开时文字区要留给滚动）；长按复制。
                // 滑动放在主手势、长按放在同时识别，onLongPressGesture 会把拖动吞掉。
                .gesture(swipeToTurn, including: model.cardTall ? .subviews : .all)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in model.copy() })
                // 点文字进入修改，光标放在点的位置。
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    guard model.hasResult, let text = model.session?.current else { return }
                    // 减掉文字区的内边距；展开卡片滚动过时按未滚动估算，进入后可以再点一次调整。
                    let point = CGPoint(x: value.location.x - 10, y: value.location.y - 4)
                    model.beginCardEdit(caret: CardTextHit.index(at: point, in: text, width: textWidth))
                })
            }
            iconColumn(faded: faded)
                .padding(.vertical, 5)
            if let session = model.session, session.versions.count > 1, !model.isRunning {
                pager(index: session.currentIndex, count: session.versions.count)
                    .coachTarget(.versions, active: model.coachDisplay?.target == .versions)
                    .contentShape(Rectangle())
                    // 优先于 ▲▼ 按钮：手指在按钮里滑一下松开，按钮也会算一次点击，就翻了两页。
                    .highPriorityGesture(swipeToTurn)
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func resultText(faded: Bool) -> some View {
        let text = Text(model.displayText) + Text(model.isRunning ? "▍" : "").foregroundColor(Brand.purpleText)
        Group {
            if model.cardTall {
                ScrollView {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                }
                .hidingScrollEdgeEffect()
            } else {
                // 生成中只放得下两行时显示最新的部分。
                text.lineLimit(2).truncationMode(model.isRunning ? .head : .tail)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(faded ? Color.secondary : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { textWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { textWidth = $0 }
        })
    }

    // MARK: 修改中

    /// 卡片里的文字可以直接改：光标前、正在拼的拼音（紫色下划线）、闪烁的光标、光标后。
    private var editView: some View {
        HStack(alignment: .top, spacing: 2) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        editText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GeometryReader { proxy in
                                Color.clear.onAppear { textWidth = proxy.size.width }
                            })
                            .contentShape(Rectangle())
                            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                                model.beginCardEdit(caret: CardTextHit.index(at: value.location, in: model.cardDraft,
                                                                             width: textWidth))
                            })
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .hidingScrollEdgeEffect()
                .onChange(of: model.cardDraft) { _ in
                    // 在末尾打字时跟着滚到最下面。
                    if model.cardCaret >= model.cardDraft.count - 1 { reader.scrollTo("end", anchor: .bottom) }
                }
                .onAppear {
                    if model.cardCaret >= model.cardDraft.count { reader.scrollTo("end", anchor: .bottom) }
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)
            iconColumn(faded: false)
                .padding(.vertical, 5)
            // 和显示时一样留出翻页那一列，换行位置不变，点哪儿光标就落在哪儿。
            if let session = model.session, session.versions.count > 1 {
                Color.clear.frame(width: 28)
            }
        }
        .padding(.trailing, 4)
    }

    private var editText: some View {
        let draft = model.cardDraft
        let split = draft.index(draft.startIndex, offsetBy: min(model.cardCaret, draft.count))
        return TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 || model.isComposing
            (Text(draft[..<split])
                + Text(model.composition).underline(color: Brand.tagSelectedText)
                + Text(Image(uiImage: CardTextHit.caret)).foregroundColor(visible ? Brand.tagSelectedText : .clear)
                    .baselineOffset(-3)
                + Text(draft[split...]))
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
        }
    }

    /// ✦ 状态、复制、展开：15pt 线性图标，24×18 点击区，上中下对齐。
    private func iconColumn(faded: Bool) -> some View {
        VStack(spacing: 0) {
            if model.isRunning {
                SparkleMark(size: 15, color: Brand.purpleText, animating: animating)
                    .frame(width: 24, height: 18)
                    .background(Capsule().fill(Brand.softFill))
            } else {
                // 修改结果：平时紫色，显示的是改过的一版时变灰（还能再点进去改），修改中带浅紫底。
                let editing = model.target == .card
                let tint = editing || !(model.session?.currentIsEdited ?? false) ? Brand.tagSelectedText : Brand.pathSeparator
                iconButton("pencil", tint: faded && !editing ? .secondary : tint) {
                    editing ? model.finishCardEdit() : model.beginCardEdit()
                }
                .background(Capsule().fill(editing ? Brand.softFill : Color.clear))
                .disabled(!model.hasResult)
            }
            Spacer(minLength: 0)
            iconButton(model.copied ? "doc.on.doc.fill" : "doc.on.doc", tint: model.copied ? Brand.purpleText : .secondary) {
                model.copy()
            }
            .disabled(!model.hasResult)
            Spacer(minLength: 0)
            iconButton(model.cardExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       tint: .secondary) {
                withAnimation(.easeOut(duration: 0.2)) { model.cardExpanded.toggle() }
            }
        }
        .frame(width: 24)
    }

    private func iconButton(_ systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 多个版本：▲ 2/3 ▼。
    private func pager(index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            Button { turn(-1) } label: {
                Image(systemName: "chevron.up").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(index == 0)
            Text("\(index + 1)/\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.primary)
            if model.session?.currentIsEdited == true {
                Text(L("已改", "Edited", "編集済み")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Brand.deepPurple)
            }
            Button { turn(1) } label: {
                Image(systemName: "chevron.down").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(index >= count - 1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .buttonStyle(.plain)
        .frame(width: 28)
        .padding(.vertical, 2)
    }

    /// 上滑看下一版，下滑看上一版。
    private var swipeToTurn: some Gesture {
        DragGesture(minimumDistance: 12).onEnded { value in
            // 快速轻扫移动距离短，用预测的终点算。
            let dy = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                ? value.predictedEndTranslation.height : value.translation.height
            guard abs(dy) > abs(value.translation.width) else { return }
            if dy < -20 { turn(1) } else if dy > 20 { turn(-1) }
        }
    }

    private func turn(_ offset: Int) {
        model.keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.2)) { model.showVersion(offset: offset) }
    }

    // MARK: 边框

    @ViewBuilder
    private func border(_ look: Look) -> some View {
        switch look {
        case .running:
            if animating {
                FlowingBorder(shape: shape)
            } else {
                shape.strokeBorder(Brand.purpleText.opacity(0.5), lineWidth: 1)
            }
        case .fresh:
            shape.strokeBorder(LinearGradient(colors: Brand.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: 1.2)
        case .faded:
            shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.8)
        case .error:
            shape.strokeBorder(Color.red.opacity(0.35), lineWidth: 0.8)
        case .editing:
            shape.strokeBorder(Brand.tagSelectedText, lineWidth: 2)
        case .checklist, .hint:
            EmptyView()
        }
    }

    // MARK: 提示、出错、检查清单

    /// 提示卡里提到的选择器名字：当前提示词，默认是「润色」。
    private var chipName: String { model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える") }

    private func hintView(_ notice: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notice {
                Text(notice).font(.system(size: 13)).foregroundStyle(Color.primary)
            } else {
                HStack(spacing: 4) {
                    SparkleMark(size: 11, color: Brand.purpleText)
                    Text(L("点 ✨，按当前提示词改输入框里的话", "Tap ✨ to run the current prompt on your text", "✨ で、いまのプロンプトを入力欄の文章に使います")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.purpleText)
                }
                Text(L("点「\(chipName)▾」换一条提示词，或者直接写任何要求：翻成日语、改成朋友圈语气……", "Tap \(chipName) ▾ to switch prompts, or ask for anything: translate it, make it casual…", "「\(chipName) ▾」でプロンプトを切り替えるか、何でも指示できます：英語に、やわらかく……"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(L("出错了", "Something went wrong", "エラーが発生しました"), systemImage: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// 首次使用：没开完全访问或没配置 API 时，卡片位置列出还差的几步，✨ 置灰，打字不受影响。
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                SparkleMark(size: 12, color: Brand.purpleText)
                Text(L("还差几步就能用 AI，打字不受影响", "A few steps to use AI. Typing works now", "あと数ステップで AI が使えます。入力はすぐに使えます")).font(.system(size: 13, weight: .semibold))
            }
            checkRow(1, L("打开「允许完全访问」", "Turn on Allow Full Access", "「フルアクセスを許可」をオン"), done: model.hasFullAccess)
            HStack {
                checkRow(2, L("配置模型 API", "Set up a model API", "モデル API を設定"), done: model.settings.isConfigured)
                Spacer(minLength: 0)
                if !model.settings.isConfigured && SharedStorage.usesClipboardConfig {
                    Button { model.importConfigFromPasteboard() } label: {
                        Text(L("从剪贴板导入", "Import from clipboard", "クリップボードから読み込む"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.purpleText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(Brand.softFill))
                    }
                    .buttonStyle(KeyPressStyle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func checkRow(_ number: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green)
            } else {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Brand.purple))
            }
            Text(title).font(.system(size: 13)).foregroundStyle(done ? Color.secondary : Color.primary)
        }
    }
}

// MARK: - 润色动画（方案 A）

/// 生成中的边框：品牌渐变沿边框转一圈，周期 1.6 秒；外圈淡紫光晕轻微明暗。
struct FlowingBorder: View {
    var shape: RoundedRectangle
    var lineWidth: CGFloat = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let wave = (1 - cos(2 * .pi * phase)) / 2
            ZStack {
                shape.stroke(Brand.violet.opacity(0.18 + 0.14 * wave), lineWidth: 4).blur(radius: 3)
                shape.strokeBorder(AngularGradient(colors: Brand.gradient + [Brand.gradient[0]], center: .center,
                                                   angle: .degrees(phase * 360)),
                                   lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 快速模式出错：AI 栏风格按钮右边「润色失败，点重试」。
struct QuickRetryLabel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button { model.sparkleTapped() } label: {
            ViewThatFits(in: .horizontal) {
                Text(L("润色失败，点重试", "Polish failed. Tap to retry", "失敗しました。タップで再試行"))
                Text(L("失败，重试", "Failed, retry", "失敗・再試行"))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.deepPurple)
            .lineLimit(1)
        }
        .buttonStyle(KeyPressStyle())
        .padding(.leading, 2)
    }
}

/// 卡片里的扫光：约 300pt 宽的斜向光带从左往右匀速扫过，中间最深（#7C3AED 16%），一趟 1.6 秒，和边框同步。
struct SweepBand: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let band: CGFloat = 300
                LinearGradient(colors: [Brand.violet.opacity(0), Brand.violet.opacity(0.16), Brand.violet.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band, height: geo.size.height * 2)
                    .rotationEffect(.degrees(18))
                    .offset(x: -band + (geo.size.width + band) * phase, y: -geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// iOS 26 会在滚动区顶部加一层渐变模糊，盖住预览区的第一行，这里关掉它。
    @ViewBuilder
    func hidingScrollEdgeEffect() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }
}


/// 结果卡片左上角的「AI 生成」标签（CP8）：高 18、圆角 5，灰底灰字，前面一颗四角星。
struct AIGeneratedTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .semibold))
            Text(L("AI 生成", "AI-generated", "AI 生成")).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Brand.aiTagText)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.aiTagFill))
        .accessibilityElement(children: .combine)
    }
}

/// 快速模式替换后 AI 栏上的浅紫胶囊（CP9）：高 28、圆角 14，紫色四角星 +「AI 生成 · 已替换」。
struct ReplacedPill: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold))
                Text(L("AI 生成 · 已替换", "AI-generated · Replaced", "AI 生成・置き換え済み"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Brand.replacedPillText)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(Brand.replacedPillFill))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("展开看结果", "Shows the result", "結果を表示"))
    }
}
