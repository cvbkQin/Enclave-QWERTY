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

    /// 对方输入框通知变了：抽屉开着、正打进识意框时，光标前后的文字或选中的文字变了，就算用户点了上面的输入框，打字换回对方输入框。
    /// 只比字数不够：长文本时系统只给光标附近固定长度的一截，挪光标前后字数常常一样（0.91 真机上备忘录切不过去）。
    /// 键盘刚弹出（还没记过）、键盘自己刚插过字替换过的都不算；在卡片里改字时不动。
    func hostSelectionChanged() {
        let now = currentHostCaret()
        let previous = hostCaret
        hostCaret = now
        guard aiExpanded, target == .instruction, Date().timeIntervalSince(lastProxyUse) > 0.5,
              let previous, previous != now
        else { return }
        if isComposing { finishComposition() }
        if aiRow != nil { aiRow = nil }
        if askSelected { askSelected = false }
        hostFocused = true
        target = .host
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
        if target != .instruction { target = .instruction }
    }

    /// 识意框里有话才能执行。
    var canAsk: Bool { !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// ✨ 现在显示的方式：手动选过、框里的字没改就是那一种，否则自动（nil）。
    var askButtonMode: AskMode? { askChoice != nil && instruction == askChoiceText ? askChoice : nil }

    /// 识意展开时的 ✨：mode 为 nil 让模型自己判断，改写 / 问答是按住滑出来选的（或上次手动选的）。
    func askTapped(_ mode: AskMode?) {
        guard !isRunning, canAsk else { return }
        guard passGate(then: { [weak self] in self?.askTapped(mode) }) else { return }
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
        let context = edited ?? CommandParser.parse(readField(remember: true).text).content
        if edited == nil { dropSession(unlessItBelongsTo: context) }
        let pending = session ?? (context.isEmpty
            ? EditSession(mode: .write, original: question)
            : EditSession(mode: .polish, original: context))
        let search = mode != .rewrite ? settings.answerSearch : nil
        if mode != .rewrite {
            guard passAnswerConsent(then: { [weak self] in self?.askTapped(mode) }) else { return }
        }
        let request = AskRequest(question: question, forced: mode,
                                 fallbackAnswer: mode.map { $0 == .answer } ?? context.isEmpty,
                                 context: context, search: search)
        let messages = Prompts.ask(question, context: context, forceAnswer: mode.map { $0 == .answer }, search: search != nil,
                                   answerStyle: settings.selectedAnswerStyle, tendency: settings.tendency)

        // 抽屉先不展开：收起时按快速模式开始，判断是问答再展开（askDecided）。
        if !aiExpanded { beginQuickMode(source: readField().text) }
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

    /// 结果卡左边模式控件「⇄ 切换」（SW4）：同一句、同样的原文换另一种方式重做，结果作为新的一版进翻页。
    func switchAskMode() {
        guard !isRunning, let session, session.currentIsAsk, let source = session.currentAskSource else { return }
        guard passGate(then: { [weak self] in self?.switchAskMode() }) else { return }
        reload()
        guard checkCanAsk() else { return }
        let target: AskMode = session.currentIsAnswer ? .rewrite : .answer
        if target == .answer {
            guard passAnswerConsent(then: { [weak self] in self?.switchAskMode() }) else { return }
        }
        // 新的一版，不顶掉现在这一版。
        lastAsk = nil
        let search = target == .answer ? settings.answerSearch : nil
        let request = AskRequest(question: source.question, forced: target, fallbackAnswer: target == .answer,
                                 context: source.context, search: search)
        let messages = Prompts.ask(source.question, context: source.context, forceAnswer: target == .answer, search: search != nil,
                                   answerStyle: settings.selectedAnswerStyle, tendency: settings.tendency)
        start(from: .ask) { run(messages, pending: session, ask: request) }
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
