import SwiftUI

/// AI 栏往上展开的一行（QA1–QA14）：「润色 ▴」展开提示词标签，「识意 ▾」展开一个输入框，问问题或提要求。
/// 识意展开时 ✨ 按框里的话执行：模型先判断是改写还是问答，问答展开抽屉看回答，改写跟着快速模式走。
extension KeyboardModel {
    /// 不在卡片里改字时打字去哪：识意展开着就进识意框，否则进对方的输入框。
    var restingTarget: InputTarget { aiRow == .ask ? .instruction : .host }

    /// 点「润色 ▴」「识意 ▾」：开这一行（另一行自动收起），再点自己收起。
    func toggleRow(_ row: AIRow) {
        endCoach()
        if target == .card { finishCardEdit() }
        finishComposition()
        let next: AIRow? = aiRow == row ? nil : row
        aiRow = next
        if next == .ask { moveInstructionCaret(by: instruction.count) }
        // 识意框里本来有字：展开时全选，直接打字就覆盖。
        let select = next == .ask && !instruction.isEmpty
        if askSelected != select { askSelected = select }
        let newTarget = restingTarget
        if target != newTarget { target = newTarget }
    }

    /// 识意框右端的 ×：只收起，框里的字留着。
    func closeAskRow() {
        guard aiRow == .ask else { return }
        toggleRow(.ask)
    }

    /// 点识意框：打字回到框里，取消全选。
    func focusAsk() {
        if target == .card { finishCardEdit() }
        if askSelected { askSelected = false }
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
        let search = settings.canWebSearch && mode != .rewrite
        let request = AskRequest(question: question, forced: mode,
                                 fallbackAnswer: mode.map { $0 == .answer } ?? context.isEmpty,
                                 context: context, search: search)
        let messages = Prompts.ask(question, context: context, forceAnswer: mode.map { $0 == .answer }, search: search)

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
    func appendAsk(_ result: String, kind: AskMode, question: String, to session: inout EditSession) {
        var replacing = false
        if let last = lastAsk, last.question == question, last.kind != kind, !last.used,
           last.index == session.versions.count - 1 {
            replacing = true
        }
        session.appendAsk(result, answer: kind == .answer, replacingLast: replacing)
        lastAsk = LastAsk(question: question, kind: kind, index: session.currentIndex)
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
        aiRow = .ask
        target = .instruction
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
