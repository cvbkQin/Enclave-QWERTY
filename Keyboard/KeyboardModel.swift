import SwiftUI
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var settings = EnclaveSettings()
    @Published private(set) var session: EditSession? { didSet { aiLabelMayChange() } }
    @Published private(set) var streamingText = ""
    @Published private(set) var isRunning = false { didSet { aiLabelMayChange() } }
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
        /// 选了「仅使用基础功能」或撤回了隐私政策同意（CP7）：AI 不发请求。
        case privacy
        /// 还没填自己的 API Key（OB9）：引导去 App 首页跟着教程设置。
        case noKey
        /// previous：上次同意的是另一个地址，确认卡上划掉显示。
        case consent(endpoint: String, previous: String?)
        /// 试用已结束，今天的免费次数用完了。
        case quotaUsed
    }
    /// 同意后接着做的那一步（润色或再润）。
    private var afterConsent: (() -> Void)?
    @Published var errorMessage: String? { didSet { aiLabelMayChange() } }
    @Published var notice: String?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
    /// 要求栏：和正文分开存放的修改要求，执行时和输入框里的「// 要求」合并。
    @Published private(set) var instruction = ""
    /// 要求框里的光标在第几个字后面。
    @Published private(set) var instructionCaret = 0
    /// 在结果卡片里直接改（target == .card）：改到一半的文字和光标位置（按字符数）。
    @Published private(set) var cardDraft = ""
    @Published private(set) var cardCaret = 0
    /// 常用词，候选栏里给它们加个小紫点。
    @Published private(set) var commonWordTexts: Set<String> = []

    // 打字状态，逻辑在 KeyboardModel+Typing.swift
    @Published var target: InputTarget = .host { didSet { if (target == .card) != (oldValue == .card) { heightMayChange?() } } }
    @Published var layer: KeyLayer = .letters
    /// 九宫格数字键盘点了「更多」，左列是运算符。
    @Published var digitsMore = false
    @Published var shift: ShiftState = .off
    @Published var chineseMode = true
    @Published var aiExpanded = false {
        didSet {
            if aiExpanded { unseenResult = false }
            heightMayChange?()
        }
    }
    /// 收起时生成了结果（快速模式替换成功）还没展开看过：展开键变紫、右上角加紫点。
    @Published private(set) var unseenResult = false
    var showsNewResult: Bool { unseenResult && !aiExpanded && hasResult }
    @Published var composition = ""
    @Published var candidates: [String] = []
    /// 联想：上屏后候选栏接着显示的下一个词，按别的键就收起。
    @Published var predictions: [String] = []
    var engine: InputEngine = DirectEngine()
    /// 拼音词库是否可用（主 App 部署过，并且打开了完全访问）。
    @Published var pinyinReady = false
    var lastShiftTap = Date.distantPast
    /// 正被按住的键，用来画按下状态和气泡。单独放在 keyPresses 里：按下、松开只重画按键和气泡，不牵动整个键盘。
    let keyPresses = KeyPresses()
    var pressedKeys: Set<String> {
        get { keyPresses.pressed }
        set { if keyPresses.pressed != newValue { keyPresses.pressed = newValue } }
    }
    /// 长按空格进入的光标移动模式，按键上的字会隐藏。
    @Published var trackpadActive = false
    /// 候选词展开成整页。
    @Published var candidatesExpanded = false
    /// 盖在按键区上的面板：表情、颜文字、常用词。
    @Published var keysPanel: KeysPanel?
    /// 长按按键弹出的备选条。
    @Published var alternates: AlternatesPopup?
    /// 九宫格长按的十字弹层。
    @Published var cross: CrossPopup?
    /// 长按「中/英」弹出的拼音布局菜单（P11）。
    @Published var layoutMenu: LayoutMenuPopup?
    /// 对方输入框有没有字、回车键是什么类型，决定发送键的颜色和文字。
    @Published var hostHasText = false
    @Published var hostReturnKey: UIReturnKeyType = .default
    /// 上次按输入框类型切过页的 keyboardType；换了输入框、类型变了才再切一次，不打断用户自己切的页。
    var hostKeyboardType: UIKeyboardType?
    /// 输入框里是否有带下划线的拼音（marked text）。
    var hasMarkedText = false
    var lastSpaceTime = Date.distantPast
    var lastPunctuationTap = Date.distantPast
    lazy var haptic = UIImpactFeedbackGenerator(style: .light)
    /// 触发这次按键的触摸事件发生的时刻（UITouch.timestamp），打字耗时从这里算起：主线程忙、触摸排队也算进去。
    var keyEventTime: TimeInterval?

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
        QueuedEngine.shared.resultsReady = { [weak self] in self?.applyEngineResults() }
        QueuedEngine.shared.willSync = { [weak self] in self?.applyEngineResults(wait: true) }
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    enum ResultUse { case replaced, inserted }

    /// 预览区显示的文字。
    var displayText: String {
        isRunning ? streamingText : (session?.current ?? "")
    }

    /// 没开完全访问或没配置 API：✨ 置灰，卡片位置显示检查清单。
    var aiBlocked: Bool { !debugUnblocked && (!hasFullAccess || !settings.isConfigured) }
    /// 试用结束且今天的免费次数用完：润色按钮置灰带锁，点了出提示卡。
    var aiQuotaUsed: Bool { !debugUnblocked && !AIAccess.current.allowsAI }
    /// 模拟器截图用：没配 API 也显示结果卡片。
    var debugUnblocked = false
    #if DEBUG
    /// 截图用（-keyboardDebug coach:…）：点 ✨ /「执行」不真的请求，2 秒后出三个假版本，看小手飞到下一步。
    var debugFakeRun = false
    #endif

    /// 卡片用五行高度：用户点了展开，或者要显示检查清单。
    /// 在卡片里改结果时也用五行高度，改长了也看得全。
    var cardTall: Bool { cardExpanded || aiBlocked || target == .card }

    /// 结果卡片左上角的「AI 生成」标签（CP8）：有结果或正在生成时显示，卡片跟着高 22。和 ResultCard 的 look 对应。
    var showsAILabel: Bool {
        (isRunning || session?.current != nil) && errorMessage == nil && !aiBlocked && target != .card
    }
    private var lastAILabel = false

    private func aiLabelMayChange() {
        let now = showsAILabel
        guard now != lastAILabel else { return }
        lastAILabel = now
        heightMayChange?()
    }

    /// 控制器在这里同步改高度，和 SwiftUI 的新布局落在同一帧。
    var heightMayChange: (() -> Void)?

    var keyboardHeight: CGFloat {
        KeyboardMetrics.height(expanded: aiExpanded, cardExpanded: cardTall, menuOpen: styleMenuOpen, gate: gate,
                               reminder: showsTrialReminder, requestLines: requestLines, aiLabel: showsAILabel)
    }

    /// 提示词面板里要求框现在显示几行（1–3），由要求框按宽度折行后告诉这里，键盘跟着变高。
    @Published var requestLines = 1 {
        didSet { if requestLines != oldValue { heightMayChange?() } }
    }

    /// 试用最后 3 天 AI 栏上方的轻提示（K3）：每天第一次弹出键盘时出现，✕ 关掉。
    @Published private(set) var trialReminder = false { didSet { heightMayChange?() } }
    var showsTrialReminder: Bool { trialReminder && gate == nil && !aiExpanded && !styleMenuOpen }

    /// 使用指引「一键应用」后的小手指引导（见 KeyboardModel+Coach）。
    @Published var coach: Coach?
    var coachTask: Task<Void, Never>?
    /// 引导往下走了一步：10 秒没动的计时重新开始。
    var coachTouched = false

    func dismissTrialReminder() {
        trialReminder = false
    }

    func reload() {
        settings = SettingsStore.load()
        session = SessionStore.load()
        instruction = SharedStorage.defaults.string(forKey: Self.instructionKey) ?? ""
        instructionCaret = instruction.count
        hasFullAccess = controller?.hasFullAccess ?? false
        // 没开完全访问时读不到 App 里选的语言，跟随 iPhone。
        Loc.followSystemOnly = !hasFullAccess
        if KeyboardStatus.fullAccess != hasFullAccess { KeyboardStatus.fullAccess = hasFullAccess }
        KeyboardStatus.keyboardSeen = true
        if hasFullAccess && settings.isConfigured && AIAccess.reminderDueToday {
            trialReminder = true
            AIAccess.markReminderShown()
        }
        refreshHostState()
        selectEngine()
        refreshCommonWords()
        if let mark = LabCoachMark.take() { startCoach(mark) }
    }

    /// 常用词交给拼音引擎：App 里加的和导入的，加上系统「文本替换」和通讯录人名（开了完全访问才读得到）。
    /// 读到的系统词存一份快照给 App 的常用词页显示。
    func refreshCommonWords() {
        guard hasFullAccess, let controller else {
            applyCommonWords(CommonWordStore.active(lexicon: CommonWordStore.lexicon))
            return
        }
        // 两个开关都关着就不读系统词，也清掉上次的快照。
        guard CommonWordStore.usesTextReplacement || CommonWordStore.usesContacts else {
            CommonWordStore.lexicon = []
            applyCommonWords(CommonWordStore.load())
            return
        }
        controller.requestSupplementaryLexicon { lexicon in
            var seen = Set<String>()
            var words: [CommonWord] = []
            for entry in lexicon.entries {
                // 文本替换：输入码是缩写（yx → 邮箱）；人名：输入码就是名字本身，中文名按拼音打。
                let isName = entry.userInput == entry.documentText
                let hanzi = CommonWordStore.containsHanzi(entry.userInput)
                guard !isName || hanzi, seen.insert(entry.userInput + "\t" + entry.documentText).inserted else { continue }
                words.append(CommonWord(text: entry.documentText,
                                        pinyin: hanzi ? CommonWordStore.pinyin(of: entry.userInput) : "",
                                        shortcut: hanzi ? "" : entry.userInput,
                                        source: isName ? .contact : .textReplacement))
            }
            DispatchQueue.main.async {
                CommonWordStore.lexicon = words
                self.applyCommonWords(CommonWordStore.active(lexicon: words))
            }
        }
    }

    private func applyCommonWords(_ words: [CommonWord]) {
        commonWordTexts = Set(words.map(\.text))
        QueuedEngine.shared.updatePhrases(CommonWordStore.phraseEntries(words))
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
            notice = L("先在输入框里写点什么，或者点「\(settings.selectedStyle?.displayName ?? "润色")▾」写一个要求让它帮你写。", "Type something first, or tap \(settings.selectedStyle?.displayName ?? "Polish") ▾ and add a prompt to have it written for you.", "先に何か入力するか、「\(settings.selectedStyle?.displayName ?? "整える")▾」で指示を書くと下書きを作成します。")

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
            run(Prompts.write(pending.conversation, style: style), pending: pending)

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

    /// 能不能现在发给模型；不能时弹出对应的提示卡，返回 false。
    func passGate(then action: @escaping () -> Void) -> Bool {
        if !hasFullAccess && !debugUnblocked {
            gate = .fullAccess
            return false
        }
        if !PrivacyConsent.isAgreed {
            gate = .privacy
            return false
        }
        if !settings.isConfigured && !debugUnblocked {
            gate = .noKey
            return false
        }
        if !debugUnblocked && !AIAccess.current.allowsAI {
            gate = .quotaUsed
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
        // 看完提示卡回来，小手指引导的 10 秒重新算。
        if coach != nil { coachTouched = true }
        if gate != nil { gate = nil }
    }

    private func checkCanCallModel() -> Bool {
        errorMessage = nil
        notice = nil
        guard hasFullAccess else {
            errorMessage = L("需要在 设置 › 通用 › 键盘 › 键盘 › 飞地输入法 里打开「允许完全访问」才能联网。", "Turn on Allow Full Access in Settings › General › Keyboard › Keyboards › Enclave to connect.", "通信するには、設定 › 一般 › キーボード › キーボード › Enclave で「フルアクセスを許可」をオンにしてください。")
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
        let started = Date()
        let styleID = settings.selectedStyle?.id
        // 仪表盘的统计：耗时按毫秒记。
        func record(ok: Bool) {
            UsageStats.recordPolish(ms: Int(Date().timeIntervalSince(started) * 1000), ok: ok, styleID: styleID)
        }
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
                    self.errorMessage = L("模型没有返回内容。", "The model returned nothing.", "モデルから応答がありませんでした。")
                    self.endQuickMode(.failed)
                    record(ok: false)
                } else {
                    record(ok: true)
                    // 试用结束后只有成功拿到结果才算一次；没网、报错、点停止都不算。
                    AIAccess.recordUse()
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
                    record(ok: false)
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
        unseenResult = false
    }

    /// 快速模式结束：替换成功后提示词按钮的位置显示「AI 生成 · 已替换」3 秒（CP9）；出错留在 AI 栏上「润色失败，点重试」；
    /// 输入框中途被改过就不替换，展开面板给人看结果。
    func endQuickMode(_ outcome: QuickOutcome) {
        guard quickSource != nil else { return }
        quickSource = nil
        switch outcome {
        case .replaced:
            // 快速模式的小手：替换成功或失败后淡出。
            endCoach()
            quickStatus = .done
            if !aiExpanded { unseenResult = true }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, self.quickStatus == .done else { return }
                withAnimation(.easeOut(duration: 0.25)) { self.quickStatus = nil }
            }
        case .failed:
            endCoach()
            quickStatus = .failed
        case .changed:
            endCoach()
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

    /// 截图用：小手指引导时点 ✨ /「执行」不真的请求，2 秒后出三个假版本；收起时当作快速模式替换成功。
    func fakeCoachRun() {
        session = nil
        isRunning = true
        let quick = !aiExpanded
        if quick { beginQuickMode(source: "") }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.loadDebugVersions()
            self.isRunning = false
            // 快速模式和真的一样走完：小手淡出，AI 栏显示「AI 生成 · 已替换」3 秒。
            if quick { self.endQuickMode(.replaced) }
        }
    }

    func debugCoach(_ steps: [LabCoachMark.Step], expanded: Bool, menuOpen: Bool) {
        debugUnblocked = true
        debugFakeRun = true
        startCoach(LabCoachMark(scene: 0, steps: steps, expanded: expanded, menuOpen: menuOpen))
    }

    /// 模拟器截图用：停在生成中，看流光动画。
    func loadDebugRunning() {
        isRunning = true
        streamingText = "不好意思，明天的会我可能参加不了，家里临时有点事"
    }

    /// 截图用：收起状态下 AI 栏上的快速模式（-keyboardDebug quick:running|done|failed）。
    func loadDebugQuick(_ status: QuickStatus) {
        quickStatus = status
        // 完成时带一份结果，看展开键的「有新结果」紫点。
        if status == .done {
            if session == nil { loadDebugVersions() }
            unseenResult = true
        }
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
        coachTapped(.versions)
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

    private static let instructionKey = SettingsStore.instructionKey

    /// 整段换掉（清空、填入建议），光标放到最后。
    func setInstruction(_ text: String) {
        storeInstruction(text, caret: text.count)
    }

    func insertInInstruction(_ text: String) {
        let split = instruction.index(instruction.startIndex, offsetBy: instructionCaret)
        storeInstruction(String(instruction[..<split]) + text + String(instruction[split...]),
                         caret: instructionCaret + text.count)
    }

    func deleteInInstruction() {
        guard instructionCaret > 0 else { return }
        let end = instruction.index(instruction.startIndex, offsetBy: instructionCaret)
        let start = instruction.index(before: end)
        storeInstruction(String(instruction[..<start]) + String(instruction[end...]), caret: instructionCaret - 1)
    }

    func moveInstructionCaret(by offset: Int) {
        instructionCaret = min(max(instructionCaret + offset, 0), instruction.count)
    }

    private func storeInstruction(_ text: String, caret: Int) {
        instruction = text
        instructionCaret = min(max(caret, 0), text.count)
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
        endCoach()
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
        endCoach()
        guard let text = session?.current, let proxy else { return }
        proxy.insertText(text)
        recordEdit(inserted: text, original: "", use: .inserted)
    }

    func undo() {
        endCoach()
        guard let edit = undoStack.popLast(), let proxy else { return }
        swap(edit.inserted, for: edit.original, in: proxy)
        redoStack.append(edit)
        resultUse = nil
        updateUndoState()
    }

    func redo() {
        endCoach()
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
            errorMessage = L("剪贴板里没有飞地输入法配置。先在 App 里点「复制配置」。", "No Enclave settings on the clipboard. Tap Copy settings in the app first.", "クリップボードに Enclave の設定がありません。先にアプリで「設定をコピー」をタップしてください。")
            return
        }
        // 配置里有 API key，导入后马上清掉剪贴板。
        UIPasteboard.general.string = ""
        reload()
        errorMessage = nil
        notice = L("配置已导入。", "Settings imported.", "設定を読み込みました。")
    }
}

private struct FieldEdit {
    var inserted: String
    var original: String
    var use: KeyboardModel.ResultUse
}
