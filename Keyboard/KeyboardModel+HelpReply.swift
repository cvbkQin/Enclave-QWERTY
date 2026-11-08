import SwiftUI
import UIKit

/// AI 帮回（T16）的一句：对方的话、卡头的几种风格（标签）、每种风格写过的几版、现在看哪种哪版、在写哪种。
/// 一次只写一种（HB17）：点帮回先写上次用的那种，点别的标签就中断、换成那种写；写好的都留着，点回去直接看。
/// 每种风格可以有几版（HB21）：按要求重写、再写一版、用润色改，都接在这种风格后面，▲▼ 翻。
/// 帮回和润色、问答共用回答卡（方案 C，11-06）：切到润色、问答时这一句收起来（helpThreads），点帮回键再拿回来。
struct HelpReplyState: Equatable {
    struct Reply: Equatable, Identifiable {
        var id = UUID()
        var styleID: UUID
        var name: String
        var text: String
        /// 这一版按什么要求写的（识意框里的字）；翻到这一版时识意框跟着换成它。
        var direction: String?
        /// 用润色改出来的这一版：润色风格的名字（正文前标「✨ 正式」）。
        var polish: String?
        var at: Date
        /// 从 AI 历史还原的（11-08）：原来记的接口、用过没有、什么时候用的，再记回历史时照抄。
        var provider: String?
        var use: AIHistoryEntry.Use?
        var usedAt: Date?
    }

    /// 卡头的一个标签：打勾的几种，加上次用的（没勾时）、⌄ 里加的。
    struct Tag: Equatable, Identifiable {
        var id: UUID
        var name: String
        var style: StylePreset
    }

    /// 这个标签最近一次没写好的原因：停了、出错了。
    enum Note: Equatable {
        case stopped
        case error(String)
    }

    let historyID: String
    var date: Date
    var message: String
    var tags: [Tag] = []
    /// 按风格 id：写过的几版（旧的在前）和现在看第几版。
    var results: [UUID: [Reply]] = [:]
    var pages: [UUID: Int] = [:]
    var notes: [UUID: Note] = [:]
    /// 这一句所有写好的版本（进 App 的 AI 历史）。
    var history: [Reply] = []
    var index = 0
    /// 替换 / 插入进输入框的那版和放进去的字（帮回卡上点润色时找输入框里的这段）。
    var insertedID: UUID?
    var insertedText: String?
    var insertedAt: Date?
    /// 正在写的那种（风格 id）、已经出来的字、是不是在用润色改。
    var running: UUID?
    var streaming = ""
    var runningPolish = false
    /// 写好的那一刻：键上白色对勾一笔画出。
    var successAt: Date?
    /// 开新的一句时先倒计时 3 秒（HB29，放在识意框里）：到点按上次的风格写。
    var countdownEnds: Date?
    /// 收起来时识意框里的字和执行过的那段（再拿回来时还原）。
    var askDraft = ""
    var askExecuted: String?

    /// 空卡（11-08，RG5 ③）：从没用过帮回，没复制也打开；还没有要回的那句话。
    var isEmpty: Bool { message.isEmpty }
    var currentTag: Tag? { tags.indices.contains(index) ? tags[index] : nil }
    func versions(_ id: UUID) -> [Reply] { results[id] ?? [] }
    func page(_ id: UUID) -> Int {
        let count = versions(id).count
        return min(max(pages[id] ?? count - 1, 0), max(count - 1, 0))
    }
    var currentVersions: [Reply] { currentTag.map { versions($0.id) } ?? [] }
    var currentPage: Int { currentTag.map { page($0.id) } ?? 0 }
    var current: Reply? {
        guard let tag = currentTag else { return nil }
        let list = versions(tag.id)
        return list.isEmpty ? nil : list[page(tag.id)]
    }
    var currentNote: Note? { currentTag.flatMap { notes[$0.id] } }
    var currentRunning: Bool { running != nil && running == currentTag?.id }
    func isDone(_ tag: Tag) -> Bool { !versions(tag.id).isEmpty }
    /// 回哪句话列表右边：「客气 3 版」——写得最多的那种（一样多取现在这种）。
    var summary: (name: String, count: Int)? {
        let written = tags.filter { isDone($0) }
        guard !written.isEmpty else { return nil }
        let pick = (currentTag.flatMap { tag in isDone(tag) ? tag : nil })
            ?? written.max { versions($0.id).count < versions($1.id).count }!
        return (pick.name, versions(pick.id).count)
    }
}

/// ^^ 键（帮回）的样子（KeyCapContext 里比较，变了才重画键帽）。
struct HelpKeyLook: Equatable {
    var running: Bool
    var moving: Bool
    var successAt: Date?
    /// 有新复制的内容：「回」右上角红点（HB23）。
    var newCopy = false
    /// 识意框里有还没执行的要求：绿描边 + 光晕，点它按这条要求写（RG4）。
    var armed = false
    /// 帮回卡开着：键外一圈浅绿（K2 #B9D6C7）。
    var open = false
    /// 倒计时中（11-08，RG6 ①）：键上是「⏸ 暂停」，键里一圈跟着这 3 秒走。
    var countdownEnds: Date?
}

/// 回哪句话列表的一行（RG2 ③）。
struct HelpSentenceRow: Identifiable, Equatable {
    /// history：App AI 历史里回过的（11-08）；hint：什么都没有时那一行提示。
    enum Source: Equatable { case current, thread(String), history(String), clip(String), hint }
    var id: String
    var text: String
    var date: Date
    var source: Source
    /// 「客气 3 版」；nil 是还没回。
    var summary: String?
}

