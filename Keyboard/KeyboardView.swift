import SwiftUI

/// 键盘主体。
/// 收起时：顶部一行（展开、润色；打拼音时换成候选词），下面是按键。
/// 展开时：预览行（左润色、右结果）、操作行（打拼音时换成候选词）、要求行，下面是按键。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            if model.aiExpanded {
                aiPanel
                    .padding(.horizontal, KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX)
                    .padding(.top, KeyboardMetrics.panelTop)
                    .padding(.bottom, KeyboardMetrics.panelSpacing)
            } else {
                Group {
                    if model.isComposing {
                        candidateBar
                    } else {
                        toolBar
                    }
                }
                .frame(height: KeyboardMetrics.topRow)
            }
            KeysView(model: model)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
                .layoutPriority(1)
        }
        // 系统给的高度不够时先压缩预览行，再从顶上裁，按键始终完整贴在底部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    // MARK: - 收起时的顶栏

    /// 展开键在最左边，和展开后要求行里的收起键位置、大小完全一样。
    private var toolBar: some View {
        HStack(spacing: 6) {
            PanelToggleButton(expanded: false) { model.setAIExpanded(true) }
            ToolChip(title: model.isRunning ? "停止" : "润色", systemImage: model.isRunning ? "stop.fill" : "sparkles",
                     prominent: true) {
                model.isRunning ? model.stop() : model.sparkleTapped()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX)
        .padding(.bottom, KeyboardMetrics.panelSpacing)
        .frame(maxHeight: .infinity, alignment: .bottom)
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
                                .foregroundStyle(Color.primary)
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

    // MARK: - AI 面板

    private var aiPanel: some View {
        VStack(spacing: KeyboardMetrics.panelSpacing) {
            previewRow
            Group {
                if model.isComposing {
                    candidateBar
                } else {
                    actionRow
                }
            }
            .frame(height: KeyboardMetrics.actionRow)
            requirementRow
        }
    }

    /// 预览行：左边润色，右边结果。
    private var previewRow: some View {
        HStack(spacing: 6) {
            SideButton(title: model.isRunning ? "停止" : "润色",
                       systemImage: model.isRunning ? "stop.fill" : "sparkles",
                       fill: model.isRunning ? .red : .accentColor, foreground: .white) {
                model.isRunning ? model.stop() : model.execute()
            }
            preview
        }
        .frame(minHeight: KeyboardMetrics.minPreviewHeight, maxHeight: KeyboardMetrics.previewHeight)
    }

    private var preview: some View {
        VersionPager(model: model) {
            VStack(alignment: .leading, spacing: 4) {
                setupHint
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else if let notice = model.notice, model.displayText.isEmpty {
                    Text(notice).foregroundStyle(.secondary)
                }
                if model.displayText.isEmpty && model.errorMessage == nil && model.notice == nil {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.displayText)
                        .foregroundStyle(.primary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // 长按结果复制，不单独放复制按钮。
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in model.copy() })
        .overlay {
            if model.copiedFlash {
                Label("已复制", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 没开完全访问或没配置 API 时的提示，放在预览区里，不额外占高度。
    @ViewBuilder
    private var setupHint: some View {
        if !model.hasFullAccess {
            Text("请到 设置 › 通用 › 键盘 › 键盘 › Enclave，打开「允许完全访问」。")
                .foregroundStyle(.orange)
        } else if !model.settings.isConfigured {
            HStack {
                Text("还没有配置 API").foregroundStyle(.orange)
                Spacer()
                Button("从剪贴板导入配置") { model.importConfigFromPasteboard() }
            }
        }
    }

    private var placeholder: String {
        if model.isRunning { return "生成中…" }
        return "点左边「润色」整理输入框里的内容。下面选风格或写要求。结果出来后长按可复制。"
    }

    private var hasResult: Bool { !model.isRunning && model.session?.current != nil }

    /// 操作行：替换（最常用，实心主色）、插入（描边）、撤销/重做（一组）、新会话，最右边是布局菜单。
    /// 复制改成长按预览。
    private var actionRow: some View {
        HStack(spacing: 5) {
            PanelButton(title: "替换", systemImage: "arrow.left.arrow.right", kind: .primary) { model.replace() }
                .disabled(!hasResult)
            PanelButton(title: "插入", systemImage: "text.insert", kind: .outlined) { model.insert() }
                .disabled(!hasResult)
            UndoRedoPair(model: model)
            PanelButton(title: "新会话", systemImage: nil) { model.newSession() }
                .disabled(model.session == nil && !model.isRunning)
            layoutMenu
                .frame(width: 40)
        }
    }

    /// 键盘布局切换（风格改成了要求行里的标签）。
    private var layoutMenu: some View {
        Menu {
            ForEach(KeyboardLayout.allCases) { layout in
                Button {
                    model.setLayout(layout)
                } label: {
                    if layout == model.settings.keyboardLayout {
                        Label(layout.title, systemImage: "checkmark")
                    } else {
                        Text(layout.title)
                    }
                }
            }
        } label: {
            Image(systemName: "keyboard")
                .font(.footnote)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KeyStyle.charKey))
        }
    }

    /// 要求行：左边收起，中间可左右滑动——先是风格标签（单选），一条细线隔开，再是写要求；右边执行。
    /// 已有结果时，点风格会立刻生成新的一版，可以上下滑回之前的版本。
    private var requirementRow: some View {
        HStack(spacing: 6) {
            PanelToggleButton(expanded: true) { model.setAIExpanded(false) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.settings.styles) { style in
                        StyleTag(title: style.name, selected: style.id == model.settings.selectedStyle?.id) {
                            model.styleTagTapped(style)
                        }
                    }
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)
                    customRequirementChip
                }
            }
            .hidingScrollEdgeEffect()

            ExecuteButton(model: model)
        }
        .frame(height: KeyboardMetrics.instructionRow)
    }

    /// 自己写的要求。
    private var customRequirementChip: some View {
        let editing = model.target == .instruction
        let custom = model.instruction
        let showsText = !custom.isEmpty || (editing && model.isComposing)
        return HStack(spacing: 4) {
            Image(systemName: "pencil")
            if showsText {
                (Text(custom)
                    + Text(editing ? model.composition : "").foregroundColor(.secondary).underline()
                    + Text(editing ? "|" : "").foregroundColor(.accentColor))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 180, alignment: .leading)
                    .fixedSize(horizontal: custom.count < 12, vertical: false)
            } else {
                Text(editing ? "输入要求…" : "写要求").foregroundStyle(editing ? Color.secondary : Color.primary)
            }
            if !custom.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture { model.setInstruction("") }
            }
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .frame(height: KeyboardMetrics.chipHeight)
        .foregroundStyle(Color.primary)
        .background(Capsule().fill(KeyStyle.charKey))
        .overlay(Capsule().stroke(Color.accentColor, lineWidth: editing ? 1.5 : 0))
        .contentShape(Capsule())
        .onTapGesture { model.toggleInstructionEditing() }
    }
}

