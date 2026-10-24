import SwiftUI

/// 键盘主体。
/// AI 栏永远紧贴按键上方，收起和展开是同一条：[展开/收起] [✨ 润色] [正式▾] … [撤销|重做]；打拼音时这一行换成候选。
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
                        .frame(height: model.cardTall ? KeyboardMetrics.expandedCardHeight : KeyboardMetrics.cardHeight)
                    actionRow
                        .frame(height: KeyboardMetrics.actionRow)
                }
                .padding(.horizontal, inset)
                .padding(.top, KeyboardMetrics.panelTop)
            }
            if model.gate == nil, model.styleMenuOpen {
                StyleMenu(model: model)
                    .frame(height: KeyboardMetrics.menuHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, model.aiExpanded ? KeyboardMetrics.panelSpacing : KeyboardMetrics.panelTop)
            }
            Group {
                if model.isComposing {
                    candidateBar
                } else if model.target == .card {
                    cardEditHint
                } else {
                    aiBar
                }
            }
            .frame(height: KeyboardMetrics.topRow)
            KeysView(model: model)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
                .layoutPriority(1)
        }
        // 系统给的高度不够时从顶上裁，按键始终完整贴在底部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    // MARK: - AI 栏

    /// 在卡片里改结果时 AI 栏换成提示。
    private var cardEditHint: some View {
        HStack(spacing: 8) {
            Label("正在修改结果", systemImage: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Brand.returnSoftFill))
            Text("打字进卡片，按住空格左右滑动移光标")
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
            PanelToggleButton(expanded: model.aiExpanded) { model.setAIExpanded(!model.aiExpanded) }
            PolishButton(model: model)
            // 风格按钮优先完整显示，地方不够时失败提示换成短的。
            StyleChip(model: model).layoutPriority(1)
            if model.quickStatus == .failed, !model.aiExpanded {
                QuickRetryLabel(model: model)
            }
            Spacer(minLength: 0)
            UndoRedoPair(model: model)
        }
        .padding(.horizontal, inset)
    }

    /// 打拼音时的候选栏，右边的箭头展开整页候选。
    private var candidateBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(model.candidates.prefix(60).enumerated()), id: \.offset) { index, word in
                        Button { model.selectCandidate(index) } label: {
                            Text(word)
                                .font(.system(size: 20))
                                .foregroundStyle(index == 0 ? Brand.purple : Color.primary)
                                .padding(.horizontal, 11)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
                .padding(.leading, 2)
            }
            .hidingScrollEdgeEffect()
            Divider().frame(height: 22)
            Button { model.candidatesExpanded.toggle() } label: {
                Image(systemName: model.candidatesExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44)
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
                PanelButton(title: "取消修改", systemImage: nil, kind: .plain) { model.cancelCardEdit() }
                PanelButton(title: "完成修改", systemImage: "checkmark", kind: .primary) { model.finishCardEdit() }
            }
        } else {
            useRow
        }
    }

    private var useRow: some View {
        let replaced = model.resultUse == .replaced
        let inserted = model.resultUse == .inserted
        return HStack(spacing: 6) {
            PanelButton(title: replaced ? "已替换" : "替换",
                        systemImage: replaced ? "checkmark" : "arrow.left.arrow.right",
                        kind: replaced ? .done : .primary) { model.replace() }
                .disabled(!model.hasResult || replaced)
            PanelButton(title: inserted ? "已插入" : "插入",
                        systemImage: inserted ? "checkmark" : "text.insert",
                        kind: inserted ? .done : .outlined) { model.insert() }
                .disabled(!model.hasResult || inserted)
        }
    }
}

// MARK: - AI 栏的按钮

