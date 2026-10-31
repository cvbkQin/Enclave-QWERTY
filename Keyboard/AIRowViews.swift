import SwiftUI

// MARK: - AI 栏的两颗风格键（MG1–MG5）

/// 改写风格键、问答风格键（AB2）：展开时才有，紫色 / 蓝色柔和混色底、白字白图标。
/// 回答卡上是哪一种结果，那一颗就激活：1.5pt 浅色边框、两小段白光沿边框转（3 秒一圈）、外面 3pt 淡外圈（扁平化后不再有 10pt 的光）。
struct StyleKey: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var answer: Bool { row == .answerStyles }

    var body: some View {
        let locked = !model.hasFullAccess
        let open = !locked && model.aiRow == row
        let active = !locked && isActive
        Button { locked ? model.showFullAccessTip() : model.toggleRow(row) } label: {
            Self.face(answer: answer, title: Self.title(model, answer: answer), open: open)
            .background {
                // 激活：外面 3pt 淡外圈，润色 rgba(124,58,237,.25)、直击要害 rgba(14,165,233,.25)。
                if active {
                    Capsule().fill(answer ? Self.answerGlow : Self.rewriteGlow).padding(-3)
                }
            }
            .overlay {
                if active || open {
                    Capsule().strokeBorder(answer ? Self.answerBorder : Self.rewriteBorder, lineWidth: 1.5)
                }
                if active && !reduceMotion {
                    StyleKeySpots().mask(Capsule().strokeBorder(lineWidth: 1.5))
                }
            }
            .opacity(locked ? 0.45 : 1)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: RowChipFrameKey.self, value: [row: geometry.frame(in: .named("keyboard"))])
            })
            // 点按区上下各扩 5pt；垫一层几乎透明的底，系统才把字缝、▾ 旁边的触摸交给键盘（混色底不接触摸）。
            .padding(.vertical, 5)
            .background(PolishButton.touchFill)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel((answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル")) + "：" + Self.title(model, answer: answer))
        .accessibilityValue(open ? L("已展开", "Expanded", "展開中") : L("已收起", "Collapsed", "折りたたみ"))
    }

    static let rewriteBorder = NebulaFill.color(0xC4B5FD)
    static let answerBorder = NebulaFill.color(0x7DD3FC)
    static let rewriteGlow = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255).opacity(0.25)
    static let answerGlow = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255).opacity(0.25)

    /// 柔和混色底、白字白图标（AB2；底色、竖线和内边距按 FB2）：高 34、左内边 7、右内边 6；15pt 图标、间距 3、13.5pt 600 风格名（最宽 76）、竖线、10pt ▾。
    /// 宽度按字算死，AI 栏分裂动画里画的那几颗和这里一样宽。
    static func face(answer: Bool, title: String, open: Bool = false, filled: Bool = true) -> some View {
        HStack(spacing: 3) {
            Image(systemName: answer ? "questionmark.circle" : "pencil")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: textWidth(title))
            chevronDivider
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 10)
        }
        .foregroundStyle(.white)
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(width: width(title), height: KeyboardMetrics.chipHeight)
        .background {
            if filled { NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()) }
        }
    }

    /// 风格名的宽度，最宽 76，太长截断。
    static func textWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        return min(76, ceil((title as NSString).size(withAttributes: [.font: font]).width))
    }

    /// 名字和 ▾ 之间的竖线：1×14、白 45%，和放大镜里那条一样（FB）。两边的 3pt 由 HStack 间距给。
    static var chevronDivider: some View {
        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
    }

    /// 整颗的宽：7 + 图标 16 + 3 + 字 + 3 + 竖线 1 + 3 + ▾ 10 + 6。
    static func width(_ title: String) -> CGFloat { 49 + textWidth(title) }

    /// 展开、有结果时，回答卡上是问答就激活问答那颗，否则激活改写那颗（润色也算改写）。
    private var isActive: Bool {
        guard model.aiExpanded, model.target != .card, let session = model.session, session.current != nil else { return false }
        return session.currentIsAnswer == answer
    }

    /// 润色键写当前润色风格的名字；问答键固定写「问答」，不写风格名（KB1）。
    static func title(_ model: KeyboardModel, answer: Bool) -> String {
        if answer { return L("问答", "Ask", "質問") }
        return model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
    }
}

