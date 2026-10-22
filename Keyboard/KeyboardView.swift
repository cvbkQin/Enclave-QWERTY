import SwiftUI

/// 键盘主体：顶部一行核心功能（组字时换成候选词），可展开的 AI 面板，下面是按键。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            topRow
            if model.aiExpanded {
                aiPanel
            }
            KeysView(model: model)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 4)
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
        .frame(height: 36)
    }

    /// 平时：✨润色、要求、语音状态、风格。
    private var toolBar: some View {
        HStack(spacing: 8) {
            ToolChip(title: model.isRunning ? "停止" : "润色", systemImage: model.isRunning ? "stop.fill" : "sparkles",
                     prominent: true) {
                model.isRunning ? model.stop() : model.sparkleTapped()
            }
            ToolChip(title: "要求", systemImage: "text.bubble") { model.setAIExpanded(true) }
            if model.voiceState == .recording {
                ToolChip(title: "完成", systemImage: "stop.fill", tint: .red) { model.voiceTapped(model.voiceMode) }
                ToolChip(title: nil, systemImage: "xmark") { model.cancelVoice() }
            }
            Spacer(minLength: 0)
            voiceStatus
            styleMenu
            if model.session != nil {
                Button { model.setAIExpanded(true) } label: {
                    Image(systemName: "chevron.up").font(.footnote.weight(.semibold))
                }
                .tint(.primary)
            }
        }
        .padding(.horizontal, 4)
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

    // 麦克风会话是否在线：在线时点 🎤 直接录音，不在线会先跳到 App。
    private var voiceStatus: some View {
        Image(systemName: model.voiceState == .idle ? "mic.slash" : "mic.fill")
            .font(.footnote)
            .foregroundStyle(model.voiceState == .idle ? Color.secondary : Color.orange)
    }

    private var styleMenu: some View {
        Menu {
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
        } label: {
            Label(model.settings.selectedStyle?.name ?? "风格", systemImage: "paintbrush")
                .font(.footnote)
        }
        .tint(.primary)
    }

    // MARK: - AI 面板

    private var aiPanel: some View {
        VStack(spacing: 6) {
            banner
            preview
            actionRow
            instructionField
        }
    }

    @ViewBuilder
    private var banner: some View {
        if !model.hasFullAccess {
            Text("请到 设置 › 通用 › 键盘 › 键盘 › Enclave，打开「允许完全访问」。")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.settings.isConfigured {
            HStack {
                Text("还没有配置 API").font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("从剪贴板导入配置") { model.importConfigFromPasteboard() }
                    .font(.caption)
            }
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
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
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(height: 84)
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground).opacity(0.9)))
    }

    private var placeholder: String {
        if model.isRunning { return "生成中…" }
        switch model.voiceState {
        case .recording:
            if !model.voicePartial.isEmpty { return "正在听：\(model.voicePartial)" }
            return model.voiceMode == .content ? "正在听，说完点「完成」…" : "正在听你的修改要求，说完点「完成」…"
        case .transcribing: return "识别中…"
        default: return "现在打字会进下面的要求框。输入框有内容时按要求改，输入框为空时帮你写；要求为空直接点「执行」就是润色。"
        }
    }

    private var hasResult: Bool { !model.isRunning && model.session?.current != nil }

    private var actionRow: some View {
        HStack(spacing: 6) {
            KeyButton(title: "替换", systemImage: "arrow.left.arrow.right") { model.replace() }
                .disabled(!hasResult)
            KeyButton(title: "插入", systemImage: "text.insert") { model.insert() }
                .disabled(!hasResult)
            KeyButton(title: "复制", systemImage: "doc.on.doc") { model.copy() }
                .disabled(!hasResult)
            KeyButton(title: "撤销", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
            KeyButton(title: "新会话", systemImage: nil) { model.newSession() }
                .disabled(model.session == nil && !model.isRunning)
        }
        .frame(height: 36)
    }

    /// 要求框：展开时键盘打的字都进这里。
    private var instructionField: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
                Group {
                    if model.instruction.isEmpty && !model.isComposing {
                        Text("输入修改要求…").foregroundStyle(.secondary)
                    } else {
                        (Text(model.instruction) + Text(model.composition).foregroundColor(.secondary).underline())
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
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: model.target == .instruction ? 1.5 : 0))

            Button {
                model.isRunning ? model.stop() : model.execute()
            } label: {
                Text(model.isRunning ? "停止" : "执行")
                    .font(.callout.weight(.semibold))
                    .frame(width: 64)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.isRunning ? Color.red : Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
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
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                if let title { Text(title) }
            }
            .font(.footnote.weight(prominent ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(prominent || tint != .accentColor ? Color.white : Color.primary)
            .background(Capsule().fill(prominent ? tint : (tint != .accentColor ? tint : Color(.systemBackground))))
        }
        .buttonStyle(.plain)
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

/// 普通按键样式。
struct KeyButton: View {
    var title: String?
    var systemImage: String?
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                if let title { Text(title) }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// 按住会连续触发的按键（删除键）。
struct RepeatingKey: View {
    var systemImage: String
    var action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray3)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard timer == nil else { return }
                        action()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                            Task { @MainActor in
                                // 手指已经抬起就不再开始连发。
                                guard timer != nil else { return }
                                timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                                    Task { @MainActor in action() }
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        timer?.invalidate()
                        timer = nil
                    }
            )
    }
}
