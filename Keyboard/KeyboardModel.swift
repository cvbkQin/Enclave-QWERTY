import ObjectiveC
import SwiftUI
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var settings = EnclaveSettings()
    @Published private(set) var session: EditSession?
    @Published private(set) var streamingText = ""
    @Published private(set) var isRunning = false
    @Published private(set) var canUndo = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
    @Published private(set) var voiceState: VoiceState = .idle
    @Published private(set) var voiceMode: VoiceMode = .content
    @Published private(set) var voicePartial = ""
    /// 键盘是否正显示在屏幕上；只有显示时才自动开始录音。
    var isVisible = false
    /// 要求栏：和正文分开存放的修改要求，执行时和输入框里的「// 要求」合并。
    @Published private(set) var instruction = ""

    // 打字状态，逻辑在 KeyboardModel+Typing.swift
    @Published var target: InputTarget = .host
    @Published var layer: KeyLayer = .letters
    @Published var shift: ShiftState = .off
    @Published var chineseMode = true
    @Published var aiExpanded = false
    @Published var composition = ""
    @Published var candidates: [String] = []
    var engine: InputEngine = DirectEngine()
    /// 拼音词库是否可用（主 App 部署过，并且打开了完全访问）。
    @Published var pinyinReady = false
    var lastShiftTap = Date.distantPast
    /// 正被按住的键，用来画按下状态和气泡。
    @Published var pressedKeys: Set<String> = []
    /// 长按空格进入的光标移动模式，按键上的字会隐藏。
    @Published var trackpadActive = false
    /// 候选词展开成整页。
    @Published var candidatesExpanded = false
    /// 输入框里是否有带下划线的拼音（marked text）。
    var hasMarkedText = false
    var lastSpaceTime = Date.distantPast
    var lastPunctuationTap = Date.distantPast
    lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    weak var controller: UIInputViewController?
    private var task: Task<Void, Never>?
    private var undoSnapshot: (inserted: String, original: String)?
    private var voiceObserver: DarwinObserver?
    private var voicePoll: Timer?

    init(controller: UIInputViewController) {
        self.controller = controller
        voiceObserver = DarwinObserver(VoiceBridge.updatedNote) { [weak self] in self?.refreshVoice() }
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    /// 预览区显示的文字。
    var displayText: String {
        isRunning ? streamingText : (session?.current ?? "")
    }

    func reload() {
        settings = SettingsStore.load()
        session = SessionStore.load()
        instruction = SharedStorage.defaults.string(forKey: Self.instructionKey) ?? ""
        hasFullAccess = controller?.hasFullAccess ?? false
        selectEngine()
        refreshVoice()
    }

    // MARK: - 执行

    /// 读取输入框，按「内容 // 要求」决定润色、按要求改或帮我写。
    func execute() {
        guard !isRunning else { return }
        reload()
        errorMessage = nil
        notice = nil
        guard hasFullAccess else {
            errorMessage = "需要在 设置 › 通用 › 键盘 › 键盘 › Enclave 里打开「允许完全访问」才能联网。"
            return
        }
        guard settings.isConfigured else {
            errorMessage = LLMError.notConfigured.errorDescription
            return
        }

        let parsed = CommandParser.parse(readField().text)
        let command = CommandParser.Command(
            content: parsed.content,
            instruction: [instruction.trimmingCharacters(in: .whitespacesAndNewlines), parsed.instruction]
                .filter { !$0.isEmpty }
                .joined(separator: "；")
        )
        let style = settings.selectedStyle

        switch (command.content.isEmpty, command.instruction.isEmpty) {
        case (true, true):
            notice = "先在输入框里写点什么，或者在要求栏填一个要求让它帮你写。"

        case (false, true):
            // 润色：开启一个新会话。
            let pending = EditSession(mode: .polish, original: command.content)
            run(Prompts.polish(command.content, style: style), pending: pending)

        case (true, false):
            // 帮我写：有进行中的帮我写会话就接着追问，否则新开一个。
            var pending: EditSession
            if let session, session.mode == .write, session.current != nil {
                pending = session
            } else {
                pending = EditSession(mode: .write, original: command.instruction)
            }
            pending.conversation.append(.user(command.instruction))
            run([Prompts.writeSystem(style: style)] + pending.conversation, pending: pending)

        case (false, false):
            // 按要求改：输入框里的内容（可能被手改过）就是当前版本。
            var pending = session ?? EditSession(mode: .polish, original: command.content)
            if pending.mode == .write {
                pending.conversation.append(.user("我把正文改成了：\n\(command.content)\n\n修改要求：\(command.instruction)"))
            }
            let messages = Prompts.revise(original: pending.original, current: command.content,
                                          instruction: command.instruction, style: style)
            run(messages, pending: pending)
        }
    }

    private func run(_ messages: [ChatMessage], pending: EditSession) {
        let client = LLMClient(settings: settings, apiKey: SettingsStore.apiKey)
        isRunning = true
        streamingText = ""
        task = Task { [weak self] in
            var raw = ""
            do {
                for try await piece in client.stream(messages) {
                    raw += piece
                    self?.streamingText = ModelOutput.clean(raw)
                }
                let result = ModelOutput.clean(raw)
                guard let self else { return }
                if result.isEmpty {
                    self.errorMessage = "模型没有返回内容。"
                } else {
                    var updated = pending
                    updated.append(result)
                    if updated.mode == .write {
                        updated.conversation.append(.assistant(result))
                    }
                    self.session = updated
                    SessionStore.save(updated)
                }
            } catch {
                if !Task.isCancelled {
                    self?.errorMessage = error.localizedDescription
                }
            }
            self?.isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    // MARK: - 版本

    #if DEBUG
    /// 模拟器截图用：放三个假版本，看翻页卡片。
    func loadDebugVersions() {
        var debug = EditSession(mode: .polish, original: "那个明天的会我可能去不了")
        debug.append("不好意思，明天的会我可能参加不了，家里临时有点事。麻烦你帮我跟老板说一声，谢谢！")
        debug.append("明天的会议我恐怕无法出席，家中临时有事，烦请代我向领导说明，非常抱歉。")
        debug.append("明天开会我去不了啦，家里有点事～帮我跟老板说下哈，不好意思！")
        debug.currentIndex = 1
        session = debug
    }
    #endif

    func showVersion(offset: Int) {
        guard var session else { return }
        let index = session.currentIndex + offset
        guard session.versions.indices.contains(index) else { return }
        session.currentIndex = index
        self.session = session
        SessionStore.save(session)
    }

    func newSession() {
        stop()
        session = nil
        SessionStore.save(nil)
        setInstruction("")
        errorMessage = nil
        notice = "已开始新会话。"
    }

    func selectStyle(_ style: StylePreset) {
        updateSettings { $0.selectedStyleID = style.id }
    }

    func updateSettings(_ change: (inout EnclaveSettings) -> Void) {
        change(&settings)
        SettingsStore.save(settings)
    }

    // MARK: - 要求栏

    private static let instructionKey = "instruction.v1"

    static let presets: [(title: String, instruction: String)] = [
        ("更正式", "语气更正式"),
        ("更简短", "更简短，只保留要点"),
        ("更口语", "更口语化、自然"),
        ("翻成英文", "翻译成英文"),
        ("扩写", "扩写得更详细具体"),
    ]

    func setInstruction(_ text: String) {
        instruction = text
        SharedStorage.defaults.set(text, forKey: Self.instructionKey)
    }

    // MARK: - 写入输入框

    private func readField() -> (text: String, isSelection: Bool) {
        guard let proxy else { return ("", false) }
        if let selected = proxy.selectedText, !selected.isEmpty {
            return (selected, true)
        }
        return ((proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? ""), false)
    }

    /// 用当前版本替换输入框内容（有选中时只替换选中部分）。
    func replace() {
        guard let text = session?.current, let proxy else { return }
        let field = readField()
        if field.isSelection {
            proxy.insertText(text)
        } else {
            clearField(proxy)
            proxy.insertText(text)
        }
        setUndo(inserted: text, original: field.text)
    }

    /// 在光标处插入当前版本。
    func insert() {
        guard let text = session?.current, let proxy else { return }
        proxy.insertText(text)
        setUndo(inserted: text, original: "")
    }

    func undo() {
        guard let snapshot = undoSnapshot, let proxy else { return }
        for _ in 0..<snapshot.inserted.count { proxy.deleteBackward() }
        if !snapshot.original.isEmpty { proxy.insertText(snapshot.original) }
        setUndo(nil)
    }

    func copy() {
        guard let text = session?.current else { return }
        UIPasteboard.general.string = text
        notice = "已复制。"
    }

    private func setUndo(inserted: String, original: String) {
        setUndo((inserted, original))
    }

    private func setUndo(_ snapshot: (inserted: String, original: String)?) {
        undoSnapshot = snapshot
        canUndo = snapshot != nil
    }

    /// iOS 没有「全选删除」接口：把光标移到末尾，再逐字删除。
    private func clearField(_ proxy: UITextDocumentProxy) {
        let after = proxy.documentContextAfterInput ?? ""
        let before = proxy.documentContextBeforeInput ?? ""
        if !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        for _ in 0..<(before.count + after.count) { proxy.deleteBackward() }
        // 长文本时系统只给出光标附近的一段，继续删到读不到内容为止。
        var guardCount = 0
        while let rest = proxy.documentContextBeforeInput, !rest.isEmpty, guardCount < 5000 {
            for _ in 0..<rest.count { proxy.deleteBackward() }
            guardCount += rest.count
        }
    }


    // MARK: - 语音

    /// 点「说话」/「说要求」：没有会话就跳到 App 开启，有会话就直接开始或结束录音。
    func voiceTapped(_ mode: VoiceMode) {
        errorMessage = nil
        notice = nil
        guard hasFullAccess else {
            errorMessage = "语音需要在 设置 › 通用 › 键盘 › 键盘 › Enclave 里打开「允许完全访问」。"
            return
        }
        switch VoiceBridge.effectiveState {
        case .recording:
            VoiceBridge.post(VoiceBridge.stopNote)
        case .transcribing:
            return
        case .ready:
            VoiceBridge.mode = mode
            VoiceBridge.errorMessage = nil
            voiceMode = mode
            VoiceBridge.post(VoiceBridge.startNote)
            // App 在后台被系统暂停时收不到通知：1.5 秒内没开始录音，就重新跳过去开启会话。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.isVisible, VoiceBridge.state == .ready else { return }
                VoiceBridge.state = .idle
                VoiceBridge.requestAutoStart()
                self.refreshVoice()
                if !self.openContainingApp(URL(string: "enclave://voice?mode=\(mode.rawValue)")!) {
                    self.errorMessage = "Enclave App 没有响应。请手动打开 App，点「开启语音会话」后再回来。"
                }
            }
        case .idle:
            VoiceBridge.mode = mode
            voiceMode = mode
            VoiceBridge.requestAutoStart()
            if !openContainingApp(URL(string: "enclave://voice?mode=\(mode.rawValue)")!) {
                errorMessage = "无法自动打开 Enclave。请手动打开 App，点「开启语音会话」后再回来。"
            }
        }
    }

    func cancelVoice() {
        VoiceBridge.post(VoiceBridge.cancelNote)
    }

    func refreshVoice() {
        let state = VoiceBridge.effectiveState
        voiceState = state
        voiceMode = VoiceBridge.mode
        voicePartial = state == .recording ? VoiceBridge.partialText : ""
        // 刚从 App 开完会话回来：自动开始录音，不用再点一次。
        if isVisible, state == .ready, VoiceBridge.takeAutoStart() {
            VoiceBridge.errorMessage = nil
            VoiceBridge.post(VoiceBridge.startNote)
        }
        if let message = VoiceBridge.errorMessage, state != .recording {
            errorMessage = message
            VoiceBridge.errorMessage = nil
        }
        if let result = VoiceBridge.takePendingResult() {
            consume(result)
        }
        // 录音和识别期间 App 那边随时可能被系统结束，定时检查心跳，避免按钮卡在「识别中」。
        if state == .recording || state == .transcribing {
            if voicePoll == nil {
                voicePoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.refreshVoice() }
                }
            }
        } else {
            voicePoll?.invalidate()
            voicePoll = nil
        }
    }

    private func consume(_ result: VoiceResult) {
        guard let proxy, !result.text.isEmpty else { return }
        switch result.mode {
        case .content:
            proxy.insertText(result.text)
            if settings.autoPolishAfterVoice { execute() }
        case .instruction:
            // 说的要求只进要求栏，不动输入框，然后直接执行。
            setInstruction(result.text)
            execute()
        }
    }

    /// 键盘扩展没有公开的「打开主 App」接口，沿响应链找到 UIApplication 调用 openURL。
    private func openContainingApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = controller
        while let current = responder {
            if current is UIApplication, let method = class_getInstanceMethod(type(of: current), selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(method_getImplementation(method), to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    // MARK: - 配置导入

    func importConfigFromPasteboard() {
        guard let string = UIPasteboard.general.string, SettingsStore.importString(string) else {
            errorMessage = "剪贴板里没有 Enclave 配置。先在 App 里点「复制配置」。"
            return
        }
        // 配置里有 API key，导入后马上清掉剪贴板。
        UIPasteboard.general.string = ""
        reload()
        errorMessage = nil
        notice = "配置已导入。"
    }
}
