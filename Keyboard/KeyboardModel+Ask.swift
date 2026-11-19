import SwiftUI

/// AI 栏往上展开的一行（QA1–QA14）：「润色 ▴」展开提示词标签，「识意 ▾」展开一个输入框，问问题或提要求。
/// 识意展开时 ✨ 按框里的话执行：模型先判断是改写还是问答，问答展开抽屉看回答，改写跟着快速模式走。
extension KeyboardModel {
    /// 不在卡片里改字时打字去哪：识意展开着就进识意框，否则进对方的输入框。
    var restingTarget: InputTarget { aiExpanded && !hostFocused ? .instruction : .host }

    /// 记下对方输入框光标前后的文字，用来判断光标是不是被挪了。
    func recordHostCaret() {
        hostCaret = currentHostCaret()
    }

    private func currentHostCaret() -> HostCaret {
        HostCaret(before: proxy?.documentContextBeforeInput ?? "", after: proxy?.documentContextAfterInput ?? "",
                  selected: proxy?.selectedText ?? "")
    }

    /// 对方输入框通知变了：抽屉开着、正打进识意框时，就算用户点了上面的输入框，打字换回对方输入框（识意框变成未激活的灰底）。
    /// 不比光标挪没挪：微信里光标本来就在末尾，点一下光标不动；长文本时系统只给光标附近一截，字数也常常不变。
    /// 点输入框时系统总会通知一次，这一下就够了。不算的：键盘刚弹出后的第一次通知（hostCaret 还没记）、
    /// 刚展开抽屉或刚点识意框 0.8 秒内（键盘变高、换焦点带出来的）、键盘自己刚改过对方输入框 0.5 秒内；在卡片里改字时不动。
    func hostSelectionChanged() {
        let previous = hostCaret
        hostCaret = currentHostCaret()
        guard aiExpanded, target == .instruction, previous != nil,
              Date().timeIntervalSince(lastProxyUse) > 0.5, Date().timeIntervalSince(askFocusedAt) > 0.8
        else { return }
        commitTopCandidates()
        if aiRow != nil { aiRow = nil }
        if askSelected { askSelected = false }
        hostFocused = true
        target = .host
    }

    /// 点了回答卡的「替换」「插入」：文字已经写进输入框，打字和回车回到输入框，回车直接发送，不再在识意框里又跑一次润色 / 问答。
    /// （自己刚改过对方输入框，系统那次光标通知被 0.5 秒的保护挡掉了，hostSelectionChanged 不会切。）
    func focusHostAfterResult() {
        guard target == .instruction else { return }
        commitTopCandidates()
        if aiRow != nil { aiRow = nil }
        if askSelected { askSelected = false }
        hostFocused = true
        target = .host
    }

    /// 识意框里拼音还没选字就离开：和按空格一样上屏第一个候选（一次只选得掉一段就接着选），不留下一串字母。
    private func commitTopCandidates() {
        var rounds = 0
        while isComposing, chineseMode, !candidates.isEmpty, rounds < 10 {
            selectCandidate(0)
            rounds += 1
        }
        if isComposing { finishComposition() }
        dismissPredictions()
    }

    /// 点 AI 栏的风格键：展开时整块下半格换成这一种的风格一排，收起时浮在 AI 栏上面；再点自己换回来。
    func toggleRow(_ row: AIRow) {
        endCoach()
        if target == .card { finishCardEdit() }
        finishComposition()
        aiRow = aiRow == row ? nil : row
    }

    /// 点识意框：打字回到框里，取消全选；开着的风格一排收回去。
    func focusAsk() {
        if target == .card { finishCardEdit() }
        if aiRow != nil { aiRow = nil }
        if askSelected { askSelected = false }
        hostFocused = false
        askFocusedAt = Date()
        if target != .instruction { target = .instruction }
    }

