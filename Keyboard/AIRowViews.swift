import SwiftUI

// MARK: - AI 栏的润色键、问答键（AK1–AK3）

/// 回答卡展开时 AI 栏的两颗键：润色键「✎ 正式 ｜ ⌄」、问答键「? 问答 ｜ ⌄」，紫色 / 蓝色柔和混色底、白字白图标。
/// 竖线左边（图标 + 名字）点了就执行：润色键按当前润色风格改输入框里的话（识意框里的要求一起带上），问答键回答识意框里的问题。
/// 竖线右边 ⌄ 那块（36pt 宽，整块都算）弹风格下拉框，选完收起、不执行。生成中点名字是停止。
/// 回答卡上的结果来自哪颗，那颗外面一圈 2pt 亮边（离键 2pt），两小段白光沿着亮边转（3 秒一圈）。
struct StyleKey: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    var width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var answer: Bool { row == .answerStyles }

    var body: some View {
        let locked = !model.hasFullAccess
        let open = !locked && model.aiRow == row
        let active = !locked && isActive
        let running = model.isRunning && model.runOrigin == (answer ? KeyboardModel.RunOrigin.ask : KeyboardModel.RunOrigin.polish)
        let title = Self.title(model, answer: answer)
        let layout = Self.layout(width: width, title: title)
        ZStack(alignment: .leading) {
            Self.face(answer: answer, title: title, width: width, open: open, running: running)
                .overlay {
                    if open { Capsule().strokeBorder(answer ? Self.answerBorder : Self.rewriteBorder, lineWidth: 1.5) }
                }
                .overlay {
                    if running && model.settings.polishAnimation && !reduceMotion {
                        PolishButtonGlow(ring: answer ? Brand.answerRing : Brand.gradient).clipShape(Capsule())
                    }
                }
                .overlay {
                    // 亮边：离键 2pt、宽 2pt（AK2）。
                    if active {
                        ZStack {
                            Capsule().strokeBorder(answer ? Self.answerRing : Self.rewriteRing, lineWidth: 2)
                            if !reduceMotion {
                                StyleKeySpots().mask(Capsule().strokeBorder(lineWidth: 2))
                            }
                        }
                        .padding(-4)
                        .allowsHitTesting(false)
                    }
                }
                .opacity(locked ? 0.45 : 1)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                Button {
                    answer ? model.askKeyTapped() : model.polishKeyTapped()
                } label: {
                    // 几乎透明的底：完全透明的地方系统不把触摸交给键盘（混色底不接触摸）。
                    PolishButton.touchFill.frame(width: layout.dividerX)
                }
                .accessibilityLabel(running ? L("正在生成，轻点取消", "Working. Tap to cancel", "生成中。タップでキャンセル")
                                    : (answer ? L("问答：回答下面写的问题", "Ask: answer the question below", "質問：下に書いた質問に答える")
                                       : L("润色：按「\(title)」改输入框里的话", "Polish with \(title)", "「\(title)」で整える")))
                .modifier(CoachRunTarget(model: model, enabled: !answer))
                Button {
                    locked ? model.showFullAccessTip() : model.toggleRow(row)
                } label: {
                    PolishButton.touchFill
                }
                .accessibilityLabel((answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル")) + "：" + title)
                .accessibilityValue(open ? L("已展开", "Expanded", "展開中") : L("已收起", "Collapsed", "折りたたみ"))
            }
            .buttonStyle(KeyPressStyle())
        }
        .frame(width: width, height: KeyboardMetrics.chipHeight)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RowChipFrameKey.self, value: [row: geometry.frame(in: .named("keyboard"))])
        })
        // 点按区上下各扩 5pt。
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .padding(.vertical, -5)
    }

    static let rewriteBorder = NebulaFill.color(0xC4B5FD)
    static let answerBorder = NebulaFill.color(0x7DD3FC)
    /// 亮边颜色（AK2）：润色 #a78bfa、问答 #4c8ff8。
    static let rewriteRing = NebulaFill.color(0xA78BFA)
    static let answerRing = NebulaFill.color(0x4C8FF8)

    static let fontSize: CGFloat = 14.5
    static let chevronSize: CGFloat = 12
    /// ⌄ 那块（含竖线右边）的宽，整块都点得中。
    static let chevronZone: CGFloat = 36
    /// 两颗键的宽：放得下时 112pt，不铺满（AK1）。
    static let preferredWidth: CGFloat = 112
    static let minimumWidth: CGFloat = 88

    struct Layout {
        var iconX: CGFloat
        var textX: CGFloat
        var textWidth: CGFloat
        var dividerX: CGFloat
        var chevronX: CGFloat
    }

    /// 一颗键里各部分的位置（键的左边为 0）：竖线左边是图标 + 名字（居中，左边至少留 10），右边 36pt 是 ⌄。AI 栏开收动画也按这个摆。
    static func layout(width: CGFloat, title: String) -> Layout {
        let dividerX = width - chevronZone
        let room = max(0, dividerX - 10 - 20 - 6)
        let textWidth = min(keyTextWidth(title), room)
        let content = 20 + textWidth
        let leading = max(10, (dividerX - content) / 2)
        return Layout(iconX: leading + 8, textX: leading + 20, textWidth: textWidth,
                      dividerX: dividerX, chevronX: dividerX + 1 + (chevronZone - 1) / 2)
    }

    /// 柔和混色底、白字白图标：16pt 图标、14.5pt 600 名字、竖线、12pt ⌄。生成中图标换成白色方块。
    static func face(answer: Bool, title: String, width: CGFloat, open: Bool = false, running: Bool = false, filled: Bool = true) -> some View {
        let h = KeyboardMetrics.chipHeight
        let layout = Self.layout(width: width, title: title)
        return ZStack(alignment: .topLeading) {
            Group {
                if running {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.white).frame(width: 12, height: 12)
                } else {
                    Image(systemName: answer ? "questionmark.circle" : "pencil")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .position(x: layout.iconX, y: h / 2)
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: layout.textWidth, alignment: .leading)
                .position(x: layout.textX + layout.textWidth / 2, y: h / 2)
            chevronDivider
                .position(x: layout.dividerX + 0.5, y: h / 2)
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: chevronSize, weight: .semibold))
                .position(x: layout.chevronX, y: h / 2)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: h, alignment: .topLeading)
        .background {
            if filled { NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()) }
        }
    }

    /// 合成那一颗里风格名的宽（13.5pt），最宽 76，太长截断。
    static func textWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        return min(76, ceil((title as NSString).size(withAttributes: [.font: font]).width))
    }

    /// 润色键、问答键里名字的宽（14.5pt）。
    static func keyTextWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// 名字和 ⌄ 之间的竖线：1×14、白 45%（FB）。
    static var chevronDivider: some View {
        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
    }

    /// AI 栏有多宽时两颗键各多宽：放得下 112，放不下平分剩下的地方，最窄 88（名字截断）。
    static func width(barWidth: CGFloat, fixed: CGFloat) -> CGFloat {
        guard barWidth > 0 else { return preferredWidth }
        return max(minimumWidth, min(preferredWidth, floor((barWidth - fixed) / 2)))
    }

    /// 有结果时，回答卡上是问答就是问答键亮，否则润色键亮（润色、改写都算）。
    private var isActive: Bool {
        guard model.aiExpanded, model.target != .card, let session = model.session, session.current != nil, !model.isRunning else { return false }
        return session.currentIsAnswer == answer
    }

    /// 润色键写当前润色风格的名字；问答键固定写「问答」，不写风格名（KB1）。
    static func title(_ model: KeyboardModel, answer: Bool) -> String {
        if answer { return L("问答", "Ask", "質問") }
        return model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
    }
}

/// 使用指引里「执行」那一步指着润色键的名字（原来指着放大镜）。
private struct CoachRunTarget: ViewModifier {
    @ObservedObject var model: KeyboardModel
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.coachTarget(.run, active: model.coachDisplay?.target == .run)
        } else {
            content
        }
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
