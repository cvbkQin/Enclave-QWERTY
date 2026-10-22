import SwiftUI

/// 键盘主体。
/// 收起时：顶部一行（润色、展开、话筒；打拼音时换成候选词），下面是按键。
/// 展开时：预览行（左润色、右话筒）、操作行（打拼音时换成候选词）、要求行，下面是按键。
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

    private var toolBar: some View {
        HStack(spacing: 6) {
            ToolChip(title: model.isRunning ? "停止" : "润色", systemImage: model.isRunning ? "stop.fill" : "sparkles",
                     prominent: true) {
                model.isRunning ? model.stop() : model.sparkleTapped()
            }
            ToolChip(title: nil, systemImage: "chevron.up") { model.setAIExpanded(true) }
            Spacer(minLength: 0)
            if model.voiceState == .recording {
                ToolChip(title: nil, systemImage: "xmark") { model.cancelVoice() }
            }
            VoiceChip(model: model)
        }
        .padding(.horizontal, 8)
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

    /// 预览行：左边润色，中间结果，右边话筒。
    private var previewRow: some View {
        HStack(spacing: 6) {
            SideButton(title: model.isRunning ? "停止" : "润色",
                       systemImage: model.isRunning ? "stop.fill" : "sparkles",
                       fill: model.isRunning ? .red : .accentColor, foreground: .white) {
                model.isRunning ? model.stop() : model.execute()
            }
            preview
            VoiceSideButton(model: model)
        }
        .frame(minHeight: KeyboardMetrics.minPreviewHeight, maxHeight: KeyboardMetrics.previewHeight)
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
            .padding(.trailing, model.versionLabel == nil ? 0 : 52)
        }
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemBackground).opacity(0.9)))
        .overlay(alignment: .topTrailing) { previewBadges }
    }

    /// 预览框右上角：版本切换；录音时是取消。
    @ViewBuilder
    private var previewBadges: some View {
        if model.voiceState == .recording {
            Button { model.cancelVoice() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        } else if let label = model.versionLabel {
            HStack(spacing: 2) {
                Button { model.showVersion(offset: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 18, height: 22)
                }
                .disabled(model.isRunning || model.session?.currentIndex == 0)
                Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.showVersion(offset: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 18, height: 22)
                }
                .disabled(model.isRunning || model.session.map { $0.currentIndex >= $0.versions.count - 1 } ?? true)
            }
            .font(.caption.weight(.semibold))
            .tint(.primary)
            .padding(.trailing, 2)
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
        switch model.voiceState {
        case .recording:
            if !model.voicePartial.isEmpty { return "正在听：\(model.voicePartial)" }
            return model.voiceMode == .content ? "正在听，说完点「完成」…" : "正在听你的修改要求，说完点「完成」…"
        case .transcribing: return "识别中…"
        default: return "点左边「润色」整理输入框里的内容。下面可以写要求或选一个常用要求；长按「执行」用语音说要求。"
        }
    }

    private var hasResult: Bool { !model.isRunning && model.session?.current != nil }

    /// 操作行：替换、插入、复制、撤销、新会话，最右边是风格和布局菜单。
    private var actionRow: some View {
        HStack(spacing: 5) {
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
            styleMenu
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
            HStack(spacing: 3) {
                Image(systemName: "paintbrush")
                Text(model.settings.selectedStyle?.name ?? "风格").lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KeyStyle.charKey))
        }
    }

    /// 要求行：左边收起，中间是可左右滑动的要求标签，右边执行（长按用语音说要求）。
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

            ExecuteButton(model: model)
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
        // 只有图标的按钮是正圆，带字的是胶囊。
        .padding(.horizontal, title == nil ? 0 : 10)
        .frame(minWidth: 30)
        .frame(height: 30)
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

/// 预览框右边的话筒：单击说内容，录音中再点一下结束。会话在线时图标是橙色。
struct VoiceSideButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let recordingContent = model.voiceState == .recording && model.voiceMode == .content
        Group {
            if recordingContent {
                SideButtonLabel(title: "完成", systemImage: "stop.fill", fill: .red, foreground: .white)
            } else if model.voiceState == .transcribing && model.voiceMode == .content {
                SideButtonLabel(title: "识别中", systemImage: "ellipsis", fill: KeyStyle.charKey)
            } else {
                SideButtonLabel(title: "说话", systemImage: "mic.fill", fill: KeyStyle.charKey,
                                foreground: model.voiceState == .idle ? .primary : .orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            switch model.voiceState {
            case .recording: model.voiceTapped(model.voiceMode)
            case .transcribing: break
            default: model.voiceTapped(.content)
            }
        }
    }
}

/// 执行键：单击执行，长按用语音说要求；说要求时变成红色「完成」，再点一下结束。
struct ExecuteButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let recordingInstruction = model.voiceState == .recording && model.voiceMode == .instruction
        let busy = model.voiceState == .transcribing && model.voiceMode == .instruction
        HStack(spacing: 3) {
            if recordingInstruction {
                Image(systemName: "stop.fill").font(.caption)
                Text("完成")
            } else if busy {
                Text("识别中")
            } else {
                Text(model.isRunning ? "停止" : "执行")
                Image(systemName: "mic.fill").font(.system(size: 9)).opacity(0.8)
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(width: 62, height: KeyboardMetrics.instructionRow)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(recordingInstruction || model.isRunning ? Color.red : Color.accentColor))
        .contentShape(Rectangle())
        .onTapGesture {
            if recordingInstruction {
                model.voiceTapped(.instruction)
            } else if model.isRunning {
                model.stop()
            } else if !busy {
                model.execute()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard model.voiceState != .recording, !busy, !model.isRunning else { return }
            model.keyFeedback(for: .space)
            model.voiceTapped(.instruction)
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
