import SwiftUI
import UIKit

/// AI 帮回（T16）的一次：对方的话、写出来的几条、现在看哪条、哪条放进了输入框、在不在写。
/// 按方向重写、⌄ 多写一条都在同一次里，卡片上显示最近一轮（加上 ⌄ 多写的），所有轮都进历史。
struct HelpReplyState: Equatable {
    struct Reply: Equatable, Identifiable {
        var id = UUID()
        var styleID: UUID
        var name: String
        var text: String
        var round: Int
        var direction: String?
        var at: Date
    }

    enum Running: Equatable {
        /// 打勾的几种一起写（方向可空）。
        case all(direction: String?)
        /// ⌄ 里点了没勾的一种，多写这一条。
        case extra(name: String)
    }

    let historyID: String
    let date: Date
    var message: String
    var replies: [Reply] = []
    var history: [Reply] = []
    var index = 0
    /// 放进输入框的那条、放进去的字（再点别的语气时把它换掉）、什么时候放的。
    var insertedID: UUID?
    var insertedText: String?
    var insertedAt: Date?
    var round = 0
    var running: Running?
    /// 这一次写几条（生成中卡头「正在写 3 条…」）。
    var runningCount = 0
    var stopped = false
    var error: String?
    /// 写好的那一刻：键上白色对勾一笔画出，约 1.6 秒后 ^^ 淡回。
    var successAt: Date?

    var current: Reply? { replies.indices.contains(index) ? replies[index] : nil }
    var currentInserted: Bool { current != nil && current?.id == insertedID }
}

/// ^^ 键变帮回时的样子（KeyCapContext 里比较，变了才重画键帽）。
struct HelpKeyLook: Equatable {
    var running: Bool
    var moving: Bool
    var successAt: Date?
}

extension KeyboardModel {
    private static let helpDismissedKey = "helpReply.dismissedChangeCount"

    /// 问答接口开着、能用才有帮回（^^ 键不变、面板不显示「帮回」）。
    var helpReplyAvailable: Bool {
        (hasFullAccess || debugUnblocked) && (settings.showsAnswerKey || debugUnblocked)
    }

    /// ^^ 键现在是不是「帮回」：九宫格、没在打拼音、有新复制的内容（不读内容）、输入框里没字、没被打字收掉；
    /// 生成中和刚写好的 1.6 秒里一直是帮回。
    var helpKeyLook: HelpKeyLook? {
        guard !isComposing, helpReplyAvailable else { return nil }
        guard helpKeyHold || (clipboardHasNew && !helpDismissed && !hostHasText) else { return nil }
        return HelpKeyLook(running: helpReply?.running != nil, moving: settings.polishAnimation,
                           successAt: helpKeyHold ? helpReply?.successAt : nil)
    }

    /// 键盘出现时：这次的新复制被打字收掉过就不再变帮回（同一个 changeCount）。
    func refreshHelpOffer(changeCount: Int) {
        let dismissed = SharedStorage.defaults.object(forKey: Self.helpDismissedKey) as? Int
        let value = dismissed == changeCount
        if helpDismissed != value { helpDismissed = value }
    }

    /// 开始打字：^^ 键变回来，这份复制的内容不再提示帮回（下次复制新内容再变）。
    func dismissHelpOffer() {
        guard clipboardHasNew, !helpDismissed else { return }
        helpDismissed = true
        SharedStorage.defaults.set(UIPasteboard.general.changeCount, forKey: Self.helpDismissedKey)
    }

    /// 键盘自己写了剪贴板（复制结果、分词复制、复制一条记录）：不算新复制的内容，^^ 键变回来。
    func noteOwnCopy() {
        ClipboardHistory.lastChangeCount = UIPasteboard.general.changeCount
        if clipboardHasNew { clipboardHasNew = false }
    }

    // MARK: 入口

    /// 点 ^^ 键（帮回时）：生成中是停止；停了、出错了是用同一段话重写；否则读剪贴板开始。
    func helpKeyTapped() {
        if helpReply?.running != nil {
            stopHelpReply()
            return
        }
        if let state = helpReply, state.replies.isEmpty, state.stopped || state.error != nil {
            retryHelpReply()
            return
        }
        startHelpFromPasteboard(fromKey: true)
    }