    /// 识意框里有话才能执行。
    var canAsk: Bool { !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// ✨ 现在显示的方式：手动选过、框里的字没改就是那一种，否则自动（nil）。
    var askButtonMode: AskMode? { askChoice != nil && instruction == askChoiceText ? askChoice : nil }

    /// 识意展开时的 ✨：mode 为 nil 让模型自己判断，改写 / 问答是按住滑出来选的（或上次手动选的）。
    /// contextOverride：收着时点「问答」，问的就是输入框里的话，不再把它当上下文带一遍（传 ""）。
    func askTapped(_ mode: AskMode?, contextOverride: String? = nil) {
        guard !isRunning, canAsk else { return }
        let answerStyle = runAnswerStyleOverride
        guard passGate(then: { [weak self] in
            self?.runAnswerStyleOverride = answerStyle
            self?.askTapped(mode, contextOverride: contextOverride)
            self?.runAnswerStyleOverride = nil
        }) else { return }
        #if DEBUG
        if debugFakeRun { coachTapped(.run); fakeCoachRun(); return }
        #endif
        coachTapped(.run)
        if target == .card { finishCardEdit() }
        finishComposition()
        if askSelected { askSelected = false }
        if askChoice != mode { askChoice = mode }
        askChoiceText = instruction
        reload()
        guard checkCanAsk() else { return }

        let question = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // 卡片上是手改过的一版就拿它当原文，否则读输入框此刻的内容；输入框空就不带上下文。
        let edited = session?.currentIsEdited == true ? session?.current : nil
        let context = contextOverride ?? edited ?? CommandParser.parse(readField(remember: true).text).content
        if edited == nil { dropSession(unlessItBelongsTo: context) }
        let pending = session ?? (context.isEmpty
            ? EditSession(mode: .write, original: question)
            : EditSession(mode: .polish, original: context))
        let search = mode != .rewrite ? settings.answerSearch : nil
        if mode != .rewrite {
            guard passAnswerConsent(then: { [weak self] in
                self?.runAnswerStyleOverride = answerStyle
                self?.askTapped(mode, contextOverride: contextOverride)
                self?.runAnswerStyleOverride = nil
            }) else { return }
        }
        let request = AskRequest(question: question, forced: mode,
                                 fallbackAnswer: mode.map { $0 == .answer } ?? context.isEmpty,
                                 context: context, search: search)
        let messages = Prompts.ask(question, context: context, forceAnswer: mode.map { $0 == .answer }, search: search != nil,
                                   answerStyle: answerStyle ?? settings.selectedAnswerStyle, tendency: settings.tendency)

        // 抽屉先不展开：收起时按快速模式开始，判断是问答再展开（askDecided）。
        if !aiExpanded { beginQuickMode(source: readField().text) }
        askAuto = mode == nil
        start(from: .ask) { run(messages, pending: pending, ask: request) }
        if !isRunning {
            quickSource = nil
            clearQuickStatus()
            setAIExpanded(true)
        }
    }

    /// 没开完全访问、没配置接口：展开抽屉把原因写在卡片上。
    private func checkCanAsk() -> Bool {
        errorMessage = nil
        notice = nil
        guard hasFullAccess, settings.isConfigured else {
            errorMessage = hasFullAccess ? LLMError.notConfigured.errorDescription
                : L("需要在 设置 › 通用 › 键盘 › 键盘 › 飞地输入法 里打开「允许完全访问」才能联网。", "Turn on Allow Full Access in Settings › General › Keyboard › Keyboards › Enclave to connect.", "通信するには、設定 › 一般 › キーボード › キーボード › Enclave で「フルアクセスを許可」をオンにしてください。")
            setAIExpanded(true)
            return false
        }
        return true
    }

    /// 模型写出了类型：问答就展开抽屉（不再替换输入框）；改写照常，收起时生成完直接替换。
    func askDecided(_ kind: AskMode) {
        guard askKind != kind else { return }
        askKind = kind
        guard kind == .answer else { return }
        if quickSource != nil {
            quickSource = nil
            clearQuickStatus()
        }
        if !aiExpanded { aiExpanded = true }
    }

    /// 「识意」的结果进历史：同一句换了一种方式重做，新结果顶掉上一条（上一条用过就保留）；同一种方式照常新增。
    func appendAsk(_ result: String, kind: AskMode, question: String, context: String, to session: inout EditSession) {
        var replacing = false
        if let last = lastAsk, last.question == question, last.kind != kind, !last.used,
           last.index == session.versions.count - 1 {
            replacing = true
        }
        session.appendAsk(result, answer: kind == .answer, replacingLast: replacing,
                          source: EditSession.AskSource(question: question, context: context))
        lastAsk = LastAsk(question: question, kind: kind, index: session.currentIndex)
    }

    /// 点润色键的名字（AK1、AK2、AK4）。收着时就是快速润色（✨）；展开时按当前润色风格改输入框里的话，识意框里写的要求一起带上。
    /// 输入框里没有字（也没有手改过的一版）时不调用 AI，只提示一句（AK3）。生成中点了是停止。
    func polishKeyTapped() {
        endCelebration()
        if isRunning { stop(); return }
        lastRunPin = nil
        // 有待回的复制、输入框空（情况 ①③）：润色键整颗是「帮回」，点了就帮回。
        if polishKeyIsHelp {
            startHelpReply()
            return
        }
        runPolish()
    }

    private func runPolish() {
        guard aiExpanded else {
            sparkleTapped()
            return
        }
        if target == .card { finishCardEdit() }
        finishComposition()
        if aiRow != nil { aiRow = nil }
        let parsed = CommandParser.parse(readField().text)
        // 卡上是手改过的一版、帮回写的一版（还没放进输入框）：润色它。
        if parsed.content.isEmpty, parsed.instruction.isEmpty, session?.currentIsEdited != true, session?.currentIsReply != true {
            showKeysToast(L("输入框里没有要改的话，想问问题请点「问答」", "Nothing to edit in the text field. To ask a question, tap Ask.",
                            "入力欄に直す文章がありません。質問するときは「質問」をタップ"))
            return
        }
        let style = runStyleOverride
        guard passGate(then: { [weak self] in
            self?.runStyleOverride = style
            self?.runPolish()
            self?.runStyleOverride = nil
        }) else { return }
        #if DEBUG
        if debugFakeRun { coachTapped(.run); fakeCoachRun(); return }
        #endif
        coachTapped(.run)
        if askSelected { askSelected = false }
        var extra = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // 识意框里是点「问答」时自动填进去的那句（问题本身），不是要求：只改写输入框里的话（v308，FT13）。
        if let auto = askAutoFill, extra == auto { extra = "" }
        start(from: .polish) { execute(extraInstruction: extra) }
    }

    /// 点问答键的名字（AK1、AK2、AK4）。
    /// 展开时：回答识意框里的问题；框是空的就把光标放进框里、提示先写问题。
    /// 收着时：回答卡展开，把输入框里的话当问题回答，这句同时填进识意框（输入框不动）；输入框也空就只展开、光标进识意框。
    func askKeyTapped() {
        endCelebration()
        if isRunning { stop(); return }
        lastRunPin = nil
        runAsk()
    }

    private func runAsk() {
        if aiRow != nil { aiRow = nil }
        if !aiExpanded {
            if target == .card { finishCardEdit() }
            finishComposition()
            let text = CommandParser.parse(readField().text).content
            setAIExpanded(true)
            guard !text.isEmpty else {
                focusAsk()
                showKeysToast(L("写下想问的问题，再点「问答」", "Type your question, then tap Ask.", "質問を書いてから「質問」をタップ"))
                return
            }
            setInstruction(text)
            askAutoFill = text.trimmingCharacters(in: .whitespacesAndNewlines)
            coachTapped(.ask)
            askTapped(.answer, contextOverride: "")
            return
        }
        guard canAsk else {
            focusAsk()
            showKeysToast(L("先在下面的框里写问题，再点「问答」", "Type your question in the box below, then tap Ask.",
                            "下の欄に質問を書いてから「質問」をタップ"))
            return
        }
        coachTapped(.ask)
        askTapped(.answer)
    }

    /// 点 AI 栏上固定的风格键（AK5）：按这个风格执行一次，不改润色键 / 问答键当前选的风格。生成中点了是停止。
    func pinTapped(_ style: StylePreset, answer: Bool) {
        pinMenu = nil
        endCelebration()
        if isRunning { stop(); return }
        lastRunPin = style.id
        if answer {
            runAnswerStyleOverride = style
            runAsk()
            runAnswerStyleOverride = nil
        } else {
            runStyleOverride = style
            runPolish()
            runStyleOverride = nil
        }
    }

    /// 下拉框里的图钉、长按固定键的「取消固定」：固定 / 取消固定，满 5 个提示。
    func togglePin(_ style: StylePreset) {
        var full = false
        updateSettings { full = !$0.togglePin(style.id) }
        if full {
            if aiRow != nil {
                // 下拉框开着：提示写在下拉框底部那一行（变红 1.8 秒）。
                pinLimitHit = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.pinLimitHit = false }
            } else {
                showKeysToast(L("最多固定 5 个", "You can pin up to 5", "固定できるのは 5 つまで"))
            }
        }
        if pinMenu != nil { pinMenu = nil }
    }

