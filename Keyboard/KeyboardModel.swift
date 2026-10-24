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
    @Published var cardExpanded = false { didSet { heightMayChange?() } }
    /// 「正式▾」浮层：风格和要求。
    @Published var styleMenuOpen = false { didSet { heightMayChange?() } }
    /// 当前结果已经替换或插入过：卡片变灰，按钮显示「✓ 已替换」。
    @Published private(set) var resultUse: ResultUse?
    /// 输入框又改过，当前结果和输入对不上：卡片同样变灰。
    @Published private(set) var resultStale = false
    /// 点「润色」「再润」时先要过的一关：没开完全访问出提示卡，还没同意过当前接口地址出确认卡。
    @Published private(set) var gate: AIGate? { didSet { heightMayChange?() } }
    enum AIGate: Equatable {
        case fullAccess
        /// previous：上次同意的是另一个地址，确认卡上划掉显示。
        case consent(endpoint: String, previous: String?)
    }
    /// 同意后接着做的那一步（润色或再润）。
    private var afterConsent: (() -> Void)?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
    /// 要求栏：和正文分开存放的修改要求，执行时和输入框里的「// 要求」合并。
    @Published private(set) var instruction = ""
    /// 在结果卡片里直接改（target == .card）：改到一半的文字和光标位置（按字符数）。
    @Published private(set) var cardDraft = ""
    @Published private(set) var cardCaret = 0

    // 打字状态，逻辑在 KeyboardModel+Typing.swift
    @Published var target: InputTarget = .host
    @Published var layer: KeyLayer = .letters
    /// 九宫格数字键盘点了「更多」，左列是运算符。
    @Published var digitsMore = false
    @Published var shift: ShiftState = .off
    @Published var chineseMode = true
    @Published var aiExpanded = false { didSet { heightMayChange?() } }
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
    /// 九宫格长按的十字弹层。
    @Published var cross: CrossPopup?
    /// 对方输入框有没有字、回车键是什么类型，决定发送键的颜色和文字。
    @Published var hostHasText = false
    @Published var hostReturnKey: UIReturnKeyType = .default
    /// 输入框里是否有带下划线的拼音（marked text）。
    var hasMarkedText = false
    var lastSpaceTime = Date.distantPast
    var lastPunctuationTap = Date.distantPast
    lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    weak var controller: UIInputViewController?
    private var task: Task<Void, Never>?
    /// 快速模式：收起时点 ✨，记下当时输入框的内容，润完直接替换；输入框中途被改过就不替换，展开给人看。
    var quickSource: String?
    /// 快速模式在 AI 栏上的状态：润色中（流光圈住 AI 栏）、✓ 已润色（1.5 秒后消失）、润色失败点重试。
    @Published private(set) var quickStatus: QuickStatus?
    enum QuickStatus { case running, done, failed }
    /// 这次生成是哪个按钮点的：特效只在那个按钮上（AI 栏「润色」或风格浮层「再润」），收起展开都一样。
    enum RunOrigin { case polish, rerun }
    @Published private(set) var runOrigin: RunOrigin?
    /// 刚完成的一次，按钮上的星星闪金用。
    struct Finished: Equatable {
        var origin: RunOrigin
        var at: Date
    }
    @Published private(set) var finished: Finished?
    enum QuickOutcome { case replaced, changed, failed }
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
    var aiBlocked: Bool { !debugUnblocked && (!hasFullAccess || !settings.isConfigured) }
    /// 模拟器截图用：没配 API 也显示结果卡片。
    var debugUnblocked = false

    /// 卡片用五行高度：用户点了展开，或者要显示检查清单。
    var cardTall: Bool { cardExpanded || aiBlocked }

    /// 控制器在这里同步改高度，和 SwiftUI 的新布局落在同一帧。
    var heightMayChange: (() -> Void)?

    var keyboardHeight: CGFloat {
        KeyboardMetrics.height(expanded: aiExpanded, cardExpanded: cardTall, menuOpen: styleMenuOpen, gate: gate)
    }

    func reload() {
        settings = SettingsStore.load()
        session = SessionStore.load()
        instruction = SharedStorage.defaults.string(forKey: Self.instructionKey) ?? ""
        hasFullAccess = controller?.hasFullAccess ?? false
        if KeyboardStatus.fullAccess != hasFullAccess { KeyboardStatus.fullAccess = hasFullAccess }
        refreshHostState()
        selectEngine()
    }

    // MARK: - 执行

    /// 读取输入框，按「内容 // 要求」决定润色、按要求改或帮我写。
    func execute() {
        guard !isRunning else { return }
        reload()

        guard checkCanCallModel() else { return }

        var parsed = CommandParser.parse(readField().text)
        // 卡片上显示的是手改过的一版：拿它当原文；否则读输入框此刻的内容。
        if let session, session.currentIsEdited, let edited = session.current {
            parsed.content = edited
        } else {
            dropSession(unlessItBelongsTo: parsed.content)
        }
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
            // 润色：总是润输入框里现在的文字（可能是替换后又手改过的），结果接在这次会话后面，翻页还能找回之前的版本。
            var pending = EditSession(mode: .polish, original: command.content)
            if let session, session.mode == .polish { pending = session }
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

    /// 能不能现在发给模型；不能时弹出对应的提示卡，返回 false。接口还没配置时交给原来的流程提示。
    func passGate(then action: @escaping () -> Void) -> Bool {
        if !hasFullAccess && !debugUnblocked {
            gate = .fullAccess
            return false
        }
        guard settings.isConfigured, let endpoint = ConsentStore.endpoint(of: settings.baseURL),
              !ConsentStore.isConsented(endpoint) else { return true }
        gate = .consent(endpoint: endpoint, previous: ConsentStore.consented?.endpoint)
        afterConsent = action
        return false
    }

    /// 确认卡上的「同意并润色」：记下这个地址，接着做刚才那一步。
    func acceptConsent() {
        guard case .consent(let endpoint, _) = gate else { return }
        ConsentStore.grant(endpoint)
        let action = afterConsent
        dismissGate()
        action?()
    }

    /// 风格按钮在没开完全访问时也只出提示卡。
    func showFullAccessTip() {
        gate = .fullAccess
    }

    /// 键盘里打开主 App 的某个页面。扩展不能直接调 open(_:)，沿响应链找到 UIApplication 再调它。
    func openContainingApp(_ link: String) {
        guard let url = NSURL(string: link) else { return }
        // 先沿响应链找，找不到再用 sharedApplication；两种在不同系统版本上各有失灵的时候。
        var responder: UIResponder? = controller?.view ?? controller
        var application: NSObject?
        while let current = responder {
            if current is UIApplication { application = current; break }
            responder = current.next
        }
        if application == nil {
            application = UIApplication.value(forKey: "sharedApplication") as? NSObject
        }
        guard let application else { return }
        let modern = NSSelectorFromString("openURL:options:completionHandler:")
        if application.responds(to: modern) {
            typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
            let open = unsafeBitCast(application.method(for: modern), to: Open.self)
            open(application, modern, url, NSDictionary(), nil)
        } else {
            application.perform(NSSelectorFromString("openURL:"), with: url)
        }
    }

    // MARK: - 在卡片里改结果

    /// 进入修改：点文字时光标放在点的位置，点铅笔放到末尾。只在面板展开、有结果时能改。
    func beginCardEdit(caret: Int? = nil) {
        guard aiExpanded, hasResult, let text = session?.current else { return }
        if target != .card {
            finishComposition()
            cardDraft = text
        } else {
            finishComposition()
        }
        cardCaret = min(max(caret ?? cardDraft.count, 0), cardDraft.count)
        target = .card
    }

    /// 完成修改：改过就存成新的一版（标「已改」），没改就只退出。
    func finishCardEdit() {
        guard target == .card else { return }
        finishComposition()
        target = .host
        let text = cardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var session, !text.isEmpty, cardDraft != session.current else { return }
        session.append(cardDraft, edited: true)
        self.session = session
        resultUse = nil
        resultStale = false
        SessionStore.save(session)
    }

    /// 取消修改：丢掉这次改的，回到进入前那一版。
    func cancelCardEdit() {
        guard target == .card else { return }
        engine.reset()
        syncEngine()
        target = .host
        cardDraft = ""
    }

    func insertInCard(_ text: String) {
        let index = cardDraft.index(cardDraft.startIndex, offsetBy: cardCaret)
        cardDraft.insert(contentsOf: text, at: index)
        cardCaret += text.count
    }

    func deleteInCard() {
        guard cardCaret > 0 else { return }
        let index = cardDraft.index(cardDraft.startIndex, offsetBy: cardCaret - 1)
        cardDraft.remove(at: index)
        cardCaret -= 1
    }

    func moveCardCaret(by offset: Int) {
        cardCaret = min(max(cardCaret + offset, 0), cardDraft.count)
    }

    func dismissGate() {
        afterConsent = nil
        if gate != nil { gate = nil }
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

    /// 风格浮层里的「润色」和回车「执行」：按当前风格和要求生成。
    /// 已有这段文字的结果时，用原话重写一版追加到后面，可以上下翻回之前的版本；否则照常执行。
    func regenerate() {
        guard !isRunning else { return }
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = session?.currentIsEdited == true ? session?.current : nil
        let content = edited ?? CommandParser.parse(readField().text).content
        guard !content.isEmpty, edited != nil || !dropSession(unlessItBelongsTo: content),
              hasResult, var pending = session, let style = settings.selectedStyle
        else {
            execute()
            return
        }
        guard checkCanCallModel() else { return }
        switch pending.mode {
        case .polish:
            // 再润也以输入框里现在的文字为准，不退回最初的原话。
            run(rewrite(content, request: request, style: style), pending: pending)
        case .write:
            let ask = ["按「\(style.name)」的写法重写一遍。", request].filter { !$0.isEmpty }.joined(separator: "；")
            pending.conversation.append(.user(ask))
            run(Prompts.revise(original: pending.original, current: content, instruction: ask, style: style),
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
                    self.endQuickMode(.failed)
                } else {
                    var updated = pending
                    updated.append(result)
                    if updated.mode == .write {
                        updated.conversation.append(.assistant(result))
                    }
                    self.session = updated
                    self.finished = Finished(origin: self.runOrigin ?? .polish, at: Date())
                    self.resultUse = nil
                    self.resultStale = false
                    SessionStore.save(updated)
                    if let source = self.quickSource {
                        let unchanged = self.readField().text == source
                        if unchanged { self.replace() }
                        self.endQuickMode(unchanged ? .replaced : .changed)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self?.errorMessage = error.localizedDescription
                    self?.endQuickMode(.failed)
                }
            }
            self?.isRunning = false
            self?.runOrigin = nil
        }
    }

    /// 点了「润色」或「再润」：记下是哪个按钮，没开始生成（提示、出错）就清掉。
    func start(from origin: RunOrigin, _ action: () -> Void) {
        runOrigin = origin
        action()
        if !isRunning { runOrigin = nil }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        runOrigin = nil
        quickSource = nil
        quickStatus = nil
    }

    /// 快速模式开始：AI 栏进入「润色中」。
    func beginQuickMode(source: String) {
        quickSource = source
        quickStatus = .running
    }

    /// 快速模式结束：替换成功显示「✓ 已润色」1.5 秒；出错留在 AI 栏上「润色失败，点重试」；
    /// 输入框中途被改过就不替换，展开面板给人看结果。
    func endQuickMode(_ outcome: QuickOutcome) {
        guard quickSource != nil else { return }
        quickSource = nil
        switch outcome {
        case .replaced:
            quickStatus = .done
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self?.quickStatus == .done { self?.quickStatus = nil }
            }
        case .failed:
            quickStatus = .failed
        case .changed:
            quickStatus = nil
            aiExpanded = true
        }
    }

    /// 展开面板或开始新的生成时，AI 栏上的快速模式提示就不用留着了。
    func clearQuickStatus() {
        if quickStatus != nil { quickStatus = nil }
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

    /// 模拟器截图用：停在生成中，看流光动画。
    func loadDebugRunning() {
        isRunning = true
        streamingText = "不好意思，明天的会我可能参加不了，家里临时有点事"
    }

    /// 截图用：收起状态下 AI 栏上的快速模式（-keyboardDebug quick:running|done|failed）。
    func loadDebugQuick(_ status: QuickStatus) {
        quickStatus = status
        if status == .running {
            isRunning = true
            runOrigin = .polish
        }
    }

    /// 截图用：风格浮层「再润」生成中（rerun:running），或 3 秒后完成闪金、每 5 秒重来（rerun:cycle）。
    func loadDebugRerun(cycle: Bool) {
        styleMenuOpen = true
        guard cycle else {
            isRunning = true
            runOrigin = .rerun
            return
        }
        Task { [weak self] in
            while let self {
                self.isRunning = true
                self.runOrigin = .rerun
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.isRunning = false
                self.runOrigin = nil
                self.finished = Finished(origin: .rerun, at: Date())
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// 截图用：润色中 3 秒后完成，看完成时星星闪金（-keyboardDebug quick:cycle），每 5 秒重来一次。
    func loadDebugQuickCycle() {
        Task { [weak self] in
            while let self {
                self.loadDebugQuick(.running)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.isRunning = false
                self.runOrigin = nil
                self.quickStatus = .done
                self.finished = Finished(origin: .polish, at: Date())
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    #endif

    func showVersion(offset: Int) {
        if target == .card { finishCardEdit() }
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
        refreshHostState()
        guard let session, session.current != nil, !isRunning else { return }
        let stale = !session.belongs(to: CommandParser.parse(readField().text).content)
        if stale != resultStale { resultStale = stale }
    }

    /// 输入框里的文字和当前会话对不上时丢掉会话，返回是否丢掉了。
    /// 会话存在共享存储里，不清掉的话润色、风格和按要求改都会把上一次的内容带进来。
    /// 刚把结果替换或插入进输入框的，手改过也还算这次会话，再润的结果接着往后翻。
    @discardableResult
    func dropSession(unlessItBelongsTo fieldText: String) -> Bool {
        guard let session, resultUse == nil, !session.belongs(to: fieldText) else { return false }
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

    func readField() -> (text: String, isSelection: Bool) {
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
