import SwiftUI

/// 键盘主体：顶部一行核心功能（组字时换成候选词），可展开的 AI 面板，下面是按键。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if model.aiExpanded {
                aiPanel
                    .padding(.horizontal, KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX)
                    .padding(.bottom, 4)
            }
            KeysView(model: model)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - 顶部一行

    @ViewBuilder
    private var topRow: some View {
        Group {
            if model.isComposing {
                candidateBar
            } else if model.aiExpanded {
                expandedBar
            } else {
                toolBar
            }
        }
        .frame(height: KeyboardMetrics.topRow)
    }

    /// 平时：✨润色、要求、🎤，右边是风格和布局菜单。
    private var toolBar: some View {
        HStack(spacing: 6) {
            ToolChip(title: model.isRunning ? "停止" : "润色", systemImage: model.isRunning ? "stop.fill" : "sparkles",
                     prominent: true) {
                model.isRunning ? model.stop() : model.sparkleTapped()
            }
            ToolChip(title: "要求", systemImage: "text.bubble") { model.setAIExpanded(true) }
            VoiceChip(model: model)
            if model.voiceState == .recording {
                ToolChip(title: nil, systemImage: "xmark") { model.cancelVoice() }
            }
            Spacer(minLength: 0)
            styleMenu
            if model.session != nil {
                Button { model.setAIExpanded(true) } label: {
                    Image(systemName: "chevron.up").font(.footnote.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .tint(.primary)
            }
        }
        .padding(.horizontal, 8)
    }

    /// 展开后：收起、预设要求、版本切换。
    private var expandedBar: some View {
        HStack(spacing: 6) {
            Button { model.setAIExpanded(false) } label: {
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .tint(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(KeyboardModel.presets, id: \.title) { preset in
                        ToolChip(title: preset.title, systemImage: nil,
                                 prominent: model.instruction == preset.instruction) {
                            model.setInstruction(preset.instruction)
                        }
                    }
                }
            }
            .hidingScrollEdgeEffect()
            if let label = model.versionLabel {
                Button { model.showVersion(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.isRunning || model.session?.currentIndex == 0)
                Text(label).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.showVersion(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.isRunning || model.session.map { $0.currentIndex >= $0.versions.count - 1 } ?? true)
            }
        }
        .tint(.primary)
        .padding(.horizontal, 4)
    }

    /// 组字时：拼音和候选词。
    private var candidateBar: some View {
        HStack(spacing: 0) {
            Text(model.composition)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.candidates.prefix(60).enumerated()), id: \.offset) { index, word in
                        Button { model.selectCandidate(index) } label: {
                            Text(word)
                                .font(.title3)
                                .foregroundStyle(index == 0 ? Color.accentColor : Color.primary)
                                .padding(.horizontal, 8)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .hidingScrollEdgeEffect()
        }
    }

    private var styleMenu: some View {
        Menu {
            Section("键盘布局") {
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
            }
            Section("润色风格") {
                ForEach(model.settings.styles) { style in
                    Button {
                        model.selectStyle(style)
                    } label: {
                        if style.id == model.settings.selectedStyle?.id {
                            Label(style.name, systemImage: "checkmark")
                        } else {
                            Text(style.name)
                        }
                    }
                }
            }
        } label: {
            Label(model.settings.selectedStyle?.name ?? "风格", systemImage: "paintbrush")
                .font(.footnote)
        }
        .tint(.primary)
    }

    // MARK: - AI 面板

    private var aiPanel: some View {
        VStack(spacing: KeyboardMetrics.panelSpacing) {
            preview
            actionRow
            instructionField
        }
    }

    private var preview: some View {
        ScrollView {
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
        .frame(height: KeyboardMetrics.previewHeight)
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemBackground).opacity(0.9)))
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
        switch model.voiceState {
        case .recording:
            if !model.voicePartial.isEmpty { return "正在听：\(model.voicePartial)" }
            return model.voiceMode == .content ? "正在听，说完点「完成」…" : "正在听你的修改要求，说完点「完成」…"
        case .transcribing: return "识别中…"
        default: return "点「执行」润色输入框里的内容。点下面的要求框可以写修改要求；输入框为空时按要求帮你写。"
        }
    }

    private var hasResult: Bool { !model.isRunning && model.session?.current != nil }

    private var actionRow: some View {
        HStack(spacing: 6) {
            PanelButton(title: "替换", systemImage: "arrow.left.arrow.right") { model.replace() }
                .disabled(!hasResult)
            PanelButton(title: "插入", systemImage: "text.insert") { model.insert() }
                .disabled(!hasResult)
            PanelButton(title: "复制", systemImage: "doc.on.doc") { model.copy() }
                .disabled(!hasResult)
            PanelButton(title: "撤销", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
            PanelButton(title: "新会话", systemImage: nil) { model.newSession() }
                .disabled(model.session == nil && !model.isRunning)
        }
        .frame(height: KeyboardMetrics.actionRow)
    }

    /// 要求框：点一下才把键盘的输入切到这里，再点一下切回原输入框。
    private var instructionField: some View {
        let editing = model.target == .instruction
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
                Group {
                    if model.instruction.isEmpty && !(editing && model.isComposing) {
                        Text(editing ? "正在输入修改要求…" : "点这里写修改要求").foregroundStyle(.secondary)
                    } else {
                        (Text(model.instruction)
                            + Text(editing ? model.composition : "").foregroundColor(.secondary).underline()
                            + Text(editing ? "|" : "").foregroundColor(.accentColor))
                            .foregroundStyle(.primary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !model.instruction.isEmpty {
                    Button { model.setInstruction("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor, lineWidth: editing ? 1.5 : 0))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleInstructionEditing() }

            Button {
                model.isRunning ? model.stop() : model.execute()
            } label: {
                Text(model.isRunning ? "停止" : "执行")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 58)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(model.isRunning ? Color.red : Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .frame(height: KeyboardMetrics.instructionRow)
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
        .padding(.horizontal, 10)
        .frame(height: 28)
        .foregroundStyle(foreground ?? (filled ? Color.white : Color.primary))
        .background(Capsule().fill(filled ? tint : KeyStyle.charKey))
    }
}

/// 🎤：短按说内容，长按说要求；录音中再按一下结束。语音会话在线时图标是橙色。
struct VoiceChip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let recording = model.voiceState == .recording
        let busy = model.voiceState == .transcribing
        Group {
            if recording {
                ChipLabel(title: "完成", systemImage: "stop.fill", tint: .red)
            } else if busy {
                ChipLabel(title: "识别中", systemImage: nil)
            } else {
                ChipLabel(title: nil, systemImage: "mic.fill",
                          foreground: model.voiceState == .idle ? nil : .orange)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            if recording {
                model.voiceTapped(model.voiceMode)
            } else if !busy {
                model.voiceTapped(.content)
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !recording, !busy else { return }
            model.voiceTapped(.instruction)
        }
    }
}

/// AI 面板里的小按钮。
struct PanelButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KeyStyle.charKey))
        }
        .buttonStyle(KeyPressStyle())
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
