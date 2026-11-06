import SwiftUI
import UIKit

/// AI 帮回（T16）的一次：对方的话、卡头的几种风格（标签）、每种写好的那条、现在看哪种、哪条放进了输入框、在写哪种。
/// 一次只写一种（cvbk 11-06）：点帮回先写上次用的那种，点别的标签就中断、换成那种写；写好的都留着，点回去直接看。
/// 按方向重写后之前写的作废（留在历史里），每种按新方向重新写。所有写好的都进历史。
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

    /// 卡头的一个标签：打勾的几种，加上次用的（没勾时）、⌄ 里加的。
    struct Tag: Equatable, Identifiable {
        var id: UUID
        var name: String
        var style: StylePreset
    }

    /// 这个标签没写好的原因：停了、出错了。
    enum Note: Equatable {
        case stopped
        case error(String)
    }

    let historyID: String
    let date: Date
    var message: String
    var tags: [Tag] = []
    /// 按风格 id：这一轮（同一个方向）写好的那条。
    var results: [UUID: Reply] = [:]
    var notes: [UUID: Note] = [:]
    var history: [Reply] = []
    var index = 0
    /// 现在的回复方向（按方向重写后才有），第几轮（换一次方向加一）。
    var direction: String?
    var round = 1
    /// 放进输入框的那条、放进去的字（再点别的风格时把它换掉）、什么时候放的。
    var insertedID: UUID?
    var insertedText: String?
    var insertedAt: Date?
    /// 正在写的那种（风格 id）和已经出来的字。
    var running: UUID?
    var streaming = ""
    /// 写好的那一刻：键上白色对勾一笔画出，约 1.6 秒后 ^^ 淡回。
    var successAt: Date?

    var currentTag: Tag? { tags.indices.contains(index) ? tags[index] : nil }
    var current: Reply? { currentTag.flatMap { results[$0.id] } }
    var currentNote: Note? { currentTag.flatMap { notes[$0.id] } }
    var currentRunning: Bool { running != nil && running == currentTag?.id }
    var currentInserted: Bool { current != nil && current?.id == insertedID }
    func isDone(_ tag: Tag) -> Bool { results[tag.id] != nil }
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
        // 现在这种停了、出错了：用同一段话再写一次。
        if let state = helpReply, state.current == nil, state.currentNote != nil {
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

    /// 面板收起，回答卡展开成绿色「AI 帮回」卡，先写上次用的那种。不往输入框贴原文。
    private func beginHelpReply(message: String, fromKey: Bool) {
        endCelebration()
        if isRunning { stop() }
        cancelHelpTask()
        if target == .card { finishCardEdit() }
        finishComposition()
        if keysPanel != nil { closePanel() }
        if aiRow != nil { aiRow = nil }
        helpMenuOpen = false
        reload()
        var state = HelpReplyState(historyID: UUID().uuidString, date: Date(), message: message)
        let checked = settings.checkedReplyStyles
        state.tags = checked.map { HelpReplyState.Tag(id: $0.id, name: $0.displayName, style: $0) }
        let last = Self.lastHelpStyleID.flatMap { id in settings.replyStyles.first { $0.id == id } }
        if let last, !state.tags.contains(where: { $0.id == last.id }) {
            state.tags.append(HelpReplyState.Tag(id: last.id, name: last.displayName, style: last))
        }
        state.index = last.flatMap { last in state.tags.firstIndex { $0.id == last.id } } ?? 0
        helpReply = state
        helpKeyHold = fromKey
        // 下面的框是这次的回复方向：从空的开始。
        clearInstruction()
        setAIExpanded(true)
        // 打字还进对方输入框，点下面的框才写方向。
        if askSelected { askSelected = false }
        hostFocused = true
        if target != .host { target = .host }
        writeCurrentHelp()
    }

    /// 上次用的那种（上屏的、点过的）：下次帮回先写它。
    private static let lastStyleKey = "helpReply.lastStyleID"
    static var lastHelpStyleID: UUID? {
        get { SharedStorage.defaults.string(forKey: lastStyleKey).flatMap(UUID.init(uuidString:)) }
        set { SharedStorage.defaults.set(newValue?.uuidString, forKey: lastStyleKey) }
    }

    // MARK: 卡片上的操作

    /// 「↻ 按这个重写」/ 打着方向按回车：之前写的作废（留在历史里），这一种按这个方向重写，别的点到时再按新方向写。
    func helpRewriteTapped() {
        guard var state = helpReply else { return }
        let direction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !direction.isEmpty else {
            showKeysToast(L("先在下面写想怎么回", "Type how you'd like to reply first", "どう返したいかを先に書いてください"))
            return
        }
        guard passHelpGates(then: { [weak self] in self?.helpRewriteTapped() }) else { return }
        finishComposition()
        cancelHelpTask()
        state.running = nil
        state.streaming = ""
        state.direction = direction
        state.round += 1
        state.results = [:]
        state.notes = [:]
        helpReply = state
        writeCurrentHelp()
    }

    /// 停了、出错后再点「帮回」（键上或卡片上）：同一段话、同一个方向，把现在这种再写一次。
    func retryHelpReply() {
        guard let state = helpReply, state.running == nil else { return }
        guard passHelpGates(then: { [weak self] in self?.retryHelpReply() }) else { return }
        writeCurrentHelp()
    }

    /// ⌄ 里点了一种：卡上已经有这个标签就切过去；没有就加在最后再切过去。
    func helpStylePicked(_ style: StylePreset) {
        helpMenuOpen = false
        guard var state = helpReply else { return }
        if let index = state.tags.firstIndex(where: { $0.id == style.id }) {
            helpSelect(index)
            return
        }
        state.tags.append(HelpReplyState.Tag(id: style.id, name: style.displayName, style: style))
        helpReply = state
        helpSelect(state.tags.count - 1)
    }

    /// 点标签、左右滑：换一种。写好过的直接显示（上屏过的话输入框里那条跟着换）；
    /// 没写过的中断正在写的那种（它回到没写的样子），换成这种写。
    func helpSelect(_ index: Int) {
        guard var state = helpReply, state.tags.indices.contains(index) else { return }
        // 再点现在这个：失败了、停了就重写（HB19「点它或正文按钮重写」）。
        if index == state.index {
            if state.running == nil, state.current == nil, state.currentNote != nil { retryHelpReply() }
            return
        }
        state.index = index
        let tag = state.tags[index]
        Self.lastHelpStyleID = tag.id
        if state.running != nil, state.running != tag.id {
            cancelHelpTask()
            state.running = nil
            state.streaming = ""
        }
        helpReply = state
        keyFeedback(for: .space)
        if state.results[tag.id] != nil {
            replaceInsertedIfNeeded()
        } else if state.running == nil {
            guard passHelpGates(then: { [weak self] in self?.writeCurrentHelp() }) else { return }
            writeCurrentHelp()
        }
    }

    func helpTurn(_ offset: Int) {
        guard let state = helpReply, !state.tags.isEmpty else { return }
        let next = state.index + offset
        // 滑到头回弹：不循环。
        guard state.tags.indices.contains(next) else { return }
        helpSelect(next)
    }

    /// 点正文或左边「↵ 上屏」：放进对方输入框。上屏过别的那条时把它换掉（光标前还是它才换）。
    func helpInsert() {
        guard var state = helpReply, let reply = state.current, let proxy = editProxy else { return }
        if state.insertedID == reply.id { return }
        if let old = state.insertedText, (proxy.documentContextBeforeInput ?? "").hasSuffix(old) {
            for _ in 0..<old.count { proxy.deleteBackward() }
        }
        proxy.insertText(reply.text)
        state.insertedID = reply.id
        state.insertedText = reply.text
        state.insertedAt = Date()
        helpReply = state
        Self.lastHelpStyleID = reply.styleID
        keyFeedback(for: .space)
        // 打字和回车回到对方输入框，回车直接发送。
        focusHostAfterResult()
        recordHelpHistory()
        UIAccessibility.post(notification: .announcement, argument: L("已上屏", "Inserted", "入力しました"))
    }

    private func replaceInsertedIfNeeded() {
        guard let state = helpReply, state.insertedID != nil, state.current != nil, !state.currentInserted else { return }
        helpInsert()
    }

    /// 点停止：立即取消，不算次数；卡片「已停止 · 再点「帮回」重写」。
    func stopHelpReply() {
        guard var state = helpReply, let id = state.running else { return }
        cancelHelpTask()
        state.running = nil
        state.streaming = ""
        state.notes[id] = .stopped
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

    // MARK: 请求

    /// 用问答接口写现在这种（不联网），边写边显示。写完才算一次问答；停止、出错、被换走都不算。
    private func writeCurrentHelp() {
        guard var state = helpReply, let tag = state.currentTag else { return }
        let key = SettingsStore.answerKey(for: settings)
        guard BuiltinAPI.take(.answer, key: key) else {
            state.notes[tag.id] = .error(BuiltinAPI.limitMessage(.answer))
            helpReply = state
            return
        }
        let client = LLMClient(settings: settings.forAnswers, apiKey: key)
        cancelHelpTask()
        state.running = tag.id
        state.streaming = ""
        state.notes[tag.id] = nil
        state.successAt = nil
        helpReply = state
        let token = helpToken
        let direction = state.direction
        let round = state.round
        let messages = HelpReply.messages(message: state.message, style: tag.style, direction: direction ?? "")
        let started = Date()
        let separate = settings.usesAnswerEndpoint
        func record(ok: Bool, error: String? = nil) {
            UsageStats.recordPolish(ms: Int(Date().timeIntervalSince(started) * 1000), ok: ok, styleID: nil,
                                    mainAPI: !separate, styleName: L("帮回", "Help Reply", "返信アシスト"),
                                    model: client.settings.model, error: error)
        }
        helpTask = Task { [weak self] in
            var raw = ""
            var shownAt = Date.distantPast
            do {
                for try await piece in client.stream(messages) {
                    raw += piece
                    // 每改一次整个键盘重画：最多每 50 毫秒显示一次。
                    let now = Date()
                    guard let self, self.helpToken == token, now.timeIntervalSince(shownAt) >= 0.05 else { continue }
                    shownAt = now
                    self.helpReply?.streaming = HelpReply.single(ModelOutput.clean(raw))
                }
                try Task.checkCancellation()
                guard let self, self.helpToken == token, var state = self.helpReply else { return }
                let text = HelpReply.single(ModelOutput.clean(raw))
                state.running = nil
                state.streaming = ""
                if text.isEmpty {
                    record(ok: false, error: UsageStats.Request.Failure.empty)
                    state.notes[tag.id] = .error(L("模型没有返回内容。", "The model returned nothing.", "モデルから応答がありませんでした。"))
                    self.helpReply = state
                    return
                }
                record(ok: true)
                // 提示词页每种帮回风格的本周次数。
                DailyStats.add("reply.style.\(tag.id.uuidString)")
                DailyStats.flush()
                AIAccess.recordUse()
                self.refreshAIAccess()
                let now = Date()
                let reply = HelpReplyState.Reply(styleID: tag.id, name: tag.name, text: text, round: round,
                                                 direction: direction, at: now)
                state.results[tag.id] = reply
                state.history.append(reply)
                state.successAt = now
                self.helpReply = state
                self.recordHelpHistory()
                UIAccessibility.post(notification: .announcement, argument: L("写好了", "Reply ready", "作成しました"))
                // 白色对勾画完（600ms）后停一会儿，约 1.6 秒后 ^^ 淡回。
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    guard let self, self.helpReply?.successAt == now else { return }
                    withAnimation(.easeOut(duration: 0.3)) { self.helpKeyHold = false }
                }
            } catch {
                guard !Task.isCancelled, let self, self.helpToken == token, var state = self.helpReply else { return }
                record(ok: false, error: UsageStats.Request.Failure.of(error))
                state.running = nil
                state.streaming = ""
                state.notes[tag.id] = .error(LLMFailure.of(error).title(provider: client.settings.providerName))
                self.helpReply = state
            }
        }
    }

    /// 历史（App › 历史「帮回」）：对方的话、每一轮写好的几条、上屏了哪条。同一次帮回更新同一条。
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
    /// help:running（键和卡都在写）、help:card（写好第 1 种）、help:second（写好 2 种、看第 2 种）、help:switching（切到第 3 种正在写）、help:all（3 种都写好）、help:inserted（上屏后）、
    /// help:direction（方向重写后、框里还写着方向）、help:menu（⌄ 列表）、help:stopped（停了）、help:failed（第 3 种没写出来）、help:panel（剪贴板面板）。
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
        state.tags = styles.map { HelpReplyState.Tag(id: $0.id, name: $0.displayName, style: $0) }
        let texts = ["好啊，周六晚上可以！几点在火锅店见？", "谢谢你想着我～周六晚上有空的，到时候楼下火锅店见，几点合适你定就好。", "可以，几点？"]
        let declines = ["谢谢你叫我～不过周六晚上刚好有事走不开，这次先不去了，下次我请你们。",
                        "太感谢啦！可惜周六晚上已经约了别的事，你们吃好，下次一定。", "这次去不了，下次约！"]
        let direction = options.contains("direction") ? "委婉拒绝" : nil
        state.direction = direction
        state.round = direction == nil ? 1 : 2
        // 写好了几种：card 写好第 1 种；second、switching 写好 2 种；all、inserted 三种都写好；running、stopped 一种都没有。
        let done: Int
        if options.contains("all") || options.contains("inserted") { done = styles.count }
        else if options.contains("second") || options.contains("switching") { done = 2 }
        else if options.contains("running") || options.contains("stopped") { done = 0 }
        else { done = 1 }
        for (index, style) in styles.prefix(done).enumerated() {
            let reply = HelpReplyState.Reply(styleID: style.id, name: style.displayName,
                                             text: (direction == nil ? texts : declines)[index % 3], round: state.round,
                                             direction: direction, at: Date())
            state.results[style.id] = reply
            state.history.append(reply)
        }
        if options.contains("second") || options.contains("inserted") || options.contains("direction") {
            state.index = min(1, state.tags.count - 1)
        }
        if options.contains("running"), let first = state.tags.first { state.running = first.id }
        // direction：刚按方向点了「↻ 重写这条」，现在这种正在按新方向写。
        if options.contains("direction"), let tag = state.currentTag, state.current == nil { state.running = tag.id }
        // switching：第 1、2 种写好了，点了第 3 种正在写，已经出了半句。
        if options.contains("switching"), state.tags.count > 2 {
            state.index = 2
            state.running = state.tags[2].id
            state.streaming = "可以，几"
        }
        if options.contains("stopped"), let first = state.tags.first { state.notes[first.id] = .stopped }
        // failed：第 1 种写好了，第 3 种没写出来（HB18 ⑥）。
        if options.contains("failed"), state.tags.count > 2 {
            state.index = 2
            state.notes[state.tags[2].id] = .error(L("网络断了", "network lost", "ネットワーク切断"))
        }
        if options.contains("inserted"), let current = state.current {
            state.insertedID = current.id
            state.insertedText = current.text
            state.insertedAt = Date()
        }
        helpReply = state
        helpKeyHold = state.running != nil
        setInstruction(direction ?? "")
        aiExpanded = true
        hostFocused = !options.contains("direction")
        target = options.contains("direction") ? .instruction : .host
        if options.contains("menu") { helpMenuOpen = true }
    }
}
#endif