    /// 剪贴板面板顶上「有新复制的内容」那一行的「帮回」。
    func helpFromClipboardPrompt() {
        startHelpFromPasteboard(fromKey: false)
    }

    /// 剪贴板记录里一条的「帮回」：用这条，挪到最前。
    func helpFromClip(_ item: ClipItem) {
        clipMenu = nil
        guard passHelpGates(then: { [weak self] in self?.helpFromClip(item) }) else { return }
        clipItems = ClipboardHistory.add(item.text)
        beginHelpReply(message: item.text, fromKey: false)
    }

    /// 这时才读剪贴板（系统「粘贴自…」横幅照常闪），存进剪贴板记录。读不到文字只提示一句。
    private func startHelpFromPasteboard(fromKey: Bool) {
        guard passHelpGates(then: { [weak self] in self?.startHelpFromPasteboard(fromKey: fromKey) }) else { return }
        let board = UIPasteboard.general
        let count = board.changeCount
        let text = (board.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ClipboardHistory.lastChangeCount = count
        clipboardHasNew = false
        guard !text.isEmpty else {
            showKeysToast(L("剪贴板里没有文字", "There's no text on the clipboard", "クリップボードにテキストがありません"))
            return
        }
        clipItems = ClipboardHistory.add(text)
        beginHelpReply(message: text, fromKey: fromKey)
    }

    /// 和问答一样先过提示卡（完全访问、隐私、没配置、次数、第一次连这个地址）。
    private func passHelpGates(then action: @escaping () -> Void) -> Bool {
        guard passGate(then: action) else { return false }
        return passAnswerConsent(then: action)
    }

    /// 面板收起，回答卡展开成绿色「AI 帮回」卡，用打勾的几种一起写。不往输入框贴原文。
    private func beginHelpReply(message: String, fromKey: Bool) {
        endCelebration()
        if isRunning { stop() }
        cancelHelpTask()
        if target == .card { finishCardEdit() }
        finishComposition()
        if keysPanel != nil { closePanel() }
        if aiRow != nil { aiRow = nil }
        helpMenuOpen = false
        helpReply = HelpReplyState(historyID: UUID().uuidString, date: Date(), message: message)
        helpKeyHold = fromKey
        // 下面的框是这次的回复方向：从空的开始。
        clearInstruction()
        setAIExpanded(true)
        // 打字还进对方输入框，点下面的框才写方向。
        if askSelected { askSelected = false }
        hostFocused = true
        if target != .host { target = .host }
        reload()
        runHelp(styles: settings.checkedReplyStyles, direction: nil)
    }

    // MARK: 卡片上的操作

    /// 「↻ 按这个重写」/ 打着方向按回车：3 条都按这个方向重写，再算一次问答。
    func helpRewriteTapped() {
        guard let state = helpReply, state.running == nil else { return }
        let direction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !direction.isEmpty else {
            showKeysToast(L("先在下面写想怎么回", "Type how you'd like to reply first", "どう返したいかを先に書いてください"))
            return
        }
        guard passHelpGates(then: { [weak self] in self?.helpRewriteTapped() }) else { return }
        finishComposition()
        reload()
        runHelp(styles: settings.checkedReplyStyles, direction: direction)
    }

    /// 停了、出错后再点「帮回」：同一段话、同一个方向再写一次。
    func retryHelpReply() {
        guard let state = helpReply, state.running == nil else { return }
        guard passHelpGates(then: { [weak self] in self?.retryHelpReply() }) else { return }
        reload()
        let direction = state.replies.first?.direction ?? lastHelpDirection
        runHelp(styles: settings.checkedReplyStyles, direction: direction)
    }

    /// ⌄ 里点了一种：卡上已经有就翻到它；没有就用它多写一条，成为最后一个标签。
    func helpStylePicked(_ style: StylePreset) {
        helpMenuOpen = false
        guard var state = helpReply, state.running == nil else { return }
        if let index = state.replies.firstIndex(where: { $0.styleID == style.id }) {
            state.index = index
            helpReply = state
            replaceInsertedIfNeeded()
            return
        }
        guard passHelpGates(then: { [weak self] in self?.helpStylePicked(style) }) else { return }
        runHelp(styles: [style], direction: state.replies.first?.direction, extra: true)
    }

    /// 点标签、左右滑：换一条。上屏过的话，输入框里那条跟着换成这条。
    func helpSelect(_ index: Int) {
        guard var state = helpReply, state.replies.indices.contains(index), index != state.index else { return }
        state.index = index
        helpReply = state
        keyFeedback(for: .space)
        replaceInsertedIfNeeded()
    }

    func helpTurn(_ offset: Int) {
        guard let state = helpReply, !state.replies.isEmpty else { return }
        let next = state.index + offset
        // 滑到头回弹：不循环。
        guard state.replies.indices.contains(next) else { return }
        helpSelect(next)
    }

    /// 点正文或左边「↵ 上屏」：放进对方输入框。上屏过别的那条时把它换掉（光标前还是它才换）。
    func helpInsert() {
        guard var state = helpReply, state.running == nil, let reply = state.current, let proxy = editProxy else { return }
        if state.insertedID == reply.id { return }
        if let old = state.insertedText, (proxy.documentContextBeforeInput ?? "").hasSuffix(old) {
            for _ in 0..<old.count { proxy.deleteBackward() }
        }
        proxy.insertText(reply.text)
        state.insertedID = reply.id
        state.insertedText = reply.text
        state.insertedAt = Date()
        helpReply = state
        keyFeedback(for: .space)
        // 打字和回车回到对方输入框，回车直接发送。
        focusHostAfterResult()
        recordHelpHistory()
        UIAccessibility.post(notification: .announcement, argument: L("已上屏", "Inserted", "入力しました"))
    }

    private func replaceInsertedIfNeeded() {
        guard let state = helpReply, state.insertedID != nil, !state.currentInserted else { return }
        helpInsert()
    }

    /// 点停止：立即取消，不算次数；卡片「已停止 · 再点「帮回」重写」。
    func stopHelpReply() {
        guard var state = helpReply, state.running != nil else { return }
        cancelHelpTask()
        state.running = nil
        state.stopped = true
        helpReply = state
        UIAccessibility.post(notification: .announcement, argument: L("已停止", "Stopped", "停止しました"))
    }

    /// 收起抽屉、开始别的润色 / 问答：这次帮回结束。
    func endHelpReply() {
        cancelHelpTask()
        helpMenuOpen = false
        helpKeyHold = false
        if helpReply != nil { helpReply = nil }
    }

    private func cancelHelpTask() {
        helpTask?.cancel()
        helpTask = nil
        helpToken &+= 1
    }

    private func clearInstruction() {
        if !instruction.isEmpty { setInstruction("") }
    }

    /// 上一轮的方向（重写时清空了框也接着用）。
    private var lastHelpDirection: String? {
        helpReply?.history.last?.direction
    }

    // MARK: 请求

    /// 用问答接口一次写几条（每种风格一条），不联网。成功才算一次问答；停止、出错不算。
    private func runHelp(styles: [StylePreset], direction: String?, extra: Bool = false) {
        guard var state = helpReply, !styles.isEmpty else { return }
        let direction = direction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usedDirection = direction?.isEmpty == false ? direction : nil
        let key = SettingsStore.answerKey(for: settings)
        guard BuiltinAPI.take(.answer, key: key) else {
            state.error = BuiltinAPI.limitMessage(.answer)
            helpReply = state
            return
        }
        let client = LLMClient(settings: settings.forAnswers, apiKey: key)
        state.running = extra ? .extra(name: styles[0].displayName) : .all(direction: usedDirection)
        state.runningCount = styles.count
        state.stopped = false
        state.error = nil
        state.successAt = nil
        helpReply = state
        cancelHelpTask()
        let token = helpToken
        let messages = HelpReply.messages(message: state.message, styles: styles, direction: usedDirection ?? "")
        let started = Date()
        let separate = settings.usesAnswerEndpoint
        func record(ok: Bool, error: String? = nil) {
            UsageStats.recordPolish(ms: Int(Date().timeIntervalSince(started) * 1000), ok: ok, styleID: nil,
                                    mainAPI: !separate, styleName: L("帮回", "Help Reply", "返信アシスト"),
                                    model: client.settings.model, error: error)
        }
        helpTask = Task { [weak self] in
            var raw = ""
            do {
                for try await piece in client.stream(messages) { raw += piece }
                try Task.checkCancellation()
                guard let self, self.helpToken == token, var state = self.helpReply else { return }
                let texts = HelpReply.parse(ModelOutput.clean(raw), count: styles.count)
                state.running = nil
                if texts.isEmpty {
                    record(ok: false, error: UsageStats.Request.Failure.empty)
                    state.error = L("模型没有返回内容。", "The model returned nothing.", "モデルから応答がありませんでした。")
                    self.helpReply = state
                    return
                }
                record(ok: true)
                // 提示词页每种帮回风格的本周次数。
                for style in styles { DailyStats.add("reply.style.\(style.id.uuidString)") }
                DailyStats.flush()
                AIAccess.recordUse()
                self.refreshAIAccess()
                state.round += 1
                let now = Date()
                let replies = zip(styles, texts).map { style, text in
                    HelpReplyState.Reply(styleID: style.id, name: style.displayName, text: text, round: state.round,
                                         direction: usedDirection, at: now)
                }
                if extra {
                    state.replies += replies
                    state.index = state.replies.count - 1
                } else {
                    state.replies = replies
                    state.index = 0
                }
                state.history += replies
                state.successAt = now
                self.helpReply = state
                self.recordHelpHistory()
                UIAccessibility.post(notification: .announcement,
                                     argument: L("写好了 \(replies.count) 条回复", "\(replies.count) replies ready", "返信を \(replies.count) 件作成しました"))
                // 白色对勾画完（600ms）后停一会儿，约 1.6 秒后 ^^ 淡回。
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    guard let self, self.helpReply?.successAt == now else { return }
                    withAnimation(.easeOut(duration: 0.3)) { self.helpKeyHold = false }
                }
            } catch {
                guard !Task.isCancelled, let self, self.helpToken == token, var state = self.helpReply else { return }
                record(ok: false, error: UsageStats.Request.Failure.of(error))
                state.running = nil
                state.error = LLMFailure.of(error).title(provider: client.settings.providerName)
                self.helpReply = state
            }
        }
    }