    // MARK: - 回车键里的识意（第 70 条）

    /// 回答卡展开、焦点在识意框时回车的样子。polish / ask：上段「↑ ✨ 润色」、下段「← 问答」在不在（功能关掉或不能用就没有）。
    struct EnterAI: Equatable {
        var polish: Bool
        var ask: Bool
        /// 识意框空着：灰色「识意」，点了不发请求。
        var empty: Bool
        var running: Bool
        /// 停止图标的高光绕圈（关了发光动画就不绕）。
        var moving: Bool
    }

    /// 回车键里还能不能润色 / 问答：和 AI 栏上那颗键一样，关掉或不能用就没有（第 68 条）。
    var enterPolishAvailable: Bool {
        #if DEBUG
        if debugEnterHides.contains(.rewrite) { return false }
        #endif
        return settings.showsPolishKey || debugUnblocked
    }

    var enterAskAvailable: Bool {
        #if DEBUG
        if debugEnterHides.contains(.answer) { return false }
        #endif
        return settings.showsAnswerKey || debugUnblocked
    }

    /// 回答卡展开、焦点在识意框：回车是识意；正在拼音时还是「确认」，润色、问答都关了是普通回车。
    var enterAI: EnterAI? {
        guard aiExpanded, target == .instruction, !isComposing else { return nil }
        let polish = enterPolishAvailable, ask = enterAskAvailable
        guard polish || ask else { return nil }
        return EnterAI(polish: polish, ask: ask, empty: !canAsk && !isRunning, running: isRunning,
                       moving: settings.polishAnimation)
    }

