import SwiftUI

/// 键盘主体。
/// AI 栏永远紧贴按键上方，收起和展开是同一条：[抽屉] [✨] [润色 ▴] [识意 ▾] … [撤销|重做]；打拼音时这一行换成候选。
/// 展开抽屉时 AI 栏上面是结果卡片和动作行（替换、插入）；「润色 ▴」「识意 ▾」各自往上展开一行，紧贴 AI 栏。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    private var inset: CGFloat { KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX }

    var body: some View {
        VStack(spacing: 0) {
            if let gate = model.gate {
                // 提示卡单独占上方，结果卡片和展开的一行先让开。
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
            if model.gate == nil, let row = model.aiRow {
                // 尖角对准下面那颗按钮右侧的箭头：中心距按钮右边 15.5pt。
                AIRowPanel(model: model, row: row, arrowX: (chipEdges[row] ?? 0) - inset - 15.5)
                    .frame(height: KeyboardMetrics.aiRowHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, model.aiExpanded ? KeyboardMetrics.panelSpacing : KeyboardMetrics.panelTop)
                    .padding(.bottom, KeyboardMetrics.aiRowGap)
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
            // 按住 ✨ 弹出的「问答」盖在按键上面。
            .zIndex(1)
            KeysView(model: model)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
                .layoutPriority(1)
        }
        // 系统给的高度不够时从顶上裁，按键始终完整贴在底部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 使用指引「一键应用」后的小手指，画在键盘里面。
        .coachHandOverlay(model)
        .coordinateSpace(name: "keyboard")
        .onPreferenceChange(RowChipEdgeKey.self) { edges in
            // 打拼音时 AI 栏换成候选栏、按钮不在了，沿用上次的位置。
            if !edges.isEmpty, edges != chipEdges { chipEdges = edges }
        }
        .clipped()
    }

    /// 「润色 ▴」「识意 ▾」右边缘在键盘里的位置，展开那一行的尖角按它对齐。
    @State private var chipEdges: [KeyboardModel.AIRow: CGFloat] = [:]

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
            // 快速模式替换成功后 3 秒，两颗功能按钮的位置换成「AI 生成 · 已替换」（CP9），点它展开看结果。
            if model.quickStatus == .done, !model.aiExpanded, model.aiRow == nil {
                ReplacedPill { model.setAIExpanded(true) }
                    .layoutPriority(1)
                    .transition(.opacity)
            } else {
                // 识意是主要功能，紧挨 ✨；提示词选好后一般不常换，放后面。
                RowChip(model: model, row: .ask).layoutPriority(1)
                RowChip(model: model, row: .prompts)
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
/// 识意展开时（QA4、QA11）：按识意框里的话执行。自动是紫粉渐变只有星星，手动选的改写 / 问答带字；
/// 按住会在正上方弹出「改写」、正下方弹出「问答」，滑到哪个松手就按哪种，不滑松手是自动。框里没字时半透明、点了没反应。
struct PolishButton: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var doneAt: Date?
    /// 识意展开时按住 ✨：弹出两个选项，手指现在指着哪个。
    @State private var holding = false
    @State private var pick: KeyboardModel.AskMode?
    @State private var pressed = false
    @State private var holdTimer: DispatchWorkItem?

    /// 这次是点 ✨ 开始的：收起和展开都在按钮上放特效。
    private var quickRunning: Bool { model.isRunning && model.runOrigin != nil }
    /// 关了发光动画或开了减弱动态效果：只留星星轻微闪动。
    private var fullMotion: Bool { model.settings.polishAnimation && !reduceMotion }
    private var asking: Bool { model.aiRow == .ask }

    var body: some View {
        if asking {
            askButton
        } else {
            Button {
                model.isRunning ? model.stop() : model.sparkleTapped()
            } label: {
                decorated(face(fill: polishFill, ring: Brand.gradient) {
                    PolishStars(size: 20, running: false, glowing: fullMotion, doneAt: fullMotion ? doneAt : nil)
                })
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel(model.isRunning ? L("正在生成，轻点取消", "Working. Tap to cancel", "生成中。タップでキャンセル") : L("执行当前提示词", "Run prompt", "プロンプトを実行"))
            .coachTarget(.sparkle, active: model.coachDisplay?.target == .sparkle)
            .onChange(of: model.finished) { finished in flashDone(at: finished?.at) }
        }
    }

    // MARK: 识意展开时

    private var askButton: some View {
        let mode = model.askButtonMode
        let enabled = model.canAsk || model.isRunning
        let showsHold = holding || debugHold
        return decorated(face(fill: AnyShapeStyle(Self.askGradient(mode)), ring: (model.askKind ?? mode) == .answer ? Brand.answerRing : PolishButtonGlow.rerunRing) {
            Self.askLabel(mode, starSize: mode == nil ? 20 : 11, doneAt: fullMotion ? doneAt : nil, glowing: fullMotion)
        })
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(pressed && !showsHold ? 0.96 : 1)
        .overlay {
            if showsHold {
                ZStack {
                    AskOption(mode: .rewrite, highlighted: pick == .rewrite).offset(y: -40)
                    AskOption(mode: .answer, highlighted: pick == .answer).offset(y: 40)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let canHold = model.canAsk && !model.isRunning
                if !pressed {
                    pressed = true
                    guard canHold else { return }
                    // 按住不动 0.3 秒也弹出两个选项。
                    let timer = DispatchWorkItem { showHold() }
                    holdTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: timer)
                }
                let dy = value.translation.height
                // 和九宫格按住划（KeyTouchView.flickDistance）一样：手指离开按下点超过 16pt 立刻弹出并选中那一个，不用先等。
                if !holding, canHold, hypot(value.translation.width, dy) > Self.flickDistance {
                    holdTimer?.cancel()
                    holdTimer = nil
                    showHold()
                }
                guard holding else { return }
                let next: KeyboardModel.AskMode? = dy < -Self.flickDistance ? .rewrite : (dy > Self.flickDistance ? .answer : nil)
                if next != pick {
                    pick = next
                    if next != nil { model.keyFeedback(for: .space) }
                }
            }
            .onEnded { _ in
                holdTimer?.cancel()
                holdTimer = nil
                let wasHolding = holding
                let choice = pick
                pressed = false
                pick = nil
                withAnimation(.easeOut(duration: 0.15)) { holding = false }
                if model.isRunning {
                    model.stop()
                } else if model.canAsk {
                    // 按住不滑松手是自动；点一下按 ✨ 现在显示的方式（上次手动选的，字没改的话）。
                    model.askTapped(wasHolding ? choice : model.askButtonMode)
                }
            })
        .accessibilityElement()
        .accessibilityLabel(model.isRunning ? L("正在生成，轻点取消", "Working. Tap to cancel", "生成中。タップでキャンセル")
                            : L("执行识意，按住上滑改写、下滑问答", "Run Ask. Hold and slide up to edit, down for Q&A", "たずねるを実行。長押しで上にスライドすると修正、下で質問"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.isRunning ? model.stop() : model.askTapped(model.askButtonMode) }
        .accessibilityAction(named: L("改写", "Rewrite", "書き換え")) { model.askTapped(.rewrite) }
        .accessibilityAction(named: L("问答", "Answer", "回答")) { model.askTapped(.answer) }
        .coachTarget(.run, active: model.coachDisplay?.target == .run)
        .onChange(of: model.finished) { finished in flashDone(at: finished?.at) }
    }

    /// 和九宫格按住划出方向的距离一样。
    private static let flickDistance: CGFloat = 16

    private func showHold() {
        guard !holding else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { holding = true }
        model.keyFeedback(for: .space)
    }

    private var debugHold: Bool {
        #if DEBUG
        return model.debugAskHold
        #else
        return false
        #endif
    }

    /// 自动、改写、问答三种底色。
    static func askGradient(_ mode: KeyboardModel.AskMode?) -> LinearGradient {
        let colors: [Color]
        switch mode {
        case nil: colors = Brand.askAutoColors
        case .rewrite: colors = Brand.askRewriteColors
        case .answer: colors = Brand.askAnswerColors
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// 自动只有星星；改写 / 问答是 11pt 星星加 13.5pt 粗体白字。
    @ViewBuilder
    static func askLabel(_ mode: KeyboardModel.AskMode?, starSize: CGFloat, doneAt: Date? = nil, glowing: Bool = false) -> some View {
        if let mode {
            HStack(spacing: 3) {
                PolishStars(size: starSize, running: false, glowing: glowing, doneAt: doneAt)
                Text(mode == .rewrite ? L("改写", "Edit", "修正") : L("问答", "Q&A", "質問"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
        } else {
            // 自动（10-27 定，方案 E3）：识意图标 | 细竖线 | 上下箭头，提示可以上滑改写、下滑问答。
            HStack(spacing: 5) {
                AskIcon().frame(width: 18, height: 18)
                Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: 外观

    /// 58×34 的胶囊：生成中深灰底白色方块，流光描边按这次的颜色。
    private func face<Label: View>(fill: AnyShapeStyle, ring: [Color], @ViewBuilder label: () -> Label) -> some View {
        let shape = Capsule()
        return Group {
            if model.isRunning {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.white).frame(width: 12, height: 12)
            } else {
                label()
            }
        }
        .frame(width: KeyboardMetrics.polishButtonWidth, height: KeyboardMetrics.chipHeight)
        .background(shape.fill(model.isRunning ? AnyShapeStyle(Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)) : fill))
        .overlay {
            if quickRunning && fullMotion {
                PolishButtonGlow(ring: ring).clipShape(shape)
            }
        }
    }

    /// 小锁、剩余次数，点按区上下各扩 5pt。
    private func decorated<Content: View>(_ content: Content) -> some View {
        content
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

    private var polishFill: AnyShapeStyle {
        let gradient = LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]], startPoint: .leading, endPoint: .trailing)
        return (model.aiBlocked || model.aiQuotaUsed) ? AnyShapeStyle(gradient.opacity(0.35)) : AnyShapeStyle(gradient)
    }
}

/// 识意展开、自动时 ✨ 里的图标（方案 E3，design/ask-icon/ask-icon-e3.svg，24×24 画布）：
/// 白色实心镜片的放大镜，镜片里一颗紫粉渐变四角星，右上、左上两颗小黄星。
struct AskIcon: View {
    /// 和 ✨ 同款的四角星，24×24 画布里的路径。
    private static func star(_ path: inout Path, center: CGPoint, scale k: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + (x - 12) * k, y: center.y + (y - 12) * k) }
        path.move(to: p(12, 3))
        path.addCurve(to: p(21, 12), control1: p(12.8, 8.5), control2: p(15.5, 11.2))
        path.addCurve(to: p(12, 21), control1: p(15.5, 12.8), control2: p(12.8, 15.5))
        path.addCurve(to: p(3, 12), control1: p(11.2, 15.5), control2: p(8.5, 12.8))
        path.addCurve(to: p(12, 3), control1: p(8.5, 11.2), control2: p(11.2, 8.5))
        path.closeSubpath()
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            // 镜片：半径 6.8 的白圆加 2pt 白描边。
            context.fill(Path(ellipseIn: CGRect(x: 10 - 7.8, y: 10.6 - 7.8, width: 15.6, height: 15.6)), with: .color(.white))
            var handle = Path()
            handle.move(to: CGPoint(x: 15.41, y: 16.01))
            handle.addLine(to: CGPoint(x: 19.41, y: 20.01))
            context.stroke(handle, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var lens = Path()
            Self.star(&lens, center: CGPoint(x: 10, y: 10.6), scale: 0.44)
            context.fill(lens, with: .linearGradient(Gradient(colors: Brand.askAutoColors),
                                                     startPoint: CGPoint(x: 6, y: 6.6), endPoint: CGPoint(x: 14, y: 14.6)))
            var sparks = Path()
            Self.star(&sparks, center: CGPoint(x: 20, y: 3.4), scale: 0.26)
            Self.star(&sparks, center: CGPoint(x: 2.6, y: 3.2), scale: 0.17)
            context.fill(sparks, with: .color(Brand.gold))
        }
        .accessibilityHidden(true)
    }
}

/// 按住 ✨ 时弹出的「改写」「问答」（QA11）：58×34、各自的渐变、前面同款星星；手指指着的加 2pt 白描边和阴影。
struct AskOption: View {
    var mode: KeyboardModel.AskMode
    var highlighted: Bool

    var body: some View {
        PolishButton.askLabel(mode, starSize: 11)
            .frame(width: KeyboardMetrics.polishButtonWidth, height: KeyboardMetrics.chipHeight)
            .background(Capsule().fill(PolishButton.askGradient(mode)))
            .overlay(Capsule().strokeBorder(Color.white, lineWidth: highlighted ? 2 : 0))
            .shadow(color: .black.opacity(highlighted ? 0.28 : 0.14), radius: highlighted ? 8 : 4, y: 3)
            .scaleEffect(highlighted ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}

/// 生成中按钮里的动画：1.5pt 流光描边（1.6 秒一圈，外面不加光晕）、60pt 白色光带扫过、一圈白色小闪光。
/// 描边按 ✨ 当时的颜色：润色和改写是品牌色，识意自动是粉紫，问答是天蓝。
struct PolishButtonGlow: View {
    typealias Sparkle = (x: CGFloat, y: CGFloat, d: CGFloat, period: Double, offset: Double)

    /// 小闪光的位置（相对 84×34 的按钮，x、y、大小）和周期。
    static let polishSparkles: [Sparkle] = [
        (4, 8, 6, 1.5, 0.0), (9, 22, 5, 1.7, 0.6), (21, 2, 6, 1.9, 1.1), (29, 26, 5, 1.6, 0.3), (39, 1, 5, 1.8, 0.9),
        (52, 27, 6, 1.5, 1.3), (60, 1, 5, 1.7, 0.2), (72, 6, 6, 1.9, 0.7), (76, 20, 6, 1.6, 1.5), (65, 26, 5, 1.8, 0.4),
    ]
    /// 粉紫描边（识意自动）：#A855F7 → #EC4899 → #FDE68A → #F0ABFC。
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

// MARK: - 结果卡片

/// 结果卡片：提示、出错、首次使用清单也都显示在这个位置。
/// 有结果时右边一列是 ✦ 状态、复制、展开，多个版本时再加一列 ▲ 2/3 ▼。
struct ResultCard: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
            // 生成中第一行是流光小字「AI 正在改写… / 正在回答…」（QA10），出结果后这行字消失，
            // 「AI 生成」标签（CP8）放在正文第一行开头，只在界面上标，不往正文里插任何标记。
            if model.isRunning {
                RunningLabel(text: runningTitle, color: runningColor, animating: animating)
                    .padding(.leading, 10)
                    .padding(.top, 8)
            }
            resultText(faded: faded)
                .padding(.leading, 10)
                .padding(.top, model.isRunning ? 4 : 8)
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
                    let point = CGPoint(x: value.location.x - 10, y: value.location.y - (model.isRunning ? 4 : 8))
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

    private var runningTitle: String {
        guard model.askRunning else { return L("AI 正在润色…", "AI is polishing…", "AI が整えています…") }
        switch model.askKind {
        case .answer: return L("AI 正在回答…", "AI is answering…", "AI が回答しています…")
        case .rewrite: return L("AI 正在改写…", "AI is rewriting…", "AI が書き換えています…")
        case nil: return L("AI 正在理解…", "AI is reading…", "AI が考えています…")
        }
    }

    private var runningColor: Color { model.askKind == .answer ? Brand.answerText : Brand.purpleText }

    @ViewBuilder
    private func resultText(faded: Bool) -> some View {
        let tag = model.isRunning ? Text("") : Text(Image(uiImage: AIGeneratedTag.image(dark: colorScheme == .dark))).baselineOffset(-3.5) + Text(" ")
        let text = tag + Text(model.displayText) + Text(model.isRunning ? "▍" : "").foregroundColor(runningColor)
        Group {
            if model.isRunning && model.displayText.isEmpty {
                // 还没出字：两条灰条占位。
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Brand.skeleton).frame(height: 12).frame(maxWidth: .infinity)
                        .padding(.trailing, 30)
                    Capsule().fill(Brand.skeleton).frame(height: 12).frame(maxWidth: .infinity)
                        .padding(.trailing, 110)
                }
                .padding(.top, 6)
            } else if model.cardTall {
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
                FlowingBorder(shape: shape, colors: model.askKind == .answer ? Brand.answerRing : Brand.gradient)
            } else {
                shape.strokeBorder((model.askKind == .answer ? Brand.answerBorder : Brand.purpleText).opacity(0.5), lineWidth: 1)
            }
        case .fresh:
            // 识意的回答天蓝边、识意改写的一版紫边（QA5、QA6），按提示词润色的照旧渐变细边。
            if model.session?.currentIsAnswer == true {
                shape.strokeBorder(Brand.answerBorder, lineWidth: 1.5)
            } else if model.session?.currentIsAsk == true {
                shape.strokeBorder(Brand.rowStroke, lineWidth: 1.5)
            } else {
                shape.strokeBorder(LinearGradient(colors: Brand.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 1.2)
            }
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
                Text(L("点「\(chipName) ▾」换一条提示词；点「识意 ▾」问个问题，或说说想怎么改：翻成日语、改成朋友圈语气……", "Tap \(chipName) ▾ to switch prompts, or tap Ask ▾ to ask anything or say how to change it…", "「\(chipName) ▾」でプロンプトを切り替え、「たずねる ▾」で質問や直し方の指示ができます……"))
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
    /// 问答时换成天蓝一圈。
    var colors: [Color] = Brand.gradient

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let wave = (1 - cos(2 * .pi * phase)) / 2
            ZStack {
                shape.stroke(colors[1].opacity(0.18 + 0.14 * wave), lineWidth: 4).blur(radius: 3)
                shape.strokeBorder(AngularGradient(colors: colors + [colors[0]], center: .center,
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
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel(L("失败，重试", "Failed, retry", "失敗・再試行"))
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

    /// 同一个标签画成图片，拼在正文第一行开头（QA5、QA6）：Text 里只能嵌图片，嵌不了视图。按深浅色、语言各画一次。
    private static var images: [String: UIImage] = [:]

    static func image(dark: Bool) -> UIImage {
        let label = L("AI 生成", "AI-generated", "AI 生成")
        let key = "\(dark)\(label)"
        if let image = images[key] { return image }
        let fill = dark ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
            : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
        let ink = dark ? UIColor(red: 0xAE / 255, green: 0xAE / 255, blue: 0xB2 / 255, alpha: 1)
            : UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x73 / 255, alpha: 1)
        let font = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        let star = UIImage(systemName: "sparkle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))?
            .withTintColor(ink, renderingMode: .alwaysOriginal)
        let starWidth = star?.size.width ?? 0
        let textSize = (label as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(6 + starWidth + 3 + textSize.width + 6), height: 18)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
            star?.draw(at: CGPoint(x: 6, y: (size.height - (star?.size.height ?? 0)) / 2))
            (label as NSString).draw(at: CGPoint(x: 6 + starWidth + 3, y: (size.height - textSize.height) / 2),
                                     withAttributes: [.font: font, .foregroundColor: ink])
        }
        images[key] = image
        return image
    }
}

/// 生成中卡片第一行的流光小字（QA10）：星星 +「AI 正在改写… / 正在回答…」，一道亮光从左扫到右。
struct RunningLabel: View {
    var text: String
    var color: Color
    var animating: Bool

    var body: some View {
        let label = HStack(spacing: 5) {
            Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(height: 18)
        if animating {
            label.overlay {
                GeometryReader { geo in
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 40)
                            .offset(x: -40 + (geo.size.width + 40) * phase)
                    }
                }
                .mask(label)
                .allowsHitTesting(false)
            }
        } else {
            label
        }
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
