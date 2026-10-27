import SwiftUI

// MARK: - AI 栏的两颗功能按钮（QA1）

/// 「润色 ▴」「识意 ▴」：高 34、圆角 17、左内边 13 右内边 9；文字 14pt，中间 1×16 细竖线，右边 13pt 箭头。
/// 收起时箭头朝上（往上展开），展开时朝下，整颗选中态：浅紫底、深紫字、1.5pt #8B7CF6 内描边。
/// 「润色」位置显示当前提示词名，太长截断。
struct RowChip: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow

    var body: some View {
        let locked = !model.hasFullAccess
        let open = !locked && model.aiRow == row
        Button { locked ? model.showFullAccessTip() : model.toggleRow(row) } label: {
            HStack(spacing: 0) {
                // 提示词名太长时截断，整颗按内容宽度，不往两边撑。
                Text(title).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: row == .prompts ? 70 : nil)
                // 只是视觉上分开，整颗还是一个按钮；线和箭头不参与截断。
                Rectangle()
                    .fill(open ? Brand.rowStroke : Brand.chipLine)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 8)
                    .layoutPriority(1)
                Image(systemName: open ? "chevron.down" : "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .layoutPriority(1)
            }
            .font(.system(size: 14, weight: open ? .semibold : .regular))
            .padding(.leading, 13)
            .padding(.trailing, 9)
            .frame(height: KeyboardMetrics.chipHeight)
            .foregroundStyle(open ? Brand.chipOpenText : Color.primary)
            .background(Capsule().fill(open ? Brand.chipOpenFill : KeyStyle.charKey))
            .overlay(Capsule().strokeBorder(Brand.rowStroke, lineWidth: open ? 1.5 : 0))
            .opacity(locked ? 0.45 : 1)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: RowChipEdgeKey.self, value: [row: geometry.frame(in: .named("keyboard")).maxX])
            })
            // 点按区上下各扩 5pt。
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .accessibilityValue(open ? L("已展开", "Expanded", "展開中") : L("已收起", "Collapsed", "折りたたみ"))
    }

    private var title: String {
        switch row {
        case .prompts: return model.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
        case .ask: return L("识意", "Ask", "たずねる")
        }
    }
}

/// 两颗功能按钮的右边缘（键盘坐标）。
struct RowChipEdgeKey: PreferenceKey {
    static var defaultValue: [KeyboardModel.AIRow: CGFloat] = [:]
    static func reduce(value: inout [KeyboardModel.AIRow: CGFloat], nextValue: () -> [KeyboardModel.AIRow: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - 往上展开的那一行（QA2、QA14）

/// 整宽、高 42、圆角 12 的白框（深色 #4A4A4C），1.5pt #8B7CF6 内描边；底边伸出一个小尖角对准下面那颗按钮的箭头。
struct AIRowPanel: View {
    @ObservedObject var model: KeyboardModel
    let row: KeyboardModel.AIRow
    /// 尖角中心在这一行里的横坐标。
    var arrowX: CGFloat

    var body: some View {
        Group {
            switch row {
            case .prompts: PromptRow(model: model)
            case .ask: AskField(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AIRowBubble(arrowX: arrowX).fill(Brand.rowFill))
        .overlay(AIRowBubble(arrowX: arrowX, inset: 0.75).stroke(Brand.rowStroke, lineWidth: 1.5).allowsHitTesting(false))
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

// MARK: - 「润色 ▾」：提示词标签

/// 一排提示词标签横向可滑（左右内边 6、间距 6），右边 12% 渐隐；最右固定一个 30×30「+」去 App 管理提示词。
/// 点标签只切换当前提示词，这一行不收起；✨ 按它执行。
struct PromptRow: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.settings.styles) { style in
                            PromptTag(title: style.displayName, selected: style.id == model.settings.selectedStyle?.id) {
                                model.selectStyle(style)
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
                    if let id = model.settings.selectedStyle?.id { reader.scrollTo(id, anchor: .center) }
                }
            }
            Button { model.openContainingApp("enclave://prompts") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.askClearIcon)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.tagFill))
            }
            .buttonStyle(KeyPressStyle())
            .padding(.trailing, 6)
            .accessibilityLabel(L("管理提示词", "Manage prompts", "プロンプトを管理"))
        }
    }
}

/// 提示词标签：高 30、圆角 8、左右内边 12、14pt。没选浅灰底；当前那条浅紫底、1pt #8B7CF6 内描边、深紫粗体字、前面 12pt 勾。
struct PromptTag: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(selected ? Brand.chipOpenText : Brand.tagLabel)
            .background(shape.fill(selected ? Brand.chipOpenFill : Brand.tagFill))
            .overlay(shape.strokeBorder(Brand.rowStroke, lineWidth: selected ? 1 : 0))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 「识意 ▾」：问问题或提要求

/// 识意框（QA14、QA3、QA4）：左内边 14、15pt 字，一行；右端 24×24 圆形 ×，只收起不清空。
/// 展开后键盘打的字进这里，打拼音时候选栏照常出在 AI 栏；重新展开时整段全选，直接打字覆盖。
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
            Button { model.closeAskRow() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.askClearIcon)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Brand.askClearFill))
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("收起", "Close", "閉じる"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 3)
        .font(.system(size: 15))
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