    /// 点回车（不管点在哪一段）= 识意：识意框的话交给 AI 自己判断改写还是回答。执行中点了是停止（第 67 条）。
    func enterAskTapped() {
        endCelebration()
        if isRunning { stop(); return }
        guard canAsk else {
            showKeysToast(L("先在框里写下要求或问题", "Type a request or question in the box first.", "先に欄に依頼か質問を書いてください"))
            return
        }
        lastRunPin = nil
        if aiRow != nil { aiRow = nil }
        askTapped(nil)
    }

    /// 按住回车 0.3 秒或拖动超过 16pt：弹出「上润色、左问答」的十字，先选中中间（识意）。
    func showEnterCross(for key: KeySpec, containerWidth: CGFloat, origin: CGPoint) -> Bool {
        guard let ai = enterAI, !ai.running, !ai.empty else { return false }
        enterCross = EnterCrossPopup(key: key, containerWidth: containerWidth, polish: ai.polish, ask: ai.ask, origin: origin)
        keyFeedback(for: .space)
        return true
    }

    func moveEnterCross(to point: CGPoint) {
        guard var popup = enterCross else { return }
        let choice = popup.choice(at: point)
        guard choice != popup.selected else { return }
        popup.selected = choice
        enterCross = popup
        // 进格时轻震一下（同 ABC 十字）。
        if choice != nil { keyFeedback(for: .space) }
    }