    /// 历史（App › 历史「帮回」）：对方的话、每一轮的几条、上屏了哪条。同一次帮回更新同一条。
    func recordHelpHistory() {
        guard let state = helpReply, !state.history.isEmpty else { return }
        let provider = settings.forAnswers.providerName
        let versions = state.history.map { reply in
            let used = reply.id == state.insertedID
            return AIHistoryEntry.Version(text: reply.text, style: reply.name, provider: provider,
                                          use: used ? .inserted : nil, at: reply.at, source: "reply",
                                          usedAt: used ? state.insertedAt : nil, round: reply.round, direction: reply.direction)
        }
        AIHistory.record(AIHistoryEntry(id: state.historyID, kind: .reply, date: state.date, original: state.message,
                                        context: "", versions: versions))
    }

    // MARK: 按住 ^^ 往上滑 = 颜文字

    /// 按住 0.3 秒或拖过 16pt：正上方弹出「^^ 颜文字」格（盖住 ⌫），先选中帮回（键本身）。
    func showHelpCross(for key: KeySpec, origin: CGPoint) -> Bool {
        guard let look = helpKeyLook, !look.running else { return false }
        helpCross = HelpCrossPopup(key: key, origin: origin)
        keyFeedback(for: .space)
        return true
    }

    func moveHelpCross(to point: CGPoint) {
        guard var popup = helpCross else { return }
        let choice = popup.choice(at: point)
        guard choice != popup.selected else { return }
        popup.selected = choice
        helpCross = popup
        if choice != nil { keyFeedback(for: .space) }
    }

