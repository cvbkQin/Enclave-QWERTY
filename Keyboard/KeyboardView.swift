import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            topBar
            banner
            preview
            instructionBar
            actionRow
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 顶栏：风格、版本、新会话

    private var topBar: some View {
        HStack(spacing: 10) {
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

            Spacer()

            // 麦克风会话是否在线：在线时点「说话」直接录音，不在线会先跳到 App。
            Image(systemName: model.voiceState == .idle ? "mic.slash" : "mic.fill")
                .font(.footnote)
                .foregroundStyle(model.voiceState == .idle ? Color.secondary : Color.orange)

            if let label = model.versionLabel {
                Button { model.showVersion(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.isRunning || model.session?.currentIndex == 0)
                Text(label).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.showVersion(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.isRunning || model.session.map { $0.currentIndex >= $0.versions.count - 1 } ?? true)
            }

            Button("新会话") { model.newSession() }
                .font(.footnote)
                .disabled(model.session == nil && !model.isRunning)
        }
        .tint(.primary)
        .frame(height: 24)
    }

    // MARK: - 提示条

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

    // MARK: - 预览区

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
        .frame(maxHeight: .infinity)
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
        default: return "在输入框里写原话或点「说话」，点「执行」润色。\n在下面要求栏选一个要求或点「说要求」，按要求改；输入框为空时让它帮你写。"
        }
    }

    // MARK: - 要求栏

    private var instructionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !model.instruction.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                        Text("要求：\(model.instruction)").lineLimit(1)
                        Button { model.setInstruction("") } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.accentColor))
                }
                ForEach(KeyboardModel.presets, id: \.title) { preset in
                    Button(preset.title) { model.setInstruction(preset.instruction) }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .foregroundStyle(.primary)
                        .background(Capsule().fill(Color(.systemBackground)))
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 30)
    }

    // MARK: - 结果操作

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
        }
        .frame(height: 40)
    }

    // MARK: - 底栏：切换键盘、语音、执行、删除、换行

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.needsGlobeKey {
                NextKeyboardButton(controller: model.controller)
                    .frame(width: 44)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray3)))
            }
            voiceButton(.content, title: "说话", systemImage: "mic")
                .frame(width: 70)
            voiceButton(.instruction, title: "说要求", systemImage: "text.bubble")
                .frame(width: 84)
            Button {
                model.isRunning ? model.stop() : model.execute()
            } label: {
                Text(model.isRunning ? "停止" : "执行")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 6).fill(model.isRunning ? Color.red : Color.accentColor))
            }
            RepeatingKey(systemImage: "delete.left") { model.deleteBackward() }
                .frame(width: 48)
            KeyButton(title: nil, systemImage: "return") { model.insertNewline() }
                .frame(width: 48)
        }
        .frame(height: 44)
    }

    /// 录音时按下的那个键变成「完成」，另一个变成「取消」。
    @ViewBuilder
    private func voiceButton(_ mode: VoiceMode, title: String, systemImage: String) -> some View {
        let isActive = model.voiceMode == mode
        switch model.voiceState {
        case .recording where isActive:
            Button { model.voiceTapped(mode) } label: {
                Label("完成", systemImage: "stop.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
            }
        case .recording:
            KeyButton(title: "取消", systemImage: "xmark") { model.cancelVoice() }
        case .transcribing where isActive:
            KeyButton(title: "识别中", systemImage: nil) {}
                .disabled(true)
        default:
            KeyButton(title: title, systemImage: systemImage) { model.voiceTapped(mode) }
                .disabled(model.voiceState == .transcribing || model.isRunning)
        }
    }
}

private extension View {
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
