import SwiftUI

// MARK: - AI 栏的两颗风格键（MG1–MG5）

/// 改写风格键、问答风格键（AB2）：展开时才有，紫色 / 蓝色星团底、白字白图标。
/// 回答卡上是哪一种结果，那一颗就激活：1.5pt 浅色边框、两小段白光沿边框转（3 秒一圈）、外面一圈 10pt 的光。
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
                // 激活：外面一圈 10pt 光，润色 rgba(124,58,237,.55)、直击要害 rgba(14,165,233,.55)。
                if active {
                    Capsule().fill(answer ? Self.answerGlow : Self.rewriteGlow).padding(-3).blur(radius: 5)
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
                Color.clear.preference(key: RowChipEdgeKey.self, value: [row: geometry.frame(in: .named("keyboard")).midX])
            })
            // 点按区上下各扩 5pt。
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel((answer ? L("问答风格", "Answer style", "回答スタイル") : L("改写风格", "Rewrite style", "書き換えスタイル")) + "：" + Self.title(model, answer: answer))
        .accessibilityValue(open ? L("已展开", "Expanded", "展開中") : L("已收起", "Collapsed", "折りたたみ"))
    }

    static let rewriteBorder = NebulaFill.color(0xC4B5FD)
    static let answerBorder = NebulaFill.color(0x7DD3FC)
    static let rewriteGlow = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255).opacity(0.55)
    static let answerGlow = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255).opacity(0.55)

    /// 星团底、白字白图标（AB2）：高 34、左内边 9、右内边 8；15pt 图标、13.5pt 600 风格名（最宽 76）、10pt ▾。
    /// 宽度按字算死，AI 栏分裂动画里画的那几颗和这里一样宽。
    static func face(answer: Bool, title: String, open: Bool = false, filled: Bool = true) -> some View {
        HStack(spacing: 4) {
            Image(systemName: answer ? "questionmark.circle" : "pencil")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: textWidth(title))
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 10)
        }
        .foregroundStyle(.white)
        .padding(.leading, 9)
        .padding(.trailing, 8)
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

    /// 整颗的宽：9 + 图标 16 + 4 + 字 + 4 + ▾ 10 + 8。
    static func width(_ title: String) -> CGFloat { 51 + textWidth(title) }

    /// 展开、有结果时，回答卡上是问答就激活问答那颗，否则激活改写那颗（润色也算改写）。
    private var isActive: Bool {
        guard model.aiExpanded, model.target != .card, let session = model.session, session.current != nil else { return false }
        return session.currentIsAnswer == answer
    }

    static func title(_ model: KeyboardModel, answer: Bool) -> String {
        if answer {
            return model.settings.selectedAnswerStyle?.displayName ?? L("直击要害", "To the point", "要点だけ")
        }
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

/// 两颗风格键的中线（键盘坐标），尖角按它对齐。
struct RowChipEdgeKey: PreferenceKey {
    static var defaultValue: [KeyboardModel.AIRow: CGFloat] = [:]
    static func reduce(value: inout [KeyboardModel.AIRow: CGFloat], nextValue: () -> [KeyboardModel.AIRow: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - 往上展开的那一行（QA2、QA14）

/// 抽屉收着时点风格键：整宽、高 42、圆角 12 的白框（深色 #4A4A4C），1.5pt 模式色内描边；底边伸出一个小尖角对准下面那颗键。
struct AIRowPanel: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    /// 尖角中心在这一行里的横坐标。
    var arrowX: CGFloat

    var body: some View {
        StyleRow(model: model, row: row)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AIRowBubble(arrowX: arrowX).fill(Brand.rowFill))
            .overlay(AIRowBubble(arrowX: arrowX, inset: 0.75)
                .stroke(row == .answerStyles ? Brand.answerBorder : Brand.rewriteRing, lineWidth: 1.5).allowsHitTesting(false))
    }
}

/// 圆角矩形加底边的小尖角：宽 20、高 7.5，两侧平滑曲线、尖端圆润，左右两端水平切入底边。
/// 尖角画在框外面（框高还是 42），填充和描边都是同一条路径，看起来是框长出来的。
struct AIRowBubble: Shape {
    var arrowX: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = 12 - inset
        let half: CGFloat = 10, height: CGFloat = 7.5 - inset
        let x = min(max(arrowX, r.minX + radius + half), r.maxX - radius - half)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - radius, y: r.maxY), radius: radius)
        // 底边从右往左，到尖角处鼓出去。
        let b = r.maxY
        path.addLine(to: CGPoint(x: x + half, y: b))
        path.addCurve(to: CGPoint(x: x + 1.8, y: b + height - 0.9),
                      control1: CGPoint(x: x + 5, y: b), control2: CGPoint(x: x + 3.4, y: b + height - 2.6))
        path.addQuadCurve(to: CGPoint(x: x - 1.8, y: b + height - 0.9), control: CGPoint(x: x, y: b + height + 0.9))
        path.addCurve(to: CGPoint(x: x - half, y: b),
                      control1: CGPoint(x: x - 3.4, y: b + height - 2.6), control2: CGPoint(x: x - 5, y: b))
        path.addLine(to: CGPoint(x: r.minX + radius, y: b))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: b), tangent2End: CGPoint(x: r.minX, y: b - radius), radius: radius)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + radius, y: r.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}