/// 展开/收起 AI 面板的键。收起时在顶栏最左边，展开时在要求行最左边，两处的位置和大小一样。
struct PanelToggleButton: View {
    var expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: KeyboardMetrics.chipHeight, height: KeyboardMetrics.chipHeight)
                .foregroundStyle(Color.primary)
                .background(Circle().fill(KeyStyle.charKey))
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 风格标签：选中时是描边加粗的胶囊，和下面的常用要求（实心）区分开。
struct StyleTag: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .frame(height: KeyboardMetrics.chipHeight)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.15) : KeyStyle.charKey))
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: selected ? 1.2 : 0))
        }
        .buttonStyle(.plain)
    }
}

/// 顶部一行的胶囊按钮。
struct ToolChip: View {
    var title: String?
    var systemImage: String?
    var prominent = false
    var tint: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, systemImage: systemImage, prominent: prominent, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct ChipLabel: View {
    var title: String?
    var systemImage: String?
    var prominent = false
    var tint: Color = .accentColor
    var foreground: Color?

    var body: some View {
        let filled = prominent || tint != .accentColor
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            if let title { Text(title) }
        }
        .font(.footnote.weight(prominent ? .semibold : .regular))
        // 只有图标的按钮是正圆，带字的是胶囊；和展开键一样高。
        .padding(.horizontal, title == nil ? 0 : 12)
        .frame(minWidth: KeyboardMetrics.chipHeight)
        .frame(height: KeyboardMetrics.chipHeight)
        .foregroundStyle(foreground ?? (filled ? Color.white : Color.primary))
        .background(Capsule().fill(filled ? tint : KeyStyle.charKey))
    }
}

/// AI 面板里的小按钮。primary 是实心主色（替换），outlined 是主色描边（插入），plain 是普通按键色。
struct PanelButton: View {
    enum Kind { case plain, primary, outlined }

    var title: String
    var systemImage: String?
    var kind: Kind = .plain
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: action) {
            HStack(spacing: 3) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(kind == .plain ? .footnote : .footnote.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground)
            .background(shape.fill(kind == .primary ? Color.accentColor.opacity(isEnabled ? 1 : 0.35) : KeyStyle.charKey))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(isEnabled ? 0.9 : 0.3),
                                        lineWidth: kind == .outlined ? 1.2 : 0))
        }
        .buttonStyle(KeyPressStyle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return isEnabled ? .white : .white.opacity(0.8)
        case .outlined: return isEnabled ? .accentColor : .secondary
        case .plain: return isEnabled ? .primary : .secondary
        }
    }
}