/// 激活的风格键边框上两小段亮光，相隔 180°，匀速 3 秒一圈。只在激活时出现，外面用边框形状遮住。
struct StyleKeySpots: View {
    @State private var spin = false

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.5
            AngularGradient(stops: [
                .init(color: .clear, location: 0), .init(color: Brand.styleSpot, location: 0.05), .init(color: .clear, location: 0.1),
                .init(color: .clear, location: 0.5), .init(color: Brand.styleSpot, location: 0.55), .init(color: .clear, location: 0.6),
                .init(color: .clear, location: 1),
            ], center: .center)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { spin = true }
        }
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
/// 小标题「润色风格」/「问答风格」11.5 灰；每项高 36、字 15，当前那条浅紫底 + 主色 600 + ✓。顺序就是 App 列表里的顺序。
/// 回答卡收起和展开都一样；点一条就换、框收起。
struct StyleDropdown: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    /// 键盘里往下还剩多高，放不下时里面滚动。
    var maxHeight: CGFloat

    static let width: CGFloat = 196
    private static let itemHeight: CGFloat = 36
    private static let headerHeight: CGFloat = 26

    private var answer: Bool { row == .answerStyles }

    var body: some View {
        let styles = answer ? model.settings.answerStyles : model.settings.styles
        let selectedID = answer ? model.settings.selectedAnswerStyle?.id : model.settings.selectedStyle?.id
        let natural = Self.headerHeight + CGFloat(styles.count) * Self.itemHeight + 12
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル"))
                .font(.system(size: 11.5))
                .foregroundStyle(DropdownStyle.hint)
                .padding(.horizontal, 10)
                .frame(height: Self.headerHeight, alignment: .leading)
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(styles) { style in
                            item(style, selected: style.id == selectedID).id(style.id)
                        }
                    }
                }
                .scrollDisabled(natural <= maxHeight)
                .onAppear { if let selectedID, natural > maxHeight { reader.scrollTo(selectedID, anchor: .center) } }
            }
        }
        .padding(6)
        .frame(width: Self.width, height: max(Self.headerHeight + Self.itemHeight + 12, min(natural, maxHeight)), alignment: .top)
        .background(shape.fill(DropdownStyle.fill)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.22), radius: 12, y: 8))
        // 深色下和按键颜色接近：加一圈细边（和拼音键弹框一样）。
        .overlay(shape.strokeBorder(DropdownStyle.stroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル"))
    }

    private func item(_ style: StylePreset, selected: Bool) -> some View {
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
            .padding(.horizontal, 10)
            .frame(height: Self.itemHeight)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? DropdownStyle.selectedFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            if !editing, model.instruction.isEmpty {
                Text(L("点这里输入", "Tap to type", "タップして入力"))
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.askFaint)
                    .lineLimit(1)
                    .fixedSize()
                    .onTapGesture { model.focusAsk() }
                    .accessibilityHidden(true)
            }
            searchButton
        }
        .padding(.horizontal, 12)
        .font(.system(size: 15))
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
        L("问个问题，或说说这段话想怎么改", "Ask anything, or say how to change it", "質問するか、どう直すかを書いてください")
    }

    /// 光标前、正在拼的拼音（紫色下划线）、光标、光标后。全选时整段垫浅紫底。写长了从开头省略，光标那头总露着。
    @ViewBuilder
    private func line(caretVisible: Bool?) -> some View {
        let text = model.instruction
        let composing = model.target == .instruction ? model.composition : ""
        if text.isEmpty && composing.isEmpty {
            Text(placeholder)
                .foregroundStyle(caretVisible == nil ? Brand.askFaint : Brand.askPlaceholderActive)
                .lineLimit(1)
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
                // 未激活时留着的字变灰。
                .foregroundStyle(caretVisible == nil ? Brand.askSub : Brand.askText)
                .lineLimit(1)
                .truncationMode(atEnd ? .head : .tail)
        }
    }

    private func caretImage(_ visible: Bool) -> some View {
        Image(uiImage: Self.caret).foregroundStyle(Brand.askCaret.opacity(visible ? 1 : 0))
    }
}