// MARK: - 风格一排（MG5）

/// 一排风格小块横向可滑（左右内边 6、间距 6），右边 12% 渐隐；最右固定一个 28×28「＋」去 App 加。
/// 点小块只换下一次用的风格，不重新调用接口；展开时选完换回识意框。
struct StyleRow: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow

    private var answer: Bool { row == .answerStyles }

    var body: some View {
        let styles = answer ? model.settings.answerStyles : model.settings.styles
        let selectedID = answer ? model.settings.selectedAnswerStyle?.id : model.settings.selectedStyle?.id
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(styles) { style in
                            PromptTag(title: style.displayName, selected: style.id == selectedID, answer: answer) {
                                answer ? model.selectAnswerStyle(style) : model.selectStyle(style)
                            }
                            .id(style.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .hidingScrollEdgeEffect()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                             .init(color: .black.opacity(0), location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .onAppear {
                    if let selectedID { reader.scrollTo(selectedID, anchor: .center) }
                }
            }
            Button { model.openContainingApp(answer ? "enclave://prompts-answer" : "enclave://prompts") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.askClearIcon)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.tagFill))
            }
            .buttonStyle(KeyPressStyle())
            .padding(.trailing, 6)
            .accessibilityLabel(answer ? L("添加问答风格", "Add answer style", "回答スタイルを追加") : L("管理提示词", "Manage prompts", "プロンプトを管理"))
        }
    }
}

/// 风格小块：高 28、圆角 8、左右内边 10、14pt。没选 tagBg 底；当前那条模式色底、1pt 模式色内描边、粗体字、前面 12pt 勾。
struct PromptTag: View {
    var title: String
    var selected: Bool
    var answer = false
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(selected ? (answer ? Brand.modeAnswerText : Brand.chipOpenText) : Brand.tagLabel)
            .background(shape.fill(selected ? (answer ? Brand.modeAnswerFill : Brand.chipOpenFill) : Brand.tagFill))
            .overlay(shape.strokeBorder(answer ? Brand.answerBorder : Brand.rowStroke, lineWidth: selected ? 1 : 0))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
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
                .foregroundStyle(Brand.askPlaceholder)
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
                .foregroundStyle(Brand.askText)
                .lineLimit(1)
                .truncationMode(atEnd ? .head : .tail)
        }
    }

    private func caretImage(_ visible: Bool) -> some View {
        Image(uiImage: Self.caret).foregroundStyle(Brand.askCaret.opacity(visible ? 1 : 0))
    }
}