    /// 松手执行选中的那个；滑出十字松手是取消。
    func commitEnterCross() {
        guard let popup = enterCross else { return }
        enterCross = nil
        switch popup.selected {
        case .polish?: polishKeyTapped()
        case .ask?: askKeyTapped()
        case .auto?: enterAskTapped()
        case nil: break
        }
    }

    /// 识意框右边「使用联网查询」能不能出现（MG6）：正在显示没联网的问答，问答接口能联网，三档不是禁止。
    var canForceSearch: Bool {
        guard !isRunning, let session, session.currentIsAnswer, session.currentSearchedBy == nil,
              session.currentAskSource != nil, settings.answerSearch != nil else { return false }
        return (settings.webSearchMode ?? .off) != .off
    }

    /// 点「使用联网查询」：同一个问题强制联网重问，结果替换这条回答（MG7）。
    func forceWebSearch() {
        guard canForceSearch, let session, let source = session.currentAskSource, let provider = settings.answerSearch else { return }
        guard passGate(then: { [weak self] in self?.forceWebSearch() }) else { return }
        reload()
        guard checkCanAsk() else { return }
        guard passAnswerConsent(then: { [weak self] in self?.forceWebSearch() }) else { return }
        let request = AskRequest(question: source.question, forced: .answer, fallbackAnswer: true,
                                 context: source.context, search: provider, forceSearch: true)
        askAuto = false
        start(from: .ask) { run([], pending: session, ask: request) }
    }

    /// 替换、插入、复制过的那一版不会被顶掉。
    func markAskUsed() {
        guard let last = lastAsk, last.index == session?.currentIndex else { return }
        lastAsk?.used = true
    }

    #if DEBUG
    /// 截图用（-keyboardDebug ask…）：识意框里的示例问题。
    static let debugQuestion = "“看看”和“看一下”有区别吗"

    func loadDebugAsk(_ option: String) {
        debugUnblocked = true
        aiExpanded = true
        switch option {
        case "ask": setInstruction(Self.debugQuestion)
        case "askEmpty": setInstruction("")
        case "askSelected": setInstruction(Self.debugQuestion); askSelected = true
        case "askRewrite":
            setInstruction("翻成英文")
            askChoice = .rewrite
            askChoiceText = instruction
        case "askAnswerMode":
            setInstruction(Self.debugQuestion)
            askChoice = .answer
            askChoiceText = instruction
        case "askAnswer":
            setInstruction(Self.debugQuestion)
            var debug = EditSession(mode: .polish, original: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看")
            debug.appendAsk("意思差不多。「看看」更随意；「看一下」稍客气，像请对方花点时间。回领导用「看一下」更稳妥。",
                            answer: true, replacingLast: false)
            loadDebugSession(debug)
            aiExpanded = true
        case "askRewriteResult":
            setInstruction("翻成英文")
            var debug = EditSession(mode: .polish, original: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看")
            debug.append("文件我看过了，整体没问题，就是第三页有个数字好像不太对，麻烦你再核对一下。")
            debug.appendAsk("Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?",
                            answer: false, replacingLast: false)
            loadDebugSession(debug)
            aiExpanded = true
        case "askRunning":
            setInstruction(Self.debugQuestion)
            askChoice = .answer
            askChoiceText = instruction
            aiExpanded = true
            loadDebugAskRunning(.answer)
        default: break
        }
    }
    #endif
}