    /// 松手：在颜文字格里打开颜文字；没滑开是帮回；滑出去取消。
    func commitHelpCross() {
        guard let popup = helpCross else { return }
        helpCross = nil
        switch popup.selected {
        case .kaomoji?: openPanel(.kaomoji)
        case .help?: helpKeyTapped()
        case nil: break
        }
    }
}

/// 按住帮回键弹出的十字（HB9 第 3 格）：只有上格「^^ 颜文字」，和普通键一样大，盖住正上方的 ⌫。
struct HelpCrossPopup: Equatable {
    enum Choice: Equatable { case help, kaomoji }

    let key: KeySpec
    var origin: CGPoint
    var selected: Choice? = .help

    var upFrame: CGRect {
        let pitch = key.frame.height
        return CGRect(x: key.cap.minX, y: key.cap.minY - pitch, width: key.cap.width, height: key.cap.height)
    }

    func choice(at point: CGPoint) -> Choice? {
        if upFrame.insetBy(dx: -8, dy: -8).contains(point) { return .kaomoji }
        guard key.cap.insetBy(dx: -20, dy: -20).contains(point) || upFrame.insetBy(dx: -20, dy: -20).contains(point)
        else { return nil }
        let dx = point.x - origin.x, dy = point.y - origin.y
        if hypot(dx, dy) <= 14 { return .help }
        if dy < 0, abs(dy) > abs(dx) { return .kaomoji }
        return key.cap.contains(point) ? .help : nil
    }
}

