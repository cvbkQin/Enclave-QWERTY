import SwiftUI
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var settings = EnclaveSettings()
    @Published private(set) var session: EditSession?
    @Published private(set) var streamingText = ""
    @Published private(set) var isRunning = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// 复制后卡片上的复制图标变紫，短暂显示「已复制」。
    @Published private(set) var copied = false
    /// 结果卡片展开到五行。
    @Published var cardExpanded = false
    /// 「正式▾」浮层：风格和要求。
    @Published var styleMenuOpen = false
    /// 当前结果已经替换或插入过：卡片变灰，按钮显示「✓ 已替换」。
    @Published private(set) var resultUse: ResultUse?
    /// 输入框又改过，当前结果和输入对不上：卡片同样变灰。
    @Published private(set) var resultStale = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
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
    /// 盖在按键区上的面板：表情、颜文字、选拼音。
    @Published var keysPanel: KeysPanel?
    /// 长按按键弹出的备选条。
    @Published var alternates: AlternatesPopup?
    /// 输入框里是否有带下划线的拼音（marked text）。
    var hasMarkedText = false
    var lastSpaceTime = Date.distantPast
    var lastPunctuationTap = Date.distantPast
    lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    weak var controller: UIInputViewController?
    private var task: Task<Void, Never>?
    /// 每次替换或插入记一笔：写进去的文字和被它换掉的原文。撤销和重做在两个栈之间来回挪。
    private var undoStack: [FieldEdit] = []
    private var redoStack: [FieldEdit] = []

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    enum ResultUse { case replaced, inserted }

    /// 预览区显示的文字。
    var displayText: String {
        isRunning ? streamingText : (session?.current ?? "")
    }

    /// 没开完全访问或没配置 API：✨ 置灰，卡片位置显示检查清单。
    var aiBlocked: Bool { !hasFullAccess || !settings.isConfigured }

    /// 卡片用五行高度：用户点了展开，或者要显示检查清单。
    var cardTall: Bool { cardExpanded || aiBlocked }

    var keyboardHeight: CGFloat {
        KeyboardMetrics.height(expanded: aiExpanded, cardExpanded: cardTall, menuOpen: styleMenuOpen)
    }

    func reload() {
        settings = SettingsStore.load()
        session = SessionStore.load()
        instruction = SharedStorage.defaults.string(forKey: Self.instructionKey) ?? ""
        hasFullAccess = controller?.hasFullAccess ?? false
        selectEngine()
    }

    // MARK: - 执行

    /// 读取输入框，按「内容 // 要求」决定润色、按要求改或帮我写。
    func execute() {
        guard !isRunning else { return }
        reload()

        guard checkCanCallModel() else { return }

        let parsed = CommandParser.parse(readField().text)
        dropSession(unlessItBelongsTo: parsed.content)
        let command = CommandParser.Command(
            content: parsed.content,
            instruction: [instruction.trimmingCharacters(in: .whitespacesAndNewlines), parsed.instruction]
                .filter { !$0.isEmpty }
                .joined(separator: "；")
        )
        let style = settings.selectedStyle

        switch (command.content.isEmpty, command.instruction.isEmpty) {
        case (true, true):
            notice = "先在输入框里写点什么，或者点「\(settings.selectedStyle?.name ?? "风格")▾」写一个要求让它帮你写。"

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

    private func checkCanCallModel() -> Bool {
        errorMessage = nil
        notice = nil
        guard hasFullAccess else {
            errorMessage = "需要在 设置 › 通用 › 键盘 › 键盘 › Enclave 里打开「允许完全访问」才能联网。"
            return false
        }
        guard settings.isConfigured else {
            errorMessage = LLMError.notConfigured.errorDescription
            return false
        }
        return true
    }

    /// 预览区已经有一个结果（不在生成中）。
    var hasResult: Bool { !isRunning && session?.current != nil }

    /// 点风格标签：选中它；已有结果时立刻用这个风格（带上当前的要求）重写原话，结果作为新的一版。
    /// 浮层保持打开，结果卡片在上方显示生成中。
    func styleTagTapped(_ style: StylePreset) {
        selectStyle(style)
        guard !isRunning else { return }
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // 输入框里已经换成别的文字：按这个风格润色它，不再重写上一次的原话。
        let content = CommandParser.parse(readField().text).content
        if dropSession(unlessItBelongsTo: content) {
            guard !content.isEmpty, checkCanCallModel() else { return }
            setAIExpanded(true)
            run(rewrite(content, request: request, style: style), pending: EditSession(mode: .polish, original: content))
            return
        }
        guard hasResult, var pending = session, let current = pending.current, checkCanCallModel() else { return }
        setAIExpanded(true)
        switch pending.mode {
        case .polish:
            run(rewrite(pending.original, request: request, style: style), pending: pending)
        case .write:
            let ask = ["按「\(style.name)」的写法重写一遍。", request].filter { !$0.isEmpty }.joined(separator: "；")
            pending.conversation.append(.user(ask))
            run(Prompts.revise(original: pending.original, current: current, instruction: ask, style: style),
                pending: pending)
        }
    }

    /// 按风格重写一段原话；有要求时按要求改。
    private func rewrite(_ text: String, request: String, style: StylePreset) -> [ChatMessage] {
        request.isEmpty
            ? Prompts.polish(text, style: style)
            : Prompts.revise(original: text, current: text, instruction: request, style: style)
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
                    self.resultUse = nil
                    self.resultStale = false
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
        resultUse = nil
        SessionStore.save(session)
    }

    /// 输入框的文字变了（系统通知）：和当前结果对不上就把卡片变灰。
    func fieldDidChange() {
        guard let session, session.current != nil, !isRunning else { return }
        let stale = !session.belongs(to: CommandParser.parse(readField().text).content)
        if stale != resultStale { resultStale = stale }
    }

    /// 输入框里的文字和当前会话对不上时丢掉会话，返回是否丢掉了。
    /// 会话存在共享存储里，不清掉的话润色、风格和按要求改都会把上一次的内容带进来。
    @discardableResult
    func dropSession(unlessItBelongsTo fieldText: String) -> Bool {
        guard let session, !session.belongs(to: fieldText) else { return false }
        self.session = nil
        SessionStore.save(nil)
        return true
    }

    /// 键盘出现时：输入框里已经是别的文字，就清掉上一次的结果和要求。
    func dropStaleSessionOnAppear() {
        session = SessionStore.load()
        if dropSession(unlessItBelongsTo: CommandParser.parse(readField().text).content) {
            setInstruction("")
        }
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
        recordEdit(inserted: text, original: field.text, use: .replaced)
    }

    /// 在光标处插入当前版本。
    func insert() {
        guard let text = session?.current, let proxy else { return }
        proxy.insertText(text)
        recordEdit(inserted: text, original: "", use: .inserted)
    }

    func undo() {
        guard let edit = undoStack.popLast(), let proxy else { return }
        swap(edit.inserted, for: edit.original, in: proxy)
        redoStack.append(edit)
        resultUse = nil
        updateUndoState()
    }

    func redo() {
        guard let edit = redoStack.popLast(), let proxy else { return }
        swap(edit.original, for: edit.inserted, in: proxy)
        undoStack.append(edit)
        resultUse = edit.use
        updateUndoState()
    }

    /// 删掉光标前的 old，再写入 new。
    private func swap(_ old: String, for new: String, in proxy: UITextDocumentProxy) {
        for _ in 0..<old.count { proxy.deleteBackward() }
        if !new.isEmpty { proxy.insertText(new) }
    }

    /// 卡片上的复制图标或长按卡片：复制当前版本。
    func copy() {
        guard hasResult, let text = session?.current else { return }
        UIPasteboard.general.string = text
        keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.copied = false }
        }
    }

    private func recordEdit(inserted: String, original: String, use: ResultUse) {
        resultUse = use
        resultStale = false
        undoStack.append(FieldEdit(inserted: inserted, original: original, use: use))
        redoStack.removeAll()
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    #if DEBUG
    /// 模拟器截图用：让撤销、重做都可点。
    func loadDebugUndo() {
        undoStack = [FieldEdit(inserted: "", original: "", use: .replaced)]
        redoStack = [FieldEdit(inserted: "", original: "", use: .replaced)]
        updateUndoState()
    }
    #endif

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

private struct FieldEdit {
    var inserted: String
    var original: String
    var use: KeyboardModel.ResultUse
}