/// 展开/收起 AI 面板，AI 栏最左边的圆钮。
struct PanelToggleButton: View {
    var expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: KeyboardMetrics.chipHeight, height: KeyboardMetrics.chipHeight)
                .foregroundStyle(Color.primary)
                .background(Circle().fill(KeyStyle.charKey))
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 「✨ 润色」：收起和展开都是这一个按钮，尺寸、文字和颜色一直不变；生成中再点一下就取消。
/// 收起时（快速模式）动画只在按钮里：流光描边、白色扫光、星星闪、小闪光，完成时星星闪一下金色。
struct PolishButton: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var doneAt: Date?

    private var quickRunning: Bool { model.isRunning && model.quickStatus == .running && !model.aiExpanded }
    /// 关了发光动画或开了减弱动态效果：只留星星轻微闪动。
    private var fullMotion: Bool { model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        let shape = Capsule()
        Button {
            model.isRunning ? model.stop() : model.sparkleTapped()
        } label: {
            HStack(spacing: 5) {
                PolishStars(size: 15, running: quickRunning, glowing: fullMotion, doneAt: fullMotion ? doneAt : nil)
                Text("润色")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: KeyboardMetrics.polishButtonWidth, height: KeyboardMetrics.chipHeight)
            .background(shape.fill(fill))
            .overlay {
                if quickRunning && fullMotion {
                    PolishButtonGlow().clipShape(shape)
                }
            }
            .overlay(alignment: .topLeading) {
                // 没开完全访问：右上角一个小锁（P01）。
                if !model.hasFullAccess {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Brand.lockFill))
                        .overlay(Circle().strokeBorder(Brand.lockRing, lineWidth: 2))
                        .offset(x: 72, y: -4)
                }
            }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(model.isRunning ? "正在润色，轻点取消" : "润色")
        .onChange(of: model.quickStatus) { status in
            doneAt = status == .done ? Date() : nil
        }
    }

    private var fill: Color {
        return model.aiBlocked && !model.isRunning ? Brand.purple.opacity(0.35) : Brand.purple
    }
}

/// 快速模式润色中按钮里的动画：1.5pt 流光描边（1.6 秒一圈，外面不加光晕）、60pt 白色光带扫过、10 颗白色小闪光。
struct PolishButtonGlow: View {
    /// 小闪光的位置（相对 84×34 的按钮，x、y、大小）和周期。
    private static let sparkles: [(x: CGFloat, y: CGFloat, d: CGFloat, period: Double, offset: Double)] = [
        (4, 8, 6, 1.5, 0.0), (9, 22, 5, 1.7, 0.6), (21, 2, 6, 1.9, 1.1), (29, 26, 5, 1.6, 0.3), (39, 1, 5, 1.8, 0.9),
        (52, 27, 6, 1.5, 1.3), (60, 1, 5, 1.7, 0.2), (72, 6, 6, 1.9, 0.7), (76, 20, 6, 1.6, 1.5), (65, 26, 5, 1.8, 0.4),
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
                let sx = geo.size.width / 84, sy = geo.size.height / 34
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.32), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 60, height: geo.size.height)
                        .blur(radius: 4)
                        .offset(x: -60 + (geo.size.width + 60) * phase)
                    ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { _, s in
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
                    Capsule().strokeBorder(AngularGradient(colors: Brand.gradient + [Brand.gradient[0]], center: .center,
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

/// 「正式▾」：显示当前风格，有要求时写「正式 · 有要求」并描紫边；点开风格浮层。
struct StyleChip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let locked = !model.hasFullAccess
        let highlighted = !locked && (model.styleMenuOpen || !model.instruction.isEmpty)
        Button { locked ? model.showFullAccessTip() : model.toggleStyleMenu() } label: {
            HStack(spacing: 3) {
                Text(title).lineLimit(1)
                Image(systemName: model.styleMenuOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 14, weight: highlighted ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: KeyboardMetrics.chipHeight)
            .foregroundStyle(highlighted ? Brand.purple : Color.primary)
            .background(Capsule().fill(highlighted ? Brand.menuFill : KeyStyle.charKey))
            .overlay(Capsule().strokeBorder(Brand.purple, lineWidth: highlighted ? 1.2 : 0))
            .opacity(locked ? 0.45 : 1)
        }
        .buttonStyle(KeyPressStyle())
    }

    private var title: String {
        let name = model.settings.selectedStyle?.name ?? "风格"
        return model.instruction.isEmpty ? name : "\(name) · 有要求"
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

/// 淡紫浮层，尖角指向「正式▾」：上面一行选风格，下面一行写要求和「润色」。
/// 点风格只切换，不马上改；点「润色」或回车「执行」才开始，浮层不收起，再点「正式▾」才收。
struct StyleMenu: View {
    @ObservedObject var model: KeyboardModel

    /// 尖角对准「正式▾」：展开键 + 间距 + 润色键 + 间距，再往右到按钮中间附近。
    private let arrowX: CGFloat = KeyboardMetrics.chipHeight + 6 + KeyboardMetrics.polishButtonWidth + 6 + 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                rowLabel("风格")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(model.settings.styles) { style in
                            MenuStyleTag(title: style.name, selected: style.id == model.settings.selectedStyle?.id) {
                                model.selectStyle(style)
                            }
                        }
                    }
                }
                .hidingScrollEdgeEffect()
            }
            .frame(height: 32)
            HStack(spacing: 8) {
                rowLabel("要求")
                RequestField(model: model)
                MenuPolishButton(model: model)
            }
            .frame(height: 32)
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
            .frame(width: 34, alignment: .leading)
    }
}