/// 撤销和重做拼成一个按钮，中间一条细线。
struct UndoRedoPair: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 0) {
            half("arrow.uturn.backward", enabled: model.canUndo) { model.undo() }
            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).padding(.vertical, 7)
            half("arrow.uturn.forward", enabled: model.canRedo) { model.redo() }
        }
        .frame(width: 76)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KeyStyle.charKey))
    }

    private func half(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
    }
}

/// 预览框两边的竖按钮。
struct SideButton: View {
    var title: String
    var systemImage: String
    var fill: Color
    var foreground: Color = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SideButtonLabel(title: title, systemImage: systemImage, fill: fill, foreground: foreground)
        }
        .buttonStyle(KeyPressStyle())
    }
}

struct SideButtonLabel: View {
    var title: String?
    var systemImage: String
    var fill: Color
    var foreground: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
            if let title { Text(title).font(.caption2.weight(.semibold)) }
        }
        .foregroundStyle(foreground)
        .frame(width: 46)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
    }
}

/// 执行键：单击执行，生成中再点一下停止。
struct ExecuteButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Text(model.isRunning ? "停止" : "执行")
            .font(.subheadline.weight(.semibold))
            .frame(width: 62, height: KeyboardMetrics.instructionRow)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.isRunning ? Color.red : Color.accentColor))
            .contentShape(Rectangle())
            .onTapGesture {
                model.isRunning ? model.stop() : model.execute()
            }
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

/// 预览框：多个版本像一叠卡片，上下滑动翻页（上滑看下一版，下滑看上一版），右边竖排页码。
/// 文字超出一屏时卡片内部先滚动，这时用右边的页码条滑动或点箭头翻页。
struct VersionPager<Content: View>: View {
    @ObservedObject var model: KeyboardModel
    var content: Content

    init(model: KeyboardModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    @State private var drag: CGFloat = 0
    /// 1 表示翻到下一版（新卡片从下面上来），-1 表示上一版。
    @State private var direction = 1
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var count: Int { model.session?.versions.count ?? 0 }
    private var index: Int { model.session?.currentIndex ?? 0 }
    private var paging: Bool { count > 1 && !model.isRunning }
    private var fits: Bool { contentHeight <= viewportHeight + 1 }

    var body: some View {
        HStack(spacing: 0) {
            card
            if paging { indicator }
        }
        .background(alignment: .bottom) { stackEdge }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemBackground).opacity(0.9)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 当前版本的文字，翻页时整张卡片滑走、下一张滑进来。
    private var card: some View {
        GeometryReader { outer in
            ScrollView {
                content
                    .background(GeometryReader { inner in
                        Color.clear.preference(key: ContentHeightKey.self, value: inner.size.height)
                    })
            }
            .hidingScrollEdgeEffect()
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            .onAppear { viewportHeight = outer.size.height }
            .onChange(of: outer.size.height) { viewportHeight = $0 }
        }
        .id(index)
        .transition(.asymmetric(
            insertion: .move(edge: direction > 0 ? .bottom : .top).combined(with: .opacity),
            removal: .move(edge: direction > 0 ? .top : .bottom).combined(with: .opacity)))
        .offset(y: drag)
        .contentShape(Rectangle())
        // 文字一屏放得下时，整张卡片都能上下滑翻页。
        .simultaneousGesture(swipe, including: fits && paging ? .all : .subviews)
    }

    /// 右边竖排的「↑ 2/3 ↓」，本身也能上下滑。
    private var indicator: some View {
        VStack(spacing: 0) {
            Button { turn(-1) } label: {
                Image(systemName: "chevron.up").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(index == 0)
            VStack(spacing: 0) {
                Text("\(index + 1)")
                Rectangle().frame(width: 10, height: 1).opacity(0.4)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            Button { turn(1) } label: {
                Image(systemName: "chevron.down").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(index >= count - 1)
        }
        .font(.system(size: 11, weight: .semibold))
        .tint(.primary)
        .frame(width: 26)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.05))
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    /// 后面还有版本时，卡片底下露出一条边，像一叠卡片。
    @ViewBuilder
    private var stackEdge: some View {
        if paging && index < count - 1 {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(height: 6)
                .padding(.horizontal, 6)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let dy = value.translation.height
                // 到头了就只拉动一点，像系统的回弹。
                let atEdge = (dy < 0 && index >= count - 1) || (dy > 0 && index == 0)
                drag = atEdge ? dy / 4 : dy / 2
            }
            .onEnded { value in
                let dy = value.predictedEndTranslation.height
                if dy < -40 && index < count - 1 {
                    turn(1)
                } else if dy > 40 && index > 0 {
                    turn(-1)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
            }
    }

    private func turn(_ offset: Int) {
        direction = offset
        model.keyFeedback(for: .space)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            drag = 0
            model.showVersion(offset: offset)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
