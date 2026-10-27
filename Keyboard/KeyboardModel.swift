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
    /// 输入框太长、键盘只读到光标附近一段：替换只换了这一段，卡片上提示 4 秒。
    /// 替换后卡片底部的一行提示：只替换了读到的一段 / 输入框改过了没替换。4 秒后消失。
    @Published private(set) var replaceNote: ReplaceNote?
    enum ReplaceNote { case partial, mismatch }
    /// 发给 AI 的那段输入框文字在哪（不是选中时）。替换照它删，不在按替换时重算。
    private var readSpan: FieldSpan?
    /// 键盘里拉起 App 失败：顶上提示 4 秒，请人自己打开 App。
    @Published private(set) var openAppFailed = false
    /// 结果卡片展开到五行。
    @Published var cardExpanded = false { didSet { heightMayChange?() } }
    /// AI 栏上方展开的一行：「润色 ▴」的提示词标签，或「识意 ▾」的输入框（QA2、QA14）。两者互斥。
    enum AIRow { case prompts, ask }
    @Published var aiRow: AIRow? { didSet { if aiRow != oldValue { heightMayChange?() } } }
    /// 「识意」框重新展开时整段全选：直接打字就覆盖，删除键清空。
    @Published var askSelected = false
    /// 「识意」的两种方式：改写（产出能直接发的文字）、问答（回答问题）。
    enum AskMode { case rewrite, answer }
    /// 按住 ✨ 手动选的方式，只跟着当时那一句：识意框的字一改就回到自动。
    @Published var askChoice: AskMode?
    var askChoiceText = ""
    /// 这次生成是「识意」发起的；askKind 是模型给出的判断，还没判断时为 nil。
    @Published var askRunning = false
    @Published var askKind: AskMode?
    /// 识意问答正在联网搜索（Kimi）。卡片上的流光小字写「正在联网搜索…」。
    @Published var askSearching = false
    /// 模型说要联网、还没允许时，回答框换成这张选择框（见 searchAllowed）。
    @Published var searchPrompt: SearchPrompt?
    private var searchReply: CheckedContinuation<Bool, Never>?

    struct SearchPrompt: Equatable {
        var provider: SearchProvider
        /// 三档选了禁止：提示去 App 里开启，或者不联网直接回答。
        var disabled: Bool
    }
    /// 上一次「识意」的结果：同一句换了方式重做时顶掉它（没替换、插入、复制过的话）。
    struct LastAsk {
        var question: String
        var kind: AskMode
        var index: Int
        var used = false
    }
    var lastAsk: LastAsk?
    /// 当前结果已经替换或插入过：卡片变灰，按钮显示「✓ 已替换」。
    @Published private(set) var resultUse: ResultUse?
    /// 当前这一版替换、插入过哪几种（结果卡左边的键：两个都用过就都显示「✓ 已…」）。翻版本、出新结果时清空。
    @Published private(set) var resultUses: Set<ResultUse> = []
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
    @Published var errorMessage: String? {
        didSet {
            aiLabelMayChange()
            // 出错卡没了（新的一次请求、关掉抽屉等），失败的附带信息也一起清掉。
            if errorMessage == nil, oldValue != nil, failure != nil || partialResult != nil { clearFailure() }
        }
    }
    /// 最近一次 AI 请求失败的分类（ER0–ER5）：出错卡按它写标题、说明，决定有没有「去设置」。
    @Published var failure: LLMFailure?
    /// 出错卡「· 详情」里的原文：第一行「{服务商} · HTTP {码}」，下面是服务端返回。
    @Published var failureDetail: String?
    /// 出错的那个接口的服务商名字（说明里的 {服务商}），以及它是不是问答页的接口（「去设置」打开哪一页）。
    @Published var failureProvider = ""
    var failureOnAnswerAPI = false
    /// 点了「· 详情」：卡片展开到 4 行高。
    @Published var failureDetailShown = false
    /// 出了一半断了（ER3）：保留已出的字，下面一行橙字「没写完，连接断了」+ 重试。answer 是当时识意判断的方式。
    @Published var partialResult: (text: String, answer: Bool?)?
    /// 重试用：上一次发出去的请求，原样再发一次（结果作为新的一版进翻页）。
    private var lastRun: (messages: [ChatMessage], pending: EditSession, ask: AskRequest?, origin: RunOrigin)?
    /// 8 秒还没出字：卡片第一行后面加「模型响应较慢」和「取消」（界面等稿）。出字或结束时清掉。
    @Published var responseSlow = false
    @Published var notice: String?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
    /// 「识意」框里的话（问题或修改要求），和正文分开存放。
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
    /// 英文补全：点补全词时先删掉光标前这么多个字母（正在打的半个词）；联想下一个词时为 0。
    var predictionReplaces = 0
    /// 上次弹出时用的「主要语言」，用来判断设置是不是刚改过。
    var appliedLanguage: InputLanguage?
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
    /// 长按候选弹出的小气泡（CL1–CL3）；按的那个词在候选栏里浅色底。
    @Published var candidateMenu: CandidateMenu?
    /// 删了候选后候选栏换成「✓ 已删除「xx」 撤销」（CL4），3 秒后或继续打字时真的删。
    @Published var candidateUndo: CandidateUndo?
    var candidateUndoTimer: DispatchWorkItem?
    /// 盖在按键区上的面板：表情、颜文字、常用词。
    @Published var keysPanel: KeysPanel? { didSet { if (keysPanel == .words) != (oldValue == .words) { heightMayChange?() } } }
    /// 分词面板拆的那段字：打开时取当前版本，之后版本变了也不跟。
    @Published var wordPanelText = ""
    @Published var wordPanelFading = false
    /// 刚进自由编辑时的小胶囊。
    @Published var freeEditToast = false
    var freeEditToastTimer: DispatchWorkItem?
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
    /// 这次生成是怎么开始的：✨ 按提示词润色，或识意展开时的 ✨。特效都在 ✨ 上。
    enum RunOrigin { case polish, ask }
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
    var aiQuotaUsed: Bool { !debugUnblocked && aiUsesLeft == 0 }
    /// 试用结束后今天还剩几次（试用中、已解锁时为 nil）。润色按钮每次重画都要看，
    /// 每次现算要读好几次共享存储、算日历，打字时每个键都会重画几遍，所以弹出时和用掉一次后各算一次存着。
    private(set) var aiUsesLeft: Int?

    func refreshAIAccess() {
        if case .expired = AIAccess.current { aiUsesLeft = AIAccess.usesLeftToday } else { aiUsesLeft = nil }
    }
    /// 模拟器截图用：没配 API 也显示结果卡片。
    var debugUnblocked = false
    #if DEBUG
    /// 截图用（-keyboardDebug coach:…）：点 ✨ /「执行」不真的请求，2 秒后出三个假版本，看小手飞到下一步。
    var debugFakeRun = false
    /// 截图用（-keyboardDebug askHold）：✨ 上停着按住时弹出的「改写 / 问答」（QA11）。
    var debugAskHold = false
    /// 截图用（-keyboardDebug key:…）：结果卡左边的键停在滑过 16pt 换过去（rolled）或弹出另一个（popped）的样子。
    var debugResultKeyPose: String?

    /// 截图用：直接显示某张提示卡（quotaUsed：次数用完）。
    func debugShowGate(_ gate: AIGate) { self.gate = gate }

    /// 截图用：结果卡上的部分替换提示、顶上的打不开 App 提示，一直显示。
    func debugShowNotes(partial: Bool) {
        if partial { replaceNote = .partial } else { openAppFailed = true }
    }

    /// 截图用：不经过 App 改结果卡左边那颗键的设置。
    func debugResultKey(primary: ResultKeyAction? = nil, swipe: ResultKeySwipe? = nil, wheelUp: Bool? = nil) {
        if let primary { settings.resultKeyPrimary = primary }
        if let swipe { settings.resultKeySwipe = swipe }
        if let wheelUp { settings.resultKeyWheelUp = wheelUp }
    }
    #endif

    /// 卡片用五行高度：用户点了展开，或者要显示检查清单。
    /// 在卡片里改结果时也用五行高度，改长了也看得全。
    /// 自由编辑框按进入前是 2 行还是 4 行算高度（108 或 148）。
    var freeEditTall: Bool { !landscape && cardExpanded }

    /// 分词面板开着时结果卡固定 2 行，关掉后回到原来的 2 行或 4 行（cardExpanded 不动）。
    var cardTall: Bool { !landscape && keysPanel != .words && (cardExpanded || aiBlocked || target == .card || failureDetailShown) }

    /// 横屏简版（LS1–LS3）：控制器按屏幕方向设，尺寸见 KeyboardMetrics.landscape。
    @Published private(set) var landscape = false

    func setLandscape(_ value: Bool) {
        guard value != landscape else { return }
        KeyboardMetrics.landscape = value
        landscape = value
        heightMayChange?()
    }

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
        KeyboardMetrics.height(expanded: aiExpanded, cardExpanded: target == .card ? freeEditTall : cardTall, rowOpen: aiRow != nil, gate: gate,
                               reminder: showsTrialReminder, aiLabel: showsAILabel,
                               freeEdit: target == .card, wordPanel: keysPanel == .words)
    }

    /// 试用最后 3 天 AI 栏上方的轻提示（K3）：每天第一次弹出键盘时出现，✕ 关掉。
    @Published private(set) var trialReminder = false { didSet { heightMayChange?() } }
    var showsTrialReminder: Bool { trialReminder && gate == nil && !aiExpanded && aiRow == nil }

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
        refreshSearchPrompt()
        session = SessionStore.load()
        instruction = SharedStorage.defaults.string(forKey: Self.instructionKey) ?? ""
        instructionCaret = instruction.count
        hasFullAccess = controller?.hasFullAccess ?? false
        // 没开完全访问时读不到 App 里选的语言，跟随 iPhone。
        Loc.followSystemOnly = !hasFullAccess
        refreshAIAccess()
        if KeyboardStatus.fullAccess != hasFullAccess { KeyboardStatus.fullAccess = hasFullAccess }
        KeyboardStatus.keyboardSeen = true
        if hasFullAccess && settings.isConfigured && AIAccess.reminderDueToday {
            trialReminder = true
            AIAccess.markReminderShown()
        }
        refreshHostState()
        selectEngine()
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
            let raw = lexicon.entries.map { (input: $0.userInput, text: $0.documentText) }
            // 转拼音（每个中文名一次 CFStringTransform）、比对和重写快照都放到后台：冷启动时缓存是空的，
            // 通讯录一多，原来在主线程上要算好一阵，正好压在键盘刚弹出、用户开始打字的时候。
            DispatchQueue.global(qos: .utility).async {
                var seen = Set<String>()
                var words: [CommonWord] = []
                for entry in raw {
                    // 文本替换：输入码是缩写（yx → 邮箱）；人名：输入码就是名字本身，中文名按拼音打。
                    let isName = entry.input == entry.text
                    let hanzi = CommonWordStore.containsHanzi(entry.input)
                    guard !isName || hanzi, seen.insert(entry.input + "\t" + entry.text).inserted else { continue }
                    words.append(CommonWord(text: entry.text,
                                            pinyin: hanzi ? ContactPinyin.of(entry.input) : "",
                                            shortcut: hanzi ? "" : entry.input,
                                            source: isName ? .contact : .textReplacement))
                }
                // 快照没变就不重写（每次弹出都会读一遍，通讯录多时编码、写共享存储都不便宜）。
                // CommonWord 每次都带新的 id，按内容比。
                func signature(_ list: [CommonWord]) -> [String] {
                    list.map { "\($0.text)\t\($0.pinyin)\t\($0.shortcut)\t\($0.source.rawValue)" }
                }
                if signature(CommonWordStore.lexicon) != signature(words) { CommonWordStore.lexicon = words }
                let active = CommonWordStore.active(lexicon: words)
                DispatchQueue.main.async { [weak self] in self?.applyCommonWords(active) }
            }
        }
    }

    /// 上次交给引擎的短语表（按内容比）。
    private var lastPhraseSignature: [String]?

    /// 候选长按改了常用词：马上交给引擎，不等下次弹出键盘。
    func reloadCommonWords() {
        applyCommonWords(CommonWordStore.active(lexicon: CommonWordStore.lexicon))
    }

    private func applyCommonWords(_ words: [CommonWord]) {
        let texts = Set(words.map(\.text))
        if texts != commonWordTexts { commonWordTexts = texts }
        let entries = CommonWordStore.phraseEntries(words)
        // 没变就不交给引擎：重写短语表要排在 Rime 队列上读文件比对，弹出后的第一个键得等它。
        // 带上词库版本和用哪份词库：App 重新部署、开关完全访问后短语表要写到新的用户目录里。
        let signature = ["\(hasFullAccess)", RimeStore.deployedVersion ?? ""] + entries.map { $0.text + "\t" + $0.code }
        guard signature != lastPhraseSignature else { return }
        lastPhraseSignature = signature
        QueuedEngine.shared.updatePhrases(entries)
    }

    // MARK: - 执行

    /// 读取输入框，按「内容 // 要求」决定润色、按要求改或帮我写。
    func execute() {
        guard !isRunning else { return }
        reload()

        guard checkCanCallModel() else { return }

        var parsed = CommandParser.parse(readField(remember: true).text)
        // 卡片上显示的是手改过的一版：拿它当原文；否则读输入框此刻的内容。
        if let session, session.currentIsEdited, let edited = session.current {
            parsed.content = edited
        } else {
            dropSession(unlessItBelongsTo: parsed.content)
        }
        // 「识意」框里的话只在识意展开时用（askTapped），这里只看输入框里的「// 要求」。
        let command = parsed
        let style = settings.selectedStyle

        switch (command.content.isEmpty, command.instruction.isEmpty) {
        case (true, true):
            notice = L("先在输入框里写点什么，或者点「识意」说说想写什么，让它帮你写。", "Type something first, or tap Ask and say what you want written.", "先に何か入力するか、「たずねる」で書いてほしい内容を伝えてください。")

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

    /// 识意可能问答时：问答单独用另一个接口的，那个地址也要先同意。都同意过返回 true。
    /// 联网不在这里问：模型说要联网时才在回答框里问（searchPrompt）。
    func passAnswerConsent(then action: @escaping () -> Void) -> Bool {
        guard let endpoint = ConsentStore.endpoint(of: settings.forAnswers.baseURL),
              settings.usesAnswerEndpoint, !ConsentStore.isConsented(endpoint) else { return true }
        gate = .consent(endpoint: endpoint, previous: nil)
        afterConsent = action
        return false
    }

    /// 确认卡上的「同意并润色」：记下这个地址，接着做刚才那一步。卡上写了联网那一行时，联网问答也算同意了。
    func acceptConsent() {
        guard case .consent(let endpoint, _) = gate else { return }
        ConsentStore.grant(endpoint)
        let action = afterConsent
        dismissGate()
        action?()
    }

    /// 模型说要联网：开着、这一家同意过就直接联；否则回答框换成选择框，等用户点。
    /// 开着但第一次用这一家时点允许，记下同意，以后不再问；每次询问只算这一次。
    func searchAllowed(_ provider: SearchProvider) async -> Bool {
        let mode = settings.webSearchMode ?? .off
        if mode == .on && WebSearch.isConsented(provider) { return true }
        resolveSearchPrompt(allow: false)
        return await withCheckedContinuation { reply in
            searchReply = reply
            searchPrompt = SearchPrompt(provider: provider, disabled: mode == .off)
        }
    }

    /// 选择框上的「允许 / 拒绝」（禁止时的「直接回答」算拒绝）；点停止也走这里。
    func resolveSearchPrompt(allow: Bool) {
        let prompt = searchPrompt
        let reply = searchReply
        searchPrompt = nil
        searchReply = nil
        let allowed = allow && prompt?.disabled == false
        if allowed, let prompt, settings.webSearchMode == .on { WebSearch.grantConsent(prompt.provider) }
        reply?.resume(returning: allowed)
    }

    /// 回到键盘时重新读了设置：在 App 里把禁止改成了开或每次询问，选择框跟着变成「允许 / 拒绝」。
    private func refreshSearchPrompt() {
        guard let prompt = searchPrompt, prompt.disabled, (settings.webSearchMode ?? .off) != .off else { return }
        searchPrompt = SearchPrompt(provider: prompt.provider, disabled: false)
    }

    /// 风格按钮在没开完全访问时也只出提示卡。
    func showFullAccessTip() {
        gate = .fullAccess
    }

    /// 键盘里打开主 App 的某个页面。扩展不能直接调 open(_:)，沿响应链找到 UIApplication 再调它。
    /// 找不到、或系统回报没打开时，提示人自己去主屏幕打开 App。
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
        guard let application else { showOpenAppFailed(); return }
        let modern = NSSelectorFromString("openURL:options:completionHandler:")
        if application.responds(to: modern) {
            typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
            let open = unsafeBitCast(application.method(for: modern), to: Open.self)
            let completion: @convention(block) (Bool) -> Void = { [weak self] success in
                guard !success else { return }
                DispatchQueue.main.async { self?.showOpenAppFailed() }
            }
            open(application, modern, url, NSDictionary(), completion as AnyObject)
        } else if application.responds(to: NSSelectorFromString("openURL:")) {
            application.perform(NSSelectorFromString("openURL:"), with: url)
        } else {
            showOpenAppFailed()
        }
    }

    private func showOpenAppFailed() {
        withAnimation(.easeOut(duration: 0.15)) { openAppFailed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.openAppFailed = false }
        }
    }

    // MARK: - 在卡片里改结果

    /// 连点 3 下结果卡正文进自由编辑（FE1、FE2）：光标放在第三下点的位置，上方浮出「已开启自由编辑」1.5 秒。
    func beginFreeEdit(caret: Int) {
        guard target != .card else { return }
        beginCardEdit(caret: caret)
        guard target == .card else { return }
        keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.15)) { freeEditToast = true }
        freeEditToastTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.25)) { self?.freeEditToast = false }
        }
        freeEditToastTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timer)
    }

    /// 进入修改：光标放在给的位置，没给就放到末尾。只在面板展开、有结果时能改。
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
        target = restingTarget
        let text = cardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var session, !text.isEmpty, cardDraft != session.current else { return }
        session.append(cardDraft, edited: true)
        self.session = session
        resultUse = nil
        resultUses = []
        resultStale = false
        SessionStore.save(session)
    }

    /// 取消修改：丢掉这次改的，回到进入前那一版。
    func cancelCardEdit() {
        guard target == .card else { return }
        engine.reset()
        syncEngine()
        target = restingTarget
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

    /// 「识意」的这一次：问的话、手动选的方式（nil 自动），模型没写类型时按 fallback 算回答还是改写。
    struct AskRequest {
        var question: String
        var forced: AskMode?
        var fallbackAnswer: Bool
        /// 输入框原文（联网后再问一次要用）。
        var context: String = ""
        /// 问答接口能联网时是哪一家（不是指定改写）。联不联网看三档，模型说要联网时再定。
        var search: SearchProvider?
    }

    func run(_ messages: [ChatMessage], pending: EditSession, ask: AskRequest? = nil) {
        // 手动选了问答就直接找问答模型；自动时先用润色的快模型判断，判断是问答再换问答模型重问（answerClient）。
        let answerClient = settings.usesAnswerEndpoint
            ? LLMClient(settings: settings.forAnswers, apiKey: SettingsStore.answerKey(for: settings)) : nil
        var client = ask?.forced == .answer ? (answerClient ?? LLMClient(settings: settings, apiKey: SettingsStore.apiKey))
            : LLMClient(settings: settings, apiKey: SettingsStore.apiKey)
        var mayHandOff = answerClient != nil && ask != nil && ask?.forced != .answer
        isRunning = true
        clearFailure()
        lastRun = (messages, pending, ask, runOrigin ?? .polish)
        streamingText = ""
        askRunning = ask != nil
        if askKind != nil { askKind = nil }
        let started = Date()
        let styleID = settings.selectedStyle?.id
        // 仪表盘的统计：耗时按毫秒记。
        // 最后是问答接口回答的（单独设了问答接口）：不进接口页的小曲线，那里只看主接口。
        let separateAnswer = settings.usesAnswerEndpoint
        var answeredByAnswerAPI = ask?.forced == .answer && separateAnswer
        func record(ok: Bool) {
            UsageStats.recordPolish(ms: Int(Date().timeIntervalSince(started) * 1000), ok: ok, styleID: styleID,
                                    mainAPI: !answeredByAnswerAPI)
        }
        task = Task { [weak self] in
            var raw = ""
            var shownAt = Date.distantPast
            var messages = messages
            // 模型第一行写「联网」时停下这一轮，按三档决定联不联网，再问一次（只联网一次）。
            var maySearch = ask?.search != nil
            do {
                while true {
                    raw = ""
                    var wantsSearch = false
                    var handOff = false
                    // 每一轮请求都重新等：8 秒还没出字就标「响应较慢」。
                    let slowWatch = Task {
                        try await Task.sleep(nanoseconds: 8_000_000_000)
                        self?.responseSlow = true
                    }
                    defer { slowWatch.cancel() }
                    for try await piece in client.stream(messages) {
                        raw += piece
                        slowWatch.cancel()
                        guard let self else { continue }
                        if self.responseSlow { self.responseSlow = false }
                        if self.askSearching, !ModelOutput.clean(raw).isEmpty { self.askSearching = false }
                        if maySearch {
                            let probe = Prompts.searchProbe(ModelOutput.clean(raw), final: false)
                            if probe == .pending { continue }
                            if probe == .search { wantsSearch = true; break }
                        }
                        // 每设一次 streamingText 整个键盘就重画一遍，模型一秒能吐几十段：
                        // 面板收着（快速模式，看不到正文）就不设，展开时最多每 50 毫秒设一次。识意还没判断出方式时照常往下看。
                        let now = Date()
                        let show = self.aiExpanded && now.timeIntervalSince(shownAt) >= 0.05
                        guard show || (ask != nil && self.askKind == nil) else { continue }
                        let text = ModelOutput.clean(raw)
                        if let ask {
                            // 等第一行写出「改写 / 问答」再显示正文。
                            guard let split = Prompts.splitAsk(text, final: false, fallback: ask.fallbackAnswer) else { continue }
                            self.askDecided(split.answer ? .answer : .rewrite)
                            // 快模型判断是问答：停下，交给问答模型重新回答。
                            if split.answer && mayHandOff { handOff = true; break }
                            guard show || self.aiExpanded else { continue }
                            shownAt = now
                            self.streamingText = split.body
                        } else {
                            shownAt = now
                            self.streamingText = text
                        }
                    }
                    if maySearch, !wantsSearch, Prompts.searchProbe(ModelOutput.clean(raw), final: true) == .search {
                        wantsSearch = true
                    }
                    if handOff, let ask, let answerClient {
                        mayHandOff = false
                        client = answerClient
                        answeredByAnswerAPI = separateAnswer
                        messages = Prompts.ask(ask.question, context: ask.context, forceAnswer: true, search: maySearch)
                        continue
                    }
                    guard wantsSearch, let ask, let provider = ask.search, let self else { break }
                    maySearch = false
                    // 联网之后的回答也交给问答模型。
                    if let answerClient { client = answerClient; mayHandOff = false; answeredByAnswerAPI = separateAnswer }
                    // 联网的一定是问答：展开抽屉。三档：开且这一家同意过就直接联网，否则回答框里先问（禁止时提示去开启）。
                    self.askDecided(.answer)
                    guard await self.searchAllowed(provider) else {
                        try Task.checkCancellation()
                        messages = Prompts.ask(ask.question, context: ask.context, forceAnswer: true, offline: true)
                        continue
                    }
                    try Task.checkCancellation()
                    if provider.builtin {
                        // 千问、智谱：打开服务商自带的联网，只带问题原文再问一次。搜索在服务商那边，出字前流光小字写「正在用 … 联网搜索…」。
                        self.askSearching = true
                        client = LLMClient(settings: self.settings.forAnswers, apiKey: SettingsStore.answerKey(for: self.settings), webSearch: true)
                        messages = Prompts.ask(ask.question, context: "", forceAnswer: true, builtinSearch: true)
                        continue
                    }
                    // Kimi：流光小字写「正在联网搜索…」，键盘拿问题原文去搜。
                    self.askSearching = true
                    let search = WebSearch(settings: self.settings.forAnswers, apiKey: SettingsStore.answerKey(for: self.settings))
                    let results: String
                    do {
                        results = WebSearch.digest(try await search.search(ask.question))
                    } catch {
                        if Task.isCancelled { throw error }
                        results = ""
                    }
                    self.askSearching = false
                    messages = Prompts.ask(ask.question, context: ask.context, forceAnswer: true,
                                           results: results.isEmpty ? L("（联网搜索失败或没有搜到，按已有知识回答，并说明可能不是最新信息。）", "(The web search failed or found nothing. Answer from what you know and say it may be out of date.)", "（検索に失敗したか結果がありません。手持ちの知識で答え、最新でない可能性を伝えてください。）") : results)
                }
                guard let self else { return }
                let cleaned = ModelOutput.clean(raw)
                let split = ask.map { Prompts.splitAsk(cleaned, final: true, fallback: $0.fallbackAnswer) } ?? nil
                let result = split?.body ?? cleaned
                if let split { self.askDecided(split.answer ? .answer : .rewrite) }
                if result.isEmpty {
                    self.errorMessage = L("模型没有返回内容。", "The model returned nothing.", "モデルから応答がありませんでした。")
                    self.endQuickMode(.failed)
                    record(ok: false)
                } else {
                    record(ok: true)
                    // 试用结束后只有成功拿到结果才算一次；没网、报错、点停止都不算。
                    AIAccess.recordUse()
                    self.refreshAIAccess()
                    var updated = pending
                    if let ask, let kind = self.askKind {
                        self.appendAsk(result, kind: kind, question: ask.question, context: ask.context, to: &updated)
                    } else {
                        updated.append(result)
                    }
                    if updated.mode == .write, ask == nil {
                        updated.conversation.append(.assistant(result))
                    }
                    self.session = updated
                    self.finished = Finished(origin: self.runOrigin ?? .polish, at: Date())
                    self.resultUse = nil
                    self.resultUses = []
                    self.resultStale = false
                    SessionStore.save(updated)
                    if let source = self.quickSource {
                        let unchanged = self.readField().text == source
                        if unchanged { self.replace() }
                        self.endQuickMode(unchanged ? .replaced : .changed)
                    }
                }
            } catch {
                if !Task.isCancelled, let self {
                    record(ok: false)
                    let kind = LLMFailure.of(error)
                    let provider = client.settings.providerName
                    self.failure = kind
                    self.failureProvider = provider
                    self.failureOnAnswerAPI = answeredByAnswerAPI
                    self.failureDetail = LLMFailure.detail(error, provider: provider)
                    // 已经出了字：保留已出的部分，不当整张出错卡（ER3）。
                    let shown = ModelOutput.clean(raw)
                    let split = ask.flatMap { Prompts.splitAsk(shown, final: true, fallback: $0.fallbackAnswer) }
                    let partial = split?.body ?? shown
                    if !partial.isEmpty, !partial.hasPrefix("联网") {
                        self.partialResult = (partial, split.map(\.answer))
                    }
                    self.errorMessage = kind.title(provider: provider)
                    self.endQuickMode(.failed)
                }
            }
            self?.isRunning = false
            self?.responseSlow = false
            self?.runOrigin = nil
            self?.askRunning = false
            if self?.askSearching == true { self?.askSearching = false }
            if self?.askKind != nil { self?.askKind = nil }
        }
    }

    func clearFailure() {
        failure = nil
        failureDetail = nil
        failureDetailShown = false
        partialResult = nil
    }

    /// 出错卡、没写完那一行的「重试」：把上一次的请求原样再发一次，结果作为新的一版进翻页。
    func retryLastRun() {
        guard let last = lastRun, !isRunning else { return }
        errorMessage = nil
        clearFailure()
        start(from: last.origin) { run(last.messages, pending: last.pending, ask: last.ask) }
    }

    /// 出错卡的「去设置」：打开 App 接口页（问答接口出的错打开问答页）。
    func openAPISettings() {
        openContainingApp(failureOnAnswerAPI ? "enclave://api-answer" : "enclave://api")
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
        resolveSearchPrompt(allow: false)
        isRunning = false
        runOrigin = nil
        askRunning = false
        if askKind != nil { askKind = nil }
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

    func loadDebugSession(_ debug: EditSession) {
        session = debug
    }

    /// 截图用：识意生成中，已经判断出类型，还没出字（QA10）。
    func loadDebugAskRunning(_ kind: AskMode) {
        isRunning = true
        runOrigin = .ask
        askRunning = true
        askKind = kind
        streamingText = ""
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
        resultUses = []
        SessionStore.save(session)
    }

    /// 输入框的文字变了（系统通知）：和当前结果对不上就把卡片变灰。
    func fieldDidChange() {
        refreshHostState()
        // 对方 App 清空或改了输入框（比如发送后）：重新判断句首大写。
        if !isComposing { updateAutoShift() }
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
        if askSelected { askSelected = false }
        storeInstruction(text, caret: text.count)
    }

    func insertInInstruction(_ text: String) {
        // 全选着：打的字直接盖掉原来的。
        if askSelected {
            setInstruction(text)
            return
        }
        let split = instruction.index(instruction.startIndex, offsetBy: instructionCaret)
        storeInstruction(String(instruction[..<split]) + text + String(instruction[split...]),
                         caret: instructionCaret + text.count)
    }

    func deleteInInstruction() {
        if askSelected {
            setInstruction("")
            return
        }
        guard instructionCaret > 0 else { return }
        let end = instruction.index(instruction.startIndex, offsetBy: instructionCaret)
        let start = instruction.index(before: end)
        storeInstruction(String(instruction[..<start]) + String(instruction[end...]), caret: instructionCaret - 1)
    }

    func moveInstructionCaret(by offset: Int) {
        if askSelected { askSelected = false }
        instructionCaret = min(max(instructionCaret + offset, 0), instruction.count)
    }

    private func storeInstruction(_ text: String, caret: Int) {
        // 字改了，手动选的改写 / 问答就不再跟着。
        if askChoice != nil, text != askChoiceText { askChoice = nil }
        instruction = text
        instructionCaret = min(max(caret, 0), text.count)
        SharedStorage.defaults.set(text, forKey: Self.instructionKey)
    }

    // MARK: - 写入输入框

    /// AI 读输入框：有选中读选中的；没选中时读光标前后系统给的那段，
    /// 超过 100 字（打开「处理长文本」时 200 字）只读光标前按整句截出来的一段（见 FieldSpan）。
    /// remember：这次读到的就是要发给 AI 的那段，记下来，替换时照它删（见 readSpan）。
    func readField(remember: Bool = false) -> (text: String, isSelection: Bool) {
        guard let proxy else { return ("", false) }
        if let selected = proxy.selectedText, !selected.isEmpty {
            if remember { readSpan = nil }
            return (selected, true)
        }
        let span = fieldSpan(proxy)
        if remember { readSpan = span }
        return (span.text, false)
    }

    /// 这次处理输入框里的哪一段：光标前取 before 个字、光标后取 after 个字。替换时按这两个数删，读不到的字一个不动。
    private func fieldSpan(_ proxy: UITextDocumentProxy) -> FieldSpan {
        FieldSpan(before: proxy.documentContextBeforeInput ?? "", after: proxy.documentContextAfterInput ?? "",
                  longText: settings.longText)
    }

    /// 用当前版本替换输入框内容（有选中时只替换选中部分）。
    func replace() {
        endCoach()
        guard let text = session?.current, let proxy else { return }
        let field = readField()
        if field.isSelection {
            proxy.insertText(text)
            readSpan = FieldSpan(written: text)
            recordEdit(inserted: text, original: field.text, use: .replaced)
            return
        }
        guard let cleared = clearField(proxy) else {
            showReplaceNote(.mismatch)
            return
        }
        proxy.insertText(text)
        readSpan = FieldSpan(written: text)
        if cleared.partial { showReplaceNote(.partial) }
        recordEdit(inserted: text, original: cleared.removed, use: .replaced)
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
        if edit.use == .replaced { readSpan = FieldSpan(written: edit.original) }
        redoStack.append(edit)
        resultUse = nil
        resultUses.remove(edit.use)
        updateUndoState()
    }

    func redo() {
        endCoach()
        guard let edit = redoStack.popLast(), let proxy else { return }
        swap(edit.original, for: edit.inserted, in: proxy)
        if edit.use == .replaced { readSpan = FieldSpan(written: edit.inserted) }
        undoStack.append(edit)
        resultUse = edit.use
        resultUses.insert(edit.use)
        updateUndoState()
    }

    /// 删掉光标前的 old，再写入 new。
    private func swap(_ old: String, for new: String, in proxy: UITextDocumentProxy) {
        for _ in 0..<old.count { proxy.deleteBackward() }
        if !new.isEmpty { proxy.insertText(new) }
    }

    /// 长按结果卡：打开分词面板，拆当前版本。
    func openWordPanel() {
        guard hasResult, let text = session?.current, !text.isEmpty else { return }
        endCoach()
        wordPanelText = text
        keyFeedback(for: .space)
        openPanel(.words)
    }

    /// 分词面板的「插入」：直接把字放进输入框，面板淡出。不动结果卡左边的键（不出用过的小绿勾动画）。
    func insertWords(_ text: String) {
        guard !text.isEmpty, let proxy else { return }
        markAskUsed()
        proxy.insertText(text)
        keyFeedback(for: .space)
        closeWordPanel()
    }

    /// 分词面板的「复制」：复制选中的词，右边复制图标照旧提示一下，面板淡出。
    func copyWords(_ text: String) {
        guard !text.isEmpty else { return }
        markAskUsed()
        UIPasteboard.general.string = text
        keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.copied = false }
        }
        closeWordPanel()
    }

    /// 分词面板 0.15 秒淡出，淡完再收起、键盘高度和结果卡回到打开前。
    func closeWordPanel() {
        guard keysPanel == .words, !wordPanelFading else { return }
        withAnimation(.easeOut(duration: 0.15)) { wordPanelFading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if self.keysPanel == .words { self.closePanel() }
                self.wordPanelFading = false
            }
        }
    }

    /// 卡片上的复制图标：复制当前版本。
    func copy() {
        guard hasResult, let text = session?.current else { return }
        markAskUsed()
        UIPasteboard.general.string = text
        keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.copied = false }
        }
    }

    private func recordEdit(inserted: String, original: String, use: ResultUse) {
        markAskUsed()
        resultUse = use
        resultUses.insert(use)
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
    /// 删掉发给 AI 的那段（readSpan），先核对光标前后还是它；对不上返回 nil。返回删完后两边是否还有字：系统对长文本只给光标附近的一段，
    /// 默认又只读光标前 100 字左右；没读到的部分不能跟着删，不然润色只看了一段、却把整段换掉，前后的字就丢了。
    private func clearField(_ proxy: UITextDocumentProxy) -> (removed: String, partial: Bool)? {
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        // 照发给 AI 时读到的那段删，不在这时重算：系统每次给的光标前文字长短不一，重算出来的起点会在句子间跳。
        let span = readSpan.flatMap { $0.matches(before: before, after: after) ? $0 : nil }
            ?? (readSpan == nil ? fieldSpan(proxy) : nil)
        guard let span else { return nil }
        if span.afterCount > 0 {
            proxy.adjustTextPosition(byCharacterOffset: span.afterCount)
        }
        for _ in 0..<(span.beforeCount + span.afterCount) { proxy.deleteBackward() }
        let restBefore = proxy.documentContextBeforeInput ?? ""
        let restAfter = proxy.documentContextAfterInput ?? ""
        return (span.text, !restBefore.isEmpty || !restAfter.isEmpty)
    }

    /// partial：系统对长文本只给光标附近的一段，没读到的没动。mismatch：读完之后输入框被改过（光标挪了、又打了字），
    /// 对不上发给 AI 的那段，不替换，免得删错地方。快速模式抽屉是收着的：展开给人看到这句提示。
    private func showReplaceNote(_ note: ReplaceNote) {
        if !aiExpanded { setAIExpanded(true) }
        withAnimation(.easeOut(duration: 0.15)) { replaceNote = note }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard self?.replaceNote == note else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.replaceNote = nil }
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

/// 通讯录人名转拼音（CFStringTransform 很慢）每次弹出都要做一遍，记下来。读通讯录的回调不一定在主线程，用锁保护。
private enum ContactPinyin {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func of(_ name: String) -> String {
        lock.lock()
        let cached = cache[name]
        lock.unlock()
        if let cached { return cached }
        let pinyin = CommonWordStore.pinyin(of: name)
        lock.lock()
        cache[name] = pinyin
        lock.unlock()
        return pinyin
    }
}