/// 浮层里的「再润」：和「润色」同款实心胶囊，换成紫到粉的渐变区分开；按选好的风格和要求开始改，生成中样子不变，再点一下取消。
/// 面板收起时直接替换输入框，展开时进结果卡片。
struct MenuPolishButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button {
            model.isRunning ? model.stop() : model.menuPolishTapped()
        } label: {
            HStack(spacing: 4) {
                SparkleMark(size: 13, color: .white)
                Text("再润")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 72, height: 30)
            .background(Capsule().fill(Brand.rerunGradient))
            .opacity(model.aiBlocked && !model.isRunning ? 0.4 : 1)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(model.isRunning ? "正在润色，轻点取消" : "再润")
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
            case .consent(let endpoint, let previous): consent(endpoint, previous: previous)
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
            Text("AI 润色需要开启「允许完全访问」").font(.system(size: 14, weight: .semibold))
        }
        Text("打字不受影响。开启后才能用 AI 润色，App 里的键盘设置也会同步过来。")
            .font(.system(size: 13))
            .foregroundStyle(Brand.cardBody)
            .fixedSize(horizontal: false, vertical: true)
        // 没开完全访问时 iOS 不让键盘打开任何 App，只能把路径写出来。
        VStack(alignment: .leading, spacing: 3) {
            Text("在系统设置里开启").font(.system(size: 11.5)).foregroundStyle(Brand.disabledText)
            settingsPath.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.tagFill))
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Text("也可以打开 Enclave App 按指引开启")
                .font(.system(size: 12))
                .foregroundStyle(Brand.disabledText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            GateButton(title: "知道了", primary: true) { model.dismissGate() }
        }
    }

    /// 设置 › 通用 › 键盘 › 键盘 › Enclave › 允许完全访问：分隔符浅灰，最后一项深紫加粗。
    private var settingsPath: Text {
        let steps = ["设置", "通用", "键盘", "键盘", "Enclave"]
        var text = Text("")
        for step in steps {
            text = text + Text(step).foregroundColor(Brand.cardBody) + Text(" > ").foregroundColor(Brand.pathSeparator)
        }
        return text + Text("允许完全访问").fontWeight(.semibold).foregroundColor(Brand.deepPurple)
    }

    @ViewBuilder
    private func consent(_ endpoint: String, previous: String?) -> some View {
        HStack(spacing: 6) {
            SparkleMark(size: 14, color: Brand.tagSelectedText)
            Text(previous == nil ? "润色前确认一下" : "接口地址变了，再确认一次").font(.system(size: 14, weight: .semibold))
        }
        HStack(spacing: 6) {
            Text("文字会发送到").font(.system(size: 13)).foregroundStyle(Brand.cardBody)
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
            (Text("原来是 ") + Text(previous).strikethrough())
                .font(.system(size: 12))
                .foregroundStyle(Brand.panelLabel.opacity(0.7))
        }
        Text("只在你点「润色」或「再润」时发送：输入框里的文字（选中时只发选中的部分）和你写的要求。由这个接口处理后返回结果；Enclave 没有自己的服务器，也不保存你的文字。")
            .font(.system(size: 12))
            .foregroundStyle(Brand.cardNote)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Button { model.openContainingApp("enclave://privacy-policy") } label: {
                Text("隐私政策").font(.system(size: 12)).foregroundStyle(Brand.tagSelectedText)
            }
            .buttonStyle(.plain)
            Spacer()
            GateButton(title: "取消", primary: false) { model.dismissGate() }
            GateButton(title: "同意并润色", primary: true) { model.acceptConsent() }
        }
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

