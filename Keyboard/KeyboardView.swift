import SwiftUI

/// 键盘主体。
/// AI 栏永远紧贴按键上方，收起和展开是同一条：[展开/收起] [✨ 润色] [正式▾] … [撤销|重做]；打拼音时这一行换成候选。
/// 展开时 AI 栏上面是结果卡片和动作行（替换、插入）；打开「正式▾」时 AI 栏上面再加风格浮层。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    private var inset: CGFloat { KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX }

    var body: some View {
        VStack(spacing: 0) {
            if model.aiExpanded {
                VStack(spacing: KeyboardMetrics.panelSpacing) {
                    ResultCard(model: model)
                        .frame(height: model.cardTall ? KeyboardMetrics.expandedCardHeight : KeyboardMetrics.cardHeight)
                    actionRow
                        .frame(height: KeyboardMetrics.actionRow)
                }
                .padding(.horizontal, inset)
                .padding(.top, KeyboardMetrics.panelTop)
            }
            if model.styleMenuOpen {
                StyleMenu(model: model)
                    .frame(height: KeyboardMetrics.menuHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, model.aiExpanded ? KeyboardMetrics.panelSpacing : KeyboardMetrics.panelTop)
            }
            Group {
                if model.isComposing {
                    candidateBar
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

    private var aiBar: some View {
        HStack(spacing: 6) {
            PanelToggleButton(expanded: model.aiExpanded) { model.setAIExpanded(!model.aiExpanded) }
            PolishButton(model: model)
            StyleChip(model: model)
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
    private var actionRow: some View {
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

/// 「✨ 润色」：收起和展开都是这一个按钮，生成中原位变「停止」，尺寸不变。
struct PolishButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button {
            model.isRunning ? model.stop() : model.sparkleTapped()
        } label: {
            HStack(spacing: 5) {
                if model.isRunning {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).frame(width: 9, height: 9)
                    Text("停止")
                } else {
                    SparkleMark(size: 15, color: .white)
                    Text("润色")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: KeyboardMetrics.polishButtonWidth, height: KeyboardMetrics.chipHeight)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(KeyPressStyle())
    }

    private var fill: Color {
        if model.isRunning { return Color(white: 0.16) }
        return model.aiBlocked ? Brand.purple.opacity(0.35) : Brand.purple
    }
}

/// 「正式▾」：显示当前风格，有要求时写「正式 · 有要求」并描紫边；点开风格浮层。
struct StyleChip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let highlighted = model.styleMenuOpen || !model.instruction.isEmpty
        Button { model.toggleStyleMenu() } label: {
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
    enum Kind { case primary, outlined, done }

    var title: String
    var systemImage: String?
    var kind: Kind
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Brand.purple.opacity(isEnabled ? 0.9 : 0.3), lineWidth: kind == .outlined ? 1.2 : 0))
        }
        .buttonStyle(KeyPressStyle())
    }

    private var fill: Color {
        switch kind {
        case .primary: return Brand.purple.opacity(isEnabled ? 1 : 0.35)
        case .outlined: return KeyStyle.charKey
        case .done: return Brand.softFill
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return isEnabled ? .white : .white.opacity(0.85)
        case .outlined: return isEnabled ? Brand.purple : Brand.purple.opacity(0.4)
        case .done: return Brand.purple
        }
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
        .background(MenuBubble(arrowX: arrowX).fill(Brand.menuFill).shadow(color: .black.opacity(0.08), radius: 4, y: 1))
        .overlay(MenuBubble(arrowX: arrowX).stroke(Brand.menuStroke, lineWidth: 1))
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Brand.purple)
            .frame(width: 26, alignment: .leading)
    }
}

/// 浮层里的「再润」：白底紫描边，和 AI 栏实心的「✨ 润色」区分开；按选好的风格和要求开始改，生成中原位变深灰「停止」。
struct MenuPolishButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button {
            model.isRunning ? model.stop() : model.menuPolishTapped()
        } label: {
            HStack(spacing: 4) {
                if model.isRunning {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).frame(width: 8, height: 8)
                    Text("停止")
                } else {
                    SparkleMark(size: 13, color: Brand.violet)
                    Text("再润")
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(model.isRunning ? Color.white : Brand.deepPurple)
            .frame(width: 72, height: 30)
            .background(Capsule().fill(model.isRunning ? Brand.stopFill : KeyStyle.charKey))
            .overlay(Capsule().strokeBorder(Brand.violet, lineWidth: model.isRunning ? 0 : 1.5))
            .opacity(model.aiBlocked && !model.isRunning ? 0.4 : 1)
        }
        .buttonStyle(KeyPressStyle())
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

/// 浮层里的风格：选中的是实心紫色胶囊。
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
                .background(Capsule().fill(selected ? Brand.purple : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 要求框：方角淡紫底，铅笔图标，紫色字。键盘打的字进这里，回车就执行。
struct RequestField: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let editing = model.target == .instruction
        let text = model.instruction
        let showsPlaceholder = text.isEmpty && !(editing && model.isComposing)
        HStack(spacing: 5) {
            Image(systemName: "pencil").font(.system(size: 13, weight: .medium))
            Group {
                if showsPlaceholder {
                    (Text(editing ? "|" : "").foregroundColor(Brand.purple)
                        + Text("写要求，比如：语气委婉一点").foregroundColor(Brand.purple.opacity(0.45)))
                } else {
                    (Text(text)
                        + Text(editing ? model.composition : "").underline()
                        + Text(editing ? "|" : ""))
                }
            }
            .lineLimit(1)
            .truncationMode(.head)
            Spacer(minLength: 0)
            if !text.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Brand.purple.opacity(0.4))
                    .onTapGesture { model.setInstruction("") }
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Brand.purple)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(editing ? Brand.fieldActiveStroke : Brand.fieldStroke, lineWidth: editing ? 1.5 : 1))
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

    private enum Look { case checklist, error(String), hint(String?), running, fresh, faded }

    private var look: Look {
        if model.aiBlocked { return .checklist }
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
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
            iconColumn(faded: faded)
                .padding(.vertical, 5)
            if let session = model.session, session.versions.count > 1, !model.isRunning {
                pager(index: session.currentIndex, count: session.versions.count)
                    .contentShape(Rectangle())
                    .simultaneousGesture(swipeToTurn)
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
    }

    /// ✦ 状态、复制、展开：15pt 线性图标，24×18 点击区，上中下对齐。
    private func iconColumn(faded: Bool) -> some View {
        VStack(spacing: 0) {
            SparkleMark(size: 15, color: faded ? Color.secondary.opacity(0.7) : Brand.purple, animating: animating)
                .frame(width: 24, height: 18)
                .background(Capsule().fill(model.isRunning ? Brand.softFill : Color.clear))
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
            guard abs(value.translation.height) > abs(value.translation.width) else { return }
            if value.translation.height < -20 { turn(1) } else if value.translation.height > 20 { turn(-1) }
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
            checkRow(2, model.pinyinReady ? "拼音词库已就绪" : "拼音词库：打开一次 Enclave App 部署", done: model.pinyinReady)
            HStack {
                checkRow(3, "配置模型 API", done: model.settings.isConfigured)
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

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let wave = (1 - cos(2 * .pi * phase)) / 2
            ZStack {
                shape.stroke(Brand.violet.opacity(0.18 + 0.14 * wave), lineWidth: 4).blur(radius: 3)
                shape.strokeBorder(AngularGradient(colors: Brand.gradient + [Brand.gradient[0]], center: .center,
                                                   angle: .degrees(phase * 360)),
                                   lineWidth: 1.6)
            }
        }
        .allowsHitTesting(false)
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

