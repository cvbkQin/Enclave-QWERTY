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
            ToolChip(title: "要求", systemImage: "text.bubble",
                     prominent: model.target == .instruction) {
                // 已展开时直接进入要求输入；没展开时先展开面板。
                model.aiExpanded ? model.toggleInstructionEditing() : model.setAIExpanded(true)
            }
            VoiceChip(model: model)
            if model.voiceState == .recording {
                ToolChip(title: nil, systemImage: "xmark") { model.cancelVoice() }
            }
            Spacer(minLength: 0)
            if model.aiExpanded {
                versionControls
            }
            styleMenu
            if model.session != nil && !model.aiExpanded {
                Button { model.setAIExpanded(true) } label: {
                    Image(systemName: "chevron.up").font(.footnote.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .tint(.primary)
            }
        }
        .padding(.horizontal, 8)
    }

    /// 展开后在顶栏右边切换版本。
    @ViewBuilder
    private var versionControls: some View {
        if let label = model.versionLabel {
            HStack(spacing: 4) {
                Button { model.showVersion(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.isRunning || model.session?.currentIndex == 0)
                Text(label).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.showVersion(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.isRunning || model.session.map { $0.currentIndex >= $0.versions.count - 1 } ?? true)
            }
            .font(.footnote.weight(.semibold))
            .tint(.primary)
        }
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
            requirementRow
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
        default: return "点「执行」润色输入框里的内容。点下面的「写要求」自己写，或选一个常用要求；输入框为空时按要求帮你写。"
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

    /// 要求行：左边收起，中间是可左右滑动的要求标签，右边执行。
    /// 第一个标签是自己写的要求，点一下键盘就打进这里；后面是常用要求，点一下直接选用。
    private var requirementRow: some View {
        HStack(spacing: 6) {
            Button { model.setAIExpanded(false) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: KeyboardMetrics.instructionRow)
                    .foregroundStyle(Color.primary)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KeyStyle.functionKey))
            }
            .buttonStyle(KeyPressStyle())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    customRequirementChip
                    ForEach(KeyboardModel.presets, id: \.title) { preset in
                        ToolChip(title: preset.title, systemImage: nil,
                                 prominent: model.instruction == preset.instruction) {
                            model.selectPreset(preset.instruction)
                        }
                    }
                }
            }
            .hidingScrollEdgeEffect()

            Button {
                model.isRunning ? model.stop() : model.execute()
            } label: {
                Text(model.isRunning ? "停止" : "执行")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 54, height: KeyboardMetrics.instructionRow)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(model.isRunning ? Color.red : Color.accentColor))
            }
            .buttonStyle(KeyPressStyle())
        }
        .frame(height: KeyboardMetrics.instructionRow)
    }

    /// 自己写的要求。选中常用要求时这里不重复显示。
    private var customRequirementChip: some View {
        let editing = model.target == .instruction
        let custom = KeyboardModel.presets.contains { $0.instruction == model.instruction } ? "" : model.instruction
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
        .frame(height: 28)
        .foregroundStyle(Color.primary)
        .background(Capsule().fill(KeyStyle.charKey))
        .overlay(Capsule().stroke(Color.accentColor, lineWidth: editing ? 1.5 : 0))
        .contentShape(Capsule())
        .onTapGesture { model.toggleInstructionEditing() }
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