#if DEBUG
// MARK: - 模拟器截图用

extension KeyboardModel {
    /// -keyboardDebug help:key（^^ 变帮回）、help:hold（按住弹出颜文字格，选中帮回）、help:up（滑进颜文字格）、
    /// help:running（键和卡都在写）、help:card（写好 3 条）、help:second（翻到第 2 条）、help:inserted（上屏后）、
    /// help:direction（方向重写后、框里还写着方向）、help:menu（⌄ 列表）、help:stopped（停了）、help:panel（剪贴板面板）。
    func applyHelpDebug(_ options: [String]) {
        guard !options.isEmpty else { return }
        debugUnblocked = true
        debugHelpClipboard = true
        if settings.keyboardLayout != .nineKey { setLayout(.nineKey) }
        clipboardHasNew = true
        helpDismissed = false
        let message = "一起吃个饭，叫上小王，就在公司楼下那家火锅"
        if options.contains("panel") {
            let now = Date()
            clipItems = [
                ClipItem(text: message, date: now),
                ClipItem(text: "会议改到周五下午三点，地点在 3 楼大会议室", date: now.addingTimeInterval(-7200)),
                ClipItem(text: "SF2048-KX9Q", date: now.addingTimeInterval(-9000)),
            ]
            openPanel(.quickWords)
            return
        }
        let width = UIScreen.main.bounds.width - KeyboardMetrics.sidePadding * 2
        let layout = KeyLayout.build(layoutState, size: CGSize(width: width, height: KeyboardMetrics.keysHeight))
        let key = layout.keys.first { $0.kind == .emoticon }
        if options.contains("hold") || options.contains("up"), let key {
            let origin = CGPoint(x: key.cap.midX, y: key.cap.midY)
            if showHelpCross(for: key, origin: origin), options.contains("up") { helpCross?.selected = .kaomoji }
            return
        }
        guard options.contains(where: { $0 != "key" }) else { return }
        var state = HelpReplyState(historyID: UUID().uuidString, date: Date(), message: message)
        let styles = settings.checkedReplyStyles
        let texts = ["好啊，周六晚上可以！几点在火锅店见？", "谢谢你想着我～周六晚上有空的，到时候楼下火锅店见，几点合适你定就好。", "可以，几点？"]
        let declines = ["谢谢你叫我～不过周六晚上刚好有事走不开，这次先不去了，下次我请你们。",
                        "太感谢啦！可惜周六晚上已经约了别的事，你们吃好，下次一定。", "这次去不了，下次约！"]
        let direction = options.contains("direction") ? "委婉拒绝" : nil
        state.round = 1
        state.replies = zip(styles, direction == nil ? texts : declines).map {
            HelpReplyState.Reply(styleID: $0.id, name: $0.displayName, text: $1, round: 1, direction: direction, at: Date())
        }
        state.history = state.replies
        if options.contains("running") {
            state.replies = []
            state.running = .all(direction: nil)
            state.runningCount = styles.count
        }
        if options.contains("stopped") {
            state.replies = []
            state.stopped = true
        }
        if options.contains("second") || options.contains("inserted") || options.contains("direction") { state.index = min(1, state.replies.count - 1) }
        if options.contains("inserted"), let current = state.current {
            state.insertedID = current.id
            state.insertedText = current.text
            state.insertedAt = Date()
        }
        helpReply = state
        helpKeyHold = options.contains("running")
        setInstruction(direction ?? "")
        aiExpanded = true
        hostFocused = !options.contains("direction")
        target = options.contains("direction") ? .instruction : .host
        if options.contains("menu") { helpMenuOpen = true }
    }
}
#endif