extension KeyboardModel {
    private static let helpDismissedKey = "helpReply.dismissedChangeCount"
    /// 帮回、润色 / 问答各存一份识意框的字：切过去再切回来，问题还在。
    private static var otherAskDraft = ""

    /// 润色接口（主接口）能用才有帮回（11-08 改，不再看问答键）；不能用时 ^^ 键不变、面板不显示「帮回」。
    var helpReplyAvailable: Bool {
        (hasFullAccess || debugUnblocked) && (settings.polishUsable || debugUnblocked)
    }

    /// 识意框里有还没执行的要求（普通颜色的字）：帮回键亮起来。
    var helpAskPending: Bool {
        helpReply != nil && canAsk && instruction != helpExecutedAsk
    }

    /// 识意框里的字已经用在正文这一版上：绿字。
    var helpAskExecuted: Bool {
        helpReply != nil && !instruction.isEmpty && instruction == helpExecutedAsk
    }

    /// ^^ 键常驻「帮回 / 颜文字」（HB23）：九宫格、没在打拼音时都是帮回；新复制时带红点。
    var helpKeyLook: HelpKeyLook? {
        guard !isComposing, helpReplyAvailable else { return nil }
        return HelpKeyLook(running: helpReply?.running != nil, moving: settings.polishAnimation,
                           successAt: helpKeyHold ? helpReply?.successAt : nil,
                           newCopy: clipboardHasNew && !helpDismissed, armed: helpAskPending,
                           open: helpReply != nil && aiExpanded, countdownEnds: helpReply?.countdownEnds)
    }

    /// 键盘出现时：这次的新复制被打字收掉过就不再带红点（同一个 changeCount）。
    func refreshHelpOffer(changeCount: Int) {
        let dismissed = SharedStorage.defaults.object(forKey: Self.helpDismissedKey) as? Int
        let value = dismissed == changeCount
        if helpDismissed != value { helpDismissed = value }
    }

    /// 开始打字：这份复制的内容不再提示（红点去掉，下次复制新内容再出）。
    func dismissHelpOffer() {
        guard clipboardHasNew, !helpDismissed else { return }
        helpDismissed = true
        SharedStorage.defaults.set(UIPasteboard.general.changeCount, forKey: Self.helpDismissedKey)
    }

    /// 键盘自己写了剪贴板（复制结果、分词复制、复制一条记录）：不算新复制的内容。
    func noteOwnCopy() {
        ClipboardHistory.lastChangeCount = UIPasteboard.general.changeCount
        if clipboardHasNew { clipboardHasNew = false }
    }

    private var helpHasNewCopy: Bool { clipboardHasNew && !helpDismissed }

    // MARK: 入口

    /// 点 ^^ 帮回键（HB23、RG4，11-08 补）：
    /// 1. 正在写：停止。2. 倒计时中：暂停。3. 识意框里有没执行的要求：按它写当前这句（空卡上有新复制就开那句直接写）。
    /// 4. 卡没开：有新复制开新的一句（先倒计时）；没有就原样打开最近一次帮回（这次收起来的，没有就从 AI 历史取），
    ///    历史里也没有就开空卡。不读剪贴板、不发请求、不算次数。
    /// 5. 卡开着：有新复制开新的一句；没有就按当前风格再写一版。空卡上没有新复制只提示。
    func helpKeyTapped() {
        if helpReply?.running != nil {
            stopHelpReply()
            return
        }
        if helpReply?.countdownEnds != nil {
            pauseHelpCountdown()
            return
        }
        if let state = helpReply {
            if state.isEmpty {
                if helpHasNewCopy {
                    startHelpFromPasteboard(fromKey: true)
                } else {
                    showKeysToast(L("先复制对方的一句话", "Copy their message first", "まず相手のメッセージをコピーしてください"))
                }
            } else if helpAskPending {
                helpExecuteAsk()
            } else if helpHasNewCopy {
                startHelpFromPasteboard(fromKey: true)
            } else {
                helpWriteAgain()
            }
            return
        }
        if helpHasNewCopy {
            startHelpFromPasteboard(fromKey: true)
        } else {
            openLastHelp()
        }
    }

    /// 没有新复制时点帮回键：原样打开最近一次帮回。先找这次键盘里收起来的，再找 App 的 AI 历史，都没有就开空卡。
    private func openLastHelp() {
        if let first = helpThreads.first {
            showHelpThread(first.historyID)
            return
        }
        refreshHelpRecent()
        if let entry = helpRecentReplies.first, let state = helpState(from: entry) {
            showHelp(state)
            return
        }
        showHelp(emptyHelpState())
    }

    /// 空卡：标题行放打勾的风格，上次用的那种是待写（浅绿描边）；正文灰字提示复制一句。
    private func emptyHelpState() -> HelpReplyState {
        reload()
        var state = HelpReplyState(historyID: UUID().uuidString, date: Date(), message: "")
        state.tags = helpTags()
        state.index = Self.lastHelpStyleID.flatMap { last in state.tags.firstIndex { $0.id == last } } ?? 0
        return state
    }