/// 浮层里的风格：没选中浅灰底黑字，选中和要求框同一个渐变、白字。
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
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background {
                    if selected {
                        Capsule().fill(Brand.fieldLinearGradient)
                    } else {
                        Capsule().fill(Brand.tagFill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 要求框：实心紫色渐变，白字白光标，铅笔图标。键盘打的字进这里，回车就执行。
struct RequestField: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let editing = model.target == .instruction
        let text = model.instruction
        let showsPlaceholder = text.isEmpty && !(editing && model.isComposing)
        HStack(spacing: 5) {
            Image(systemName: "pencil").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
            Group {
                if showsPlaceholder {
                    (Text(editing ? "|" : "").foregroundColor(.white)
                        + Text("写要求，比如：语气委婉一点").foregroundColor(Color.white.opacity(0.85)))
                } else {
                    // 每段都写明白色：拼到一半的拼音不写的话会显示成强调色，在紫底上看不清。
                    (Text(text).foregroundColor(.white)
                        + Text(editing ? model.composition : "").underline(color: .white).foregroundColor(.white)
                        + Text(editing ? "|" : "").foregroundColor(.white))
                }
            }
            .lineLimit(1)
            .truncationMode(.head)
            Spacer(minLength: 0)
            if !text.isEmpty {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.35)))
                    .onTapGesture { model.setInstruction("") }
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Brand.fieldLinearGradient))
        .contentShape(Rectangle())
        .onTapGesture { model.toggleInstructionEditing() }
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
                Label("已复制", systemImage: "checkmark")
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
            resultText(faded: faded)
                .padding(.leading, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                // 不展开时上下滑翻版本（展开时文字区要留给滚动）；长按复制。
                // 滑动放在主手势、长按放在同时识别，onLongPressGesture 会把拖动吞掉。
                .gesture(swipeToTurn, including: model.cardTall ? .subviews : .all)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in model.copy() })
                // 点文字进入修改，光标放在点的位置。
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    guard model.hasResult, let text = model.session?.current else { return }
                    // 减掉文字区的内边距；展开卡片滚动过时按未滚动估算，进入后可以再点一次调整。
                    let point = CGPoint(x: value.location.x - 10, y: value.location.y - 8)
                    model.beginCardEdit(caret: CardTextHit.index(at: point, in: text, width: textWidth))
                })
            iconColumn(faded: faded)
                .padding(.vertical, 5)
            if let session = model.session, session.versions.count > 1, !model.isRunning {
                pager(index: session.currentIndex, count: session.versions.count)
                    .contentShape(Rectangle())
                    // 优先于 ▲▼ 按钮：手指在按钮里滑一下松开，按钮也会算一次点击，就翻了两页。
                    .highPriorityGesture(swipeToTurn)
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func resultText(faded: Bool) -> some View {
        let text = Text(model.displayText) + Text(model.isRunning ? "▍" : "").foregroundColor(Brand.purple)
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
                SparkleMark(size: 15, color: Brand.purple, animating: animating)
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
            iconButton(model.copied ? "doc.on.doc.fill" : "doc.on.doc", tint: model.copied ? Brand.purple : .secondary) {
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
                Text("已改").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Brand.deepPurple)
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
                shape.strokeBorder(Brand.purple.opacity(0.5), lineWidth: 1)
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

    private func hintView(_ notice: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notice {
                Text(notice).font(.system(size: 13)).foregroundStyle(Color.primary)
            } else {
                HStack(spacing: 4) {
                    SparkleMark(size: 11, color: Brand.purple)
                    Text("点「润色」整理输入框里的话").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.purple)
                }
                Text("选中一段只改选中的部分；点「\(model.settings.selectedStyle?.name ?? "风格")▾」换风格或写要求；输入框为空时写要求，它会帮你写。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("出错了", systemImage: "exclamationmark.circle")
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
                SparkleMark(size: 12, color: Brand.purple)
                Text("还差几步就能用 AI，打字不受影响").font(.system(size: 13, weight: .semibold))
            }
            checkRow(1, "打开「允许完全访问」", done: model.hasFullAccess)
            HStack {
                checkRow(2, "配置模型 API", done: model.settings.isConfigured)
                Spacer(minLength: 0)
                if !model.settings.isConfigured {
                    Button { model.importConfigFromPasteboard() } label: {
                        Text("从剪贴板导入")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.purple)
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
                Text("润色失败，点重试")
                Text("失败，重试")
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