    /// 打勾的几种，加上次用的那种（没勾时放最后）。
    private func helpTags() -> [HelpReplyState.Tag] {
        var tags = settings.checkedReplyStyles.map { HelpReplyState.Tag(id: $0.id, name: $0.displayName, style: $0) }
        let last = Self.lastHelpStyleID.flatMap { id in settings.replyStyles.first { $0.id == id } }
        if let last, !tags.contains(where: { $0.id == last.id }) {
            tags.append(HelpReplyState.Tag(id: last.id, name: last.displayName, style: last))
        }
        return tags
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

    /// 和润色一样先过提示卡（完全访问、隐私、没配置、次数）。11-08 起走润色接口，不再过问答的发送同意；
    /// 第一次发送前的确认卡是帮回自己的那张（RG9）。
    func passHelpGates(then action: @escaping () -> Void) -> Bool {
        passGate(purpose: .help, then: action)
    }

    /// 开新的一句：回答卡换成帮回（绿），先倒计时 3 秒，到点按上次用的风格写。不往输入框贴原文。
    /// 回过的同一句直接切回去。空卡上先写好了要求：不倒计时，直接按这条要求写（11-08）。
    private func beginHelpReply(message: String, fromKey: Bool) {
        if let state = helpReply, state.message == message {
            helpKeyHold = fromKey
            if !aiExpanded { setAIExpanded(true) }
            return
        }
        if let old = helpThreads.first(where: { $0.message == message }) {
            showHelpThread(old.historyID)
            return
        }
        let carried = helpReply?.isEmpty == true && helpAskPending
            ? instruction.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        reload()
        var state = HelpReplyState(historyID: UUID().uuidString, date: Date(), message: message)
        if let empty = helpReply, empty.isEmpty {
            // 空卡上点过的标签就是要先写的那种。
            state.tags = empty.tags
            state.index = empty.index
        } else {
            state.tags = helpTags()
            state.index = Self.lastHelpStyleID.flatMap { last in state.tags.firstIndex { $0.id == last } } ?? 0
        }
        showHelp(state)
        helpKeyHold = fromKey
        if carried.isEmpty {
            startHelpCountdown()
        } else {
            writeCurrentHelp(direction: carried)
        }
    }

    /// 回哪句话列表里点了一句：回过的切过去，剪贴板里没回过的开新的一句（先倒计时）。
    func helpSentencePicked(_ row: HelpSentenceRow) {
        helpListOpen = false
        switch row.source {
        case .current, .hint: break
        case .thread(let id): showHelpThread(id)
        case .history(let id):
            if let entry = helpRecentReplies.first(where: { $0.id == id }), let state = helpState(from: entry) {
                showHelp(state)
            }
        case .clip(let text):
            guard passHelpGates(then: { [weak self] in self?.helpSentencePicked(row) }) else { return }
            beginHelpReply(message: text, fromKey: false)
        }
    }

    /// 把收起来的一句拿回卡上（原样：同样的标签和版本，不重新请求）。
    private func showHelpThread(_ id: String) {
        guard let index = helpThreads.firstIndex(where: { $0.historyID == id }) else { return }
        let state = helpThreads.remove(at: index)
        showHelp(state)
    }

    /// 卡片换成这一句：现在卡上的帮回收进列表；从润色 / 问答切过来时记下那边识意框的字，换成这一句的。
    /// 空卡上先写了要求再挑一句回过的：要求留在框里（普通颜色），帮回键亮起来，点了再按它写。
    private func showHelp(_ state: HelpReplyState) {
        let carried = helpReply?.isEmpty == true && helpAskPending ? instruction : nil
        endCelebration()
        if isRunning { stop() }
        cancelHelpTask()
        cancelHelpCountdown()
        if target == .card { finishCardEdit() }
        finishComposition()
        if keysPanel != nil { closePanel() }
        if aiRow != nil { aiRow = nil }
        helpMenuOpen = false
        helpListOpen = false
        if helpReply != nil {
            stashHelp()
        } else {
            Self.otherAskDraft = instruction
        }
        helpReply = state
        helpExecutedAsk = state.askExecuted
        setInstruction(carried ?? state.askDraft)
        setAIExpanded(true)
        // 打字还进对方输入框，点下面的框才写要求。
        if askSelected { askSelected = false }
        hostFocused = true
        if target != .host { target = .host }
    }

    /// 卡上这一句收进列表（停掉在写的，记下识意框的字）。
    private func stashHelp() {
        guard var state = helpReply else { return }
        cancelHelpTask()
        cancelHelpCountdown()
        // 空卡不进列表。
        if state.isEmpty {
            helpReply = nil
            return
        }
        state.running = nil
        state.streaming = ""
        state.runningPolish = false
        state.countdownEnds = nil
        state.askDraft = instruction
        state.askExecuted = helpExecutedAsk
        helpThreads.removeAll { $0.historyID == state.historyID }
        helpThreads.insert(state, at: 0)
        if helpThreads.count > 8 { helpThreads.removeLast(helpThreads.count - 8) }
        helpReply = nil
    }

    /// 开始润色 / 问答、收起抽屉：帮回收起来（不丢，点帮回键原样拿回），识意框换回润色 / 问答那份。
    func parkHelpReply() {
        guard helpReply != nil else { return }
        stashHelp()
        helpMenuOpen = false
        helpListOpen = false
        helpKeyHold = false
        helpExecutedAsk = nil
        setInstruction(Self.otherAskDraft)
    }

    /// 上次用的那种（上屏的、点过的）：下次帮回先写它。
    private static let lastStyleKey = "helpReply.lastStyleID"
    static var lastHelpStyleID: UUID? {
        get { SharedStorage.defaults.string(forKey: lastStyleKey).flatMap(UUID.init(uuidString:)) }
        set { SharedStorage.defaults.set(newValue?.uuidString, forKey: lastStyleKey) }
    }

    /// 回哪句话列表（11-08）：卡上这句放第一行，再是这次收起来的几句、AI 历史里最近回过的（最多 10 句）、
    /// 剪贴板记录里还没回的（单号、链接不算）。同一句只出一次，除了第一行都按时间新的在前，放不下列表里上下滚。
    /// 什么都没有（空卡、剪贴板记录也空）：只有一行提示。
    var helpSentenceRows: [HelpSentenceRow] {
        var rows: [HelpSentenceRow] = []
        func label(_ state: HelpReplyState) -> String? {
            state.summary.map { Self.helpSummaryLabel(name: $0.name, count: $0.count) }
        }
        if let state = helpReply, !state.isEmpty {
            rows.append(HelpSentenceRow(id: state.historyID, text: state.message, date: state.date, source: .current,
                                        summary: label(state)))
        }
        for state in helpThreads where !state.isEmpty {
            rows.append(HelpSentenceRow(id: state.historyID, text: state.message, date: state.date,
                                        source: .thread(state.historyID), summary: label(state)))
        }
        for entry in helpRecentReplies where !rows.contains(where: { $0.id == entry.id || $0.text == entry.original }) {
            rows.append(HelpSentenceRow(id: entry.id, text: entry.original, date: entry.endDate ?? entry.date,
                                        source: .history(entry.id), summary: Self.helpSummary(entry)))
        }
        var known = Set(rows.map(\.text))
        var clips = 0
        for item in clipItems where clips < 10 && !known.contains(item.text) && HelpReply.suits(item.text) {
            known.insert(item.text)
            rows.append(HelpSentenceRow(id: "clip-\(item.date.timeIntervalSince1970)", text: item.text, date: item.date,
                                        source: .clip(item.text), summary: nil))
            clips += 1
        }
        let current = rows.first { $0.source == .current }
        var rest = rows.filter { $0.source != .current }.sorted { $0.date > $1.date }
        if let current { rest.insert(current, at: 0) }
        if rest.isEmpty {
            rest.append(HelpSentenceRow(id: "hint", text: L("复制对方的一句话，再点帮回", "Copy their message, then tap Reply",
                                                            "相手のメッセージをコピーして「返信」をタップ"),
                                        date: Date(), source: .hint, summary: nil))
        }
        return rest
    }

    /// 「客气 3 版」。
    static func helpSummaryLabel(name: String, count: Int) -> String {
        L("\(name) \(count) 版", "\(name) ×\(count)", "\(name) \(count) 件")
    }

    /// 历史里一句的「客气 3 版」：列表上显示的那版是哪种风格，这种写了几版。
    static func helpSummary(_ entry: AIHistoryEntry) -> String? {
        guard entry.versions.indices.contains(entry.shownIndex) else { return nil }
        let name = helpStyleName(entry.versions[entry.shownIndex]).name
        let count = entry.versions.filter { helpStyleName($0).name == name }.count
        return helpSummaryLabel(name: name, count: count)
    }

    /// 点开回哪句话列表时读一次 AI 历史（关着记录就不读）。
    /// 卡刚弹出 0.6 秒内（键盘还在长高、排版没到位）点到句子行、「历史」键：其实是在帮回键上又点了一下。
    /// 这时在倒计时就当暂停，别的情况不理（不打开列表，也不替他发请求）。
    func toggleHelpList() {
        if Date().timeIntervalSince(helpOpenedAt) < 0.6 {
            if helpReply?.countdownEnds != nil { pauseHelpCountdown() }
            return
        }
        if !helpListOpen { refreshHelpRecent() }
        helpListOpen.toggle()
    }

    /// App AI 历史里最近回过的 10 句（新的在前）。
    func refreshHelpRecent() {
        guard AIHistory.isEnabled else {
            helpRecentReplies = []
            return
        }
        helpRecentReplies = Array(AIHistory.load()
            .filter { $0.kind == .reply && !$0.original.isEmpty && !$0.versions.isEmpty }
            .sorted { ($0.endDate ?? $0.date) > ($1.endDate ?? $1.date) }
            .prefix(10))
    }

    // MARK: 从 AI 历史还原（11-08）

    /// 一版的风格名和润色名：新记录有 styleID / polish；旧记录风格名存成「客气 · ✨正式」，拆开。
    static func helpStyleName(_ version: AIHistoryEntry.Version) -> (name: String, polish: String?) {
        let style = version.style ?? ""
        if let range = style.range(of: " · ✨") {
            return (String(style[..<range.lowerBound]), version.polish ?? String(style[range.upperBound...]))
        }
        return (style, version.polish)
    }

    /// 用 AI 历史里的一条拼回一句帮回：标签 = 打勾的风格 + 这条里出现过的风格（对不上的当临时标签），
    /// 显示用过的那版（没用过就最后一版），识意框换成那一版的要求（绿字）。之后再写新版记回同一条。
    func helpState(from entry: AIHistoryEntry) -> HelpReplyState? {
        guard entry.kind == .reply, !entry.original.isEmpty, !entry.versions.isEmpty else { return nil }
        reload()
        var state = HelpReplyState(historyID: entry.id, date: entry.date, message: entry.original)
        state.tags = helpTags()
        var shown: HelpReplyState.Reply?
        for (offset, version) in entry.versions.enumerated() {
            let (name, polish) = Self.helpStyleName(version)
            let style = version.styleID.flatMap(UUID.init(uuidString:)).flatMap { id in settings.replyStyles.first { $0.id == id } }
                ?? settings.replyStyles.first { $0.displayName == name || $0.name == name }
            let tag: HelpReplyState.Tag
            if let style {
                if let existing = state.tags.first(where: { $0.id == style.id }) {
                    tag = existing
                } else {
                    tag = HelpReplyState.Tag(id: style.id, name: style.displayName, style: style)
                    state.tags.append(tag)
                }
            } else if let existing = state.tags.first(where: { $0.name == name }) {
                tag = existing
            } else {
                // 删掉或改了名的风格：临时标签，提示词空着（照对方的话正常回）。
                let temp = StylePreset(name: name, prompt: "")
                tag = HelpReplyState.Tag(id: temp.id, name: temp.displayName, style: temp)
                state.tags.append(tag)
            }
            let reply = HelpReplyState.Reply(styleID: tag.id, name: tag.name, text: version.text, direction: version.direction,
                                             polish: polish, at: version.at ?? entry.date, provider: version.provider,
                                             use: version.use, usedAt: version.usedAt)
            state.results[tag.id, default: []].append(reply)
            state.history.append(reply)
            if offset == entry.shownIndex { shown = reply }
        }
        guard let shown, let index = state.tags.firstIndex(where: { $0.id == shown.styleID }) else { return nil }
        state.index = index
        state.pages[shown.styleID] = state.versions(shown.styleID).firstIndex { $0.id == shown.id }
        if shown.use != nil {
            state.insertedID = shown.id
            state.insertedText = shown.text
            state.insertedAt = shown.usedAt
        }
        let direction = shown.direction ?? ""
        state.askDraft = direction
        state.askExecuted = direction.isEmpty ? nil : direction
        return state
    }

    // MARK: 倒计时（HB29，放在识意框里）

    private func startHelpCountdown() {
        helpCountdownToken &+= 1
        let token = helpCountdownToken
        helpReply?.countdownEnds = Date().addingTimeInterval(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.helpCountdownToken == token, self.helpReply?.countdownEnds != nil else { return }
            self.helpReply?.countdownEnds = nil
            self.writeCurrentHelp(direction: nil)
        }
    }

    /// 倒计时中点了识意框、点了标签：停下来。
    func cancelHelpCountdown() {
        helpCountdownToken &+= 1
        if helpReply?.countdownEnds != nil { helpReply?.countdownEnds = nil }
    }

    /// 倒计时中点帮回键（RG6 ②）：停下来等，和点识意框一样，但打字还进对方输入框。
    func pauseHelpCountdown() {
        guard helpReply?.countdownEnds != nil else { return }
        cancelHelpCountdown()
        helpKeyHold = false
        UIAccessibility.post(notification: .announcement, argument: L("已暂停", "Paused", "一時停止しました"))
    }

    // MARK: 卡片上的操作

    /// 识意框里的字（还没执行的）按回车或点帮回键：按这条要求写当前风格的新一版。
    func helpExecuteAsk() {
        guard let state = helpReply else { return }
        if state.isEmpty {
            // 空卡：有新复制就开那句并按要求写，没有就提示。
            helpKeyTapped()
            return
        }
        let direction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard passHelpGates(then: { [weak self] in self?.helpExecuteAsk() }) else { return }
        finishComposition()
        cancelHelpCountdown()
        writeCurrentHelp(direction: direction.isEmpty ? nil : direction)
    }

    /// 没有待执行的字时点帮回键：按当前风格再写一版（框里有执行过的要求就照着它）。
    func helpWriteAgain() {
        guard let state = helpReply, !state.isEmpty else { return }
        guard passHelpGates(then: { [weak self] in self?.helpWriteAgain() }) else { return }
        let direction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        writeCurrentHelp(direction: direction.isEmpty ? nil : direction)
    }

    /// 停了、出错后「↻ 再写这条」：同一个要求再写一次。
    func retryHelpReply() {
        guard helpReply?.running == nil else { return }
        helpWriteAgain()
    }

    /// ⌄ 里点了一种：卡上已经有这个标签就切过去；没有就加在最后再切过去（只在这一句里有）。
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

    /// 点标签：换一种。写好过的直接显示（识意框换成那一版的要求）；没写过的中断正在写的那种，换成这种写。
    /// 再点现在这个：失败了、停了就重写；倒计时中就马上开始写。
    func helpSelect(_ index: Int) {
        guard var state = helpReply, state.tags.indices.contains(index) else { return }
        if state.isEmpty {
            // 空卡：只选定先写哪种，不发请求。
            state.index = index
            Self.lastHelpStyleID = state.tags[index].id
            helpReply = state
            keyFeedback(for: .space)
            return
        }
        let counting = state.countdownEnds != nil
        cancelHelpCountdown()
        state.countdownEnds = nil
        if index == state.index {
            if state.running == nil, counting || state.current == nil {
                guard passHelpGates(then: { [weak self] in self?.helpWriteAgain() }) else { return }
                helpWriteAgain()
            }
            return
        }
        state.index = index
        let tag = state.tags[index]
        Self.lastHelpStyleID = tag.id
        if state.running != nil, state.running != tag.id {
            cancelHelpTask()
            state.running = nil
            state.streaming = ""
            state.runningPolish = false
        }
        helpReply = state
        keyFeedback(for: .space)
        if state.isDone(tag) {
            syncHelpAsk()
        } else if state.running == nil {
            guard passHelpGates(then: { [weak self] in self?.helpWriteAgain() }) else { return }
            helpWriteAgain()
        }
    }

    /// 左右滑正文：换一种风格（到头不循环）。
    func helpTurn(_ offset: Int) {
        guard let state = helpReply, !state.tags.isEmpty else { return }
        let next = state.index + offset
        guard state.tags.indices.contains(next) else { return }
        helpSelect(next)
    }

    /// ▲▼：翻这一句、这种风格的版本；识意框跟着换成那一版的要求。
    func helpTurnVersion(_ offset: Int) {
        guard var state = helpReply, let tag = state.currentTag, state.running == nil else { return }
        let count = state.versions(tag.id).count
        let next = state.page(tag.id) + offset
        guard next >= 0, next < count else { return }
        state.pages[tag.id] = next
        state.notes[tag.id] = nil
        helpReply = state
        syncHelpAsk()
    }

    /// 识意框换成正文这一版的要求（绿字）；框里有还没执行的字时不换。
    private func syncHelpAsk() {
        guard let state = helpReply, !helpAskPending else { return }
        let direction = state.current?.direction ?? ""
        if instruction != direction { setInstruction(direction) }
        helpExecutedAsk = direction.isEmpty ? nil : direction
    }

    /// 替换 / 插入了这一版：记下放进去的字（点润色时找输入框里的这段），进历史。
    func noteHelpUsed(_ text: String) {
        guard var state = helpReply, let reply = state.current else { return }
        state.insertedID = reply.id
        state.insertedText = text
        state.insertedAt = Date()
        helpReply = state
        Self.lastHelpStyleID = reply.styleID
        recordHelpHistory()
    }

    /// 点停止：立即取消，不算次数；没写完的不留，标签回到灰色。
    func stopHelpReply() {
        guard var state = helpReply, let id = state.running else { return }
        cancelHelpTask()
        state.running = nil
        state.streaming = ""
        state.runningPolish = false
        state.notes[id] = .stopped
        helpReply = state
        UIAccessibility.post(notification: .announcement, argument: L("已停止", "Stopped", "停止しました"))
    }

    /// 整个丢掉（现在只有截图用）。
    func endHelpReply() {
        cancelHelpTask()
        cancelHelpCountdown()
        helpMenuOpen = false
        helpListOpen = false
        helpKeyHold = false
        if helpReply != nil { helpReply = nil }
    }

    private func cancelHelpTask() {
        helpTask?.cancel()
        helpTask = nil
        helpToken &+= 1
    }

    // MARK: 请求

    /// 用润色接口（主接口，11-08 改）写现在这种的新一版（不思考、不联网，快），边写边显示。
    /// 内测版算润色次数，正式版没有次数限制。
    func writeCurrentHelp(direction: String?) {
        guard let state = helpReply, !state.isEmpty, let tag = state.currentTag else { return }
        let key = SettingsStore.apiKey
        guard BuiltinAPI.take(.polish, key: key) else {
            helpReply?.notes[tag.id] = .error(BuiltinAPI.limitMessage(.polish))
            return
        }
        let client = LLMClient(settings: settings, apiKey: key)
        let messages = HelpReply.messages(message: state.message, style: tag.style, direction: direction ?? "")
        // 点了帮回，识意框里的要求就变成绿字（执行过）。
        helpExecutedAsk = direction
        streamHelp(tag: tag, client: client, messages: messages, direction: direction, polish: nil, mainAPI: true,
                   statName: L("帮回", "Help Reply", "返信アシスト"), styleID: nil) {
            // 提示词页每种帮回风格的本周次数。
            DailyStats.add("reply.style.\(tag.id.uuidString)")
            DailyStats.flush()
        }
    }

    /// 帮回卡上点润色（RG3）：用选中的润色风格改这条回复，算当前帮回风格的新一版，卡片还是绿色。
    /// 改的是输入框里替换进去的那条（手改过也算）；还没替换就改卡上这条。
    /// 输入框里是和这条回复无关的话：返回 false，照平时润色（紫卡、润色 / 问答时间线）。
    func helpPolishTapped() -> Bool {
        guard let state = helpReply, let reply = state.current, let tag = state.currentTag else { return false }
        if target == .card { finishCardEdit() }
        finishComposition()
        let field = CommandParser.parse(readField().text).content.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: String
        if field.isEmpty || field == reply.text {
            source = reply.text
        } else if let inserted = state.insertedText, HelpReply.related(field, inserted) {
            source = field
        } else {
            return false
        }
        let style = runStyleOverride ?? settings.selectedStyle
        guard passGate(then: { [weak self] in
            self?.runStyleOverride = style
            _ = self?.helpPolishTapped()
            self?.runStyleOverride = nil
        }) else { return true }
        guard BuiltinAPI.take(.polish, key: SettingsStore.apiKey) else {
            helpReply?.notes[tag.id] = .error(BuiltinAPI.limitMessage(.polish))
            return true
        }
        cancelHelpCountdown()
        let client = LLMClient(settings: settings, apiKey: SettingsStore.apiKey)
        let name = style?.displayName ?? L("润色", "Polish", "整える")
        streamHelp(tag: tag, client: client, messages: Prompts.polish(source, style: style), direction: nil, polish: name,
                   mainAPI: true, statName: style?.displayName, styleID: style?.id) {}
        return true
    }

    /// 写一版：边写边显示（50 毫秒一次），写好接在这种风格后面、翻到这一版；出错、停止记在标签上。
    private func streamHelp(tag: HelpReplyState.Tag, client: LLMClient, messages: [ChatMessage], direction: String?, polish: String?,
                            mainAPI: Bool, statName: String?, styleID: UUID?, done: @escaping () -> Void) {
        guard var state = helpReply else { return }
        cancelHelpTask()
        state.running = tag.id
        state.runningPolish = polish != nil
        state.streaming = ""
        state.notes[tag.id] = nil
        state.successAt = nil
        state.countdownEnds = nil
        helpReply = state
        let token = helpToken
        let started = Date()
        func record(ok: Bool, error: String? = nil) {
            UsageStats.recordPolish(ms: Int(Date().timeIntervalSince(started) * 1000), ok: ok, styleID: styleID,
                                    mainAPI: mainAPI, styleName: statName, model: client.settings.model, error: error)
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
                state.runningPolish = false
                if text.isEmpty {
                    record(ok: false, error: UsageStats.Request.Failure.empty)
                    state.notes[tag.id] = .error(L("模型没有返回内容", "the model returned nothing", "応答なし"))
                    self.helpReply = state
                    return
                }
                record(ok: true)
                done()
                AIAccess.recordUse()
                self.refreshAIAccess()
                let now = Date()
                let reply = HelpReplyState.Reply(styleID: tag.id, name: tag.name, text: text, direction: direction,
                                                 polish: polish, at: now)
                state.results[tag.id, default: []].append(reply)
                state.pages[tag.id] = state.versions(tag.id).count - 1
                state.history.append(reply)
                state.successAt = now
                self.helpReply = state
                self.recordHelpHistory()
                UIAccessibility.post(notification: .announcement, argument: L("写好了", "Reply ready", "作成しました"))
                // 白色对勾画完（600ms）后停一会儿。
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    guard let self, self.helpReply?.successAt == now else { return }
                    withAnimation(.easeOut(duration: 0.3)) { self.helpKeyHold = false }
                }
            } catch {
                guard !Task.isCancelled, let self, self.helpToken == token, var state = self.helpReply else { return }
                record(ok: false, error: UsageStats.Request.Failure.of(error))
                state.running = nil
                state.streaming = ""
                state.runningPolish = false
                state.notes[tag.id] = .error(LLMFailure.of(error).title(provider: client.settings.providerName))
                self.helpReply = state
            }
        }
    }

    /// 历史（App › AI 历史「帮回」）：对方的话、每一版、用了哪版。同一句更新同一条。
    func recordHelpHistory() {
        guard let state = helpReply, !state.history.isEmpty else { return }
        let provider = settings.providerName
        let versions = state.history.map { reply in
            let used = reply.id == state.insertedID
            let round = (state.versions(reply.styleID).firstIndex { $0.id == reply.id } ?? 0) + 1
            var version = AIHistoryEntry.Version(text: reply.text, style: reply.polish.map { "\(reply.name) · ✨\($0)" } ?? reply.name,
                                                 provider: reply.provider ?? provider, use: used ? .inserted : reply.use,
                                                 at: reply.at, source: "reply",
                                                 usedAt: used ? state.insertedAt : reply.usedAt, round: round, direction: reply.direction)
            version.styleID = reply.styleID.uuidString
            version.polish = reply.polish
            return version
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
    /// -keyboardDebug help:key（^^ 是帮回、有红点）、help:hold（按住弹出颜文字格）、help:up（滑进颜文字格）、
    /// help:countdown（倒计时）、help:running（正在写、已经出了半句）、help:card（写好第 1 种）、help:second（写好 2 种、看第 2 种）、
    /// help:switching（切到第 3 种正在写）、help:all（3 种都写好）、help:versions（第 1 种有 3 版、看第 3 版）、
    /// help:direction（按要求写的一版，框里绿字）、help:pending（框里有没执行的字，帮回键亮）、help:polished（润色出的一版）、
    /// help:menu（⌄ 列表）、help:list（回哪句话列表，带一句 AI 历史里的）、help:empty（空卡）、help:consent（帮回的确认卡）、help:qwerty（全键盘，可和别的一起用）、help:dropdown（润色风格框）、help:emptylist（空卡、剪贴板也空、列表开着）、help:stopped（停了）、help:failed（第 3 种没写出来）、help:panel（剪贴板面板）、
    /// help:polish（帮回卡收起来、回到润色卡）。
    func applyHelpDebug(_ options: [String]) {
        guard !options.isEmpty else { return }
        debugUnblocked = true
        debugHelpClipboard = true
        // qwerty：全键盘（11.4：AI 栏上固定的帮回键）；dropdown：再打开润色 ⌄ 风格框（顶上「帮回」那段）。
        let wanted: KeyboardLayout = options.contains("qwerty") ? .qwerty : .nineKey
        if settings.keyboardLayout != wanted { setLayout(wanted) }
        if options.contains("dropdown") { aiRow = .prompts }
        clipboardHasNew = options.contains("key") || options.contains("countdown")
        helpDismissed = false
        let message = "这份方案明天能交吗？"
        let now = Date()
        clipItems = [
            ClipItem(text: message, date: now),
            ClipItem(text: "一起吃个饭，叫上小王，就在公司楼下那家火锅", date: now.addingTimeInterval(-720)),
            ClipItem(text: "周五的会能挪到下午吗", date: now.addingTimeInterval(-1800)),
        ]
        if options.contains("panel") {
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
        guard options.contains(where: { !["key", "qwerty", "dropdown"].contains($0) }) else { return }
        // consent：帮回第一次发送前的确认卡（RG9）。
        if options.contains("consent") {
            debugShowGate(.consent(endpoint: "api.moonshot.cn", previous: nil, purpose: .help))
            return
        }
        // empty：从没用过帮回时的空卡（RG5 ③）；emptylist：空卡 + 剪贴板记录也空、点开列表。
        if options.contains("empty") || options.contains("emptylist") {
            if options.contains("emptylist") { clipItems = [] }
            helpThreads = []
            helpRecentReplies = []
            var empty = HelpReplyState(historyID: UUID().uuidString, date: now, message: "")
            empty.tags = settings.checkedReplyStyles.map { HelpReplyState.Tag(id: $0.id, name: $0.displayName, style: $0) }
            helpReply = empty
            helpExecutedAsk = nil
            setInstruction("")
            aiExpanded = true
            hostFocused = true
            target = .host
            if options.contains("emptylist") { helpListOpen = true }
            return
        }
        var state = HelpReplyState(historyID: UUID().uuidString, date: now, message: message)
        let styles = settings.checkedReplyStyles
        state.tags = styles.map { HelpReplyState.Tag(id: $0.id, name: $0.displayName, style: $0) }
        let texts = ["好的，明天上午能交，我今晚再过一遍细节。", "可以的，明天上午发您，有问题随时说。", "能，明早给您。"]
        func add(_ index: Int, _ text: String, direction: String? = nil, polish: String? = nil) {
            guard styles.indices.contains(index) else { return }
            let style = styles[index]
            let reply = HelpReplyState.Reply(styleID: style.id, name: style.displayName, text: text, direction: direction,
                                             polish: polish, at: now)
            state.results[style.id, default: []].append(reply)
            state.history.append(reply)
        }
        // 写好了几种：card 写好第 1 种；second、switching、failed 写好 2 种；all、versions 三种都写好。
        let done: Int
        if options.contains("all") || options.contains("versions") || options.contains("list") { done = 3 }
        else if options.contains("second") || options.contains("switching") || options.contains("failed") { done = 2 }
        else if options.contains("running") || options.contains("stopped") || options.contains("countdown") { done = 0 }
        else { done = 1 }
        for index in 0..<min(done, styles.count) { add(index, texts[index % 3]) }
        var ask = ""
        var executed: String?
        if options.contains("versions") || options.contains("direction") || options.contains("pending") || options.contains("polished") {
            add(0, "后天上午交可以吗？想把细节再打磨下。", direction: "委婉点，说要后天")
            ask = "委婉点，说要后天"
            executed = ask
        }
        if options.contains("versions") || options.contains("polished") {
            add(0, "您好，方案预计后天上午提交，我想再完善一下细节，您看可以吗？", polish: "正式")
            ask = ""
            executed = nil
        }
        if options.contains("pending") { ask = "委婉点，说要大后天" }
        if options.contains("second") { state.index = min(1, state.tags.count - 1) }
        if options.contains("running"), let first = state.tags.first {
            state.running = first.id
            state.streaming = "好的，明天上午能交，我今"
        }
        // switching：第 1、2 种写好了，点了第 3 种正在写，已经出了半句。
        if options.contains("switching"), state.tags.count > 2 {
            state.index = 2
            state.running = state.tags[2].id
            state.streaming = "能，明"
        }
        if options.contains("countdown") { state.countdownEnds = now.addingTimeInterval(2) }
        if options.contains("stopped"), let first = state.tags.first { state.notes[first.id] = .stopped }
        if options.contains("failed"), state.tags.count > 2 {
            state.index = 2
            state.notes[state.tags[2].id] = .error(L("网络断了", "network lost", "ネットワーク切断"))
        }
        helpThreads = [
            {
                var old = HelpReplyState(historyID: UUID().uuidString, date: now.addingTimeInterval(-720),
                                         message: "一起吃个饭，叫上小王，就在公司楼下那家火锅")
                old.tags = state.tags
                if let first = styles.first {
                    for text in ["好啊，几点？", "好啊，周六晚上可以！"] {
                        old.results[first.id, default: []].append(HelpReplyState.Reply(styleID: first.id, name: first.displayName,
                                                                                        text: text, at: now))
                    }
                }
                return old
            }(),
        ]
        helpReply = state
        helpKeyHold = state.running != nil
        helpExecutedAsk = executed
        setInstruction(ask)
        aiExpanded = true
        hostFocused = !options.contains("pending")
        target = options.contains("pending") ? .instruction : .host
        if options.contains("menu") { helpMenuOpen = true }
        if options.contains("list") {
            // AI 历史里昨天回过的一句（11-08：列表读历史）。
            let style = styles.first?.displayName ?? "客气"
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            helpRecentReplies = [AIHistoryEntry(id: UUID().uuidString, kind: .reply, date: yesterday, original: "周末一起去爬山吗？",
                                                context: "", versions: [
                                                    AIHistoryEntry.Version(text: "好呀，周六上午出发？", style: style),
                                                    AIHistoryEntry.Version(text: "可以，我带水。", style: style),
                                                ])]
            helpListOpen = true
        }
        if options.contains("polish") { parkHelpReply() }
    }
}
#endif
