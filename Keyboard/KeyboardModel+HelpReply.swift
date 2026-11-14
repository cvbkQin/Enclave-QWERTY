import SwiftUI
import UIKit

/// AI 帮回（T16）并进润色（方案 D v6，design/help-reply/merge-polish/）：帮回就是润色的一种，原文换成剪贴板里对方的那句话（点了才读），
/// 风格用当前润色风格，识意框里的字是要求，输入框里自己打的字当「我想说的意思」一起发。
/// 接口、回答卡、时间线、替换键、确认卡、次数全和润色共用：请求走 run(_:pending:reply:)，结果是会话里的一版（标「回」）。
/// 入口：润色 ⌄ 最上面一行、识意框右边的帮回按钮、刚复制时变绿的润色键、钉在 AI 栏的帮回键、剪贴板记录长按「帮回这条」。
/// 键盘每次弹出只看剪贴板的 changeCount（已有的轮询）和一次 detectPatterns，没有别的帮回状态和视图。
extension KeyboardModel {
    private static let copyKey = "helpReply.copy.v2"

    /// 润色接口（主接口）能用才有帮回。
    var helpReplyAvailable: Bool {
        (hasFullAccess || debugUnblocked) && (settings.polishUsable || debugUnblocked)
    }

    // MARK: 待回的复制

    private static var storedCopy: HelpCopy? {
        get {
            guard let data = SharedStorage.defaults.data(forKey: copyKey) else { return nil }
            return try? JSONDecoder().decode(HelpCopy.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                SharedStorage.defaults.set(data, forKey: copyKey)
            } else {
                SharedStorage.defaults.removeObject(forKey: copyKey)
            }
        }
    }

    /// 键盘出现、剪贴板换了（1 秒一次的轮询）时：只看 changeCount、hasStrings；新的一份用 detectPatterns 判断是不是链接、纯数字（不读内容）。
    func refreshHelpCopy() {
        #if DEBUG
        if debugHelpClipboard { return }
        #endif
        guard hasFullAccess, helpReplyAvailable else {
            setHelpPending(false)
            return
        }
        let board = UIPasteboard.general
        let stored = Self.storedCopy
        let copy = HelpCopy.observe(stored, count: board.changeCount, hasStrings: board.hasStrings)
        if copy != stored { Self.storedCopy = copy }
        if copy.suits == nil, !copy.used, Date() < copy.expires {
            detectHelpCopy(count: copy.count)
        }
        applyHelpCopy(copy)
    }

    /// 系统判断剪贴板里是不是链接、纯数字：不读内容、不弹「粘贴自…」横幅。查不出来就当能帮回。
    private func detectHelpCopy(count: Int) {
        UIPasteboard.general.detectPatterns(for: [.probableWebURL, .number]) { [weak self] result in
            let suits: Bool
            switch result {
            case .success(let patterns): suits = patterns.isEmpty
            case .failure: suits = true
            }
            Task { @MainActor in
                guard let self, var copy = Self.storedCopy, copy.count == count, copy.suits == nil else { return }
                copy.suits = suits
                Self.storedCopy = copy
                self.applyHelpCopy(copy)
            }
        }
    }

    private func applyHelpCopy(_ copy: HelpCopy) {
        let pending = copy.pending()
        setHelpPending(pending)
        helpExpiry?.cancel()
        helpExpiry = nil
        guard pending else { return }
        let work = DispatchWorkItem { [weak self] in self?.refreshHelpCopy() }
        helpExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(copy.expires.timeIntervalSinceNow, 0) + 0.05, execute: work)
    }

    private func setHelpPending(_ value: Bool) {
        if helpPending != value { withAnimation(.easeOut(duration: 0.2)) { helpPending = value } }
    }

    /// 帮回写好了：这份复制算用过。
    func markHelpCopyUsed(count: Int) {
        guard var copy = Self.storedCopy, copy.count == count else {
            Self.storedCopy = HelpCopy(count: count, seen: Date(), used: true, suits: nil)
            setHelpPending(false)
            return
        }
        copy.used = true
        Self.storedCopy = copy
        applyHelpCopy(copy)
    }

    /// 键盘自己写了剪贴板（复制结果、分词复制、复制一条记录）：不算新复制的内容，也不是待回的复制。
    func noteOwnCopy() {
        let count = UIPasteboard.general.changeCount
        ClipboardHistory.lastChangeCount = count
        if clipboardHasNew { clipboardHasNew = false }
        Self.storedCopy = HelpCopy(count: count, seen: Date(), used: true, suits: nil)
        setHelpPending(false)
    }

    // MARK: 润色键、识意框按钮的样子（§3 四种情况）

    /// 输入框里有字（正在拼的拼音也算）。
    private var helpFieldHasText: Bool { hostHasText || (target == .host && isComposing) }

    /// 润色键整颗变成绿色「↩ 帮回 ⌄」（情况 ①③）：有待回的复制、输入框空、帮回没钉到 AI 栏。
    var polishKeyIsHelp: Bool {
        helpPending && !settings.helpPinned && !helpFieldHasText && helpReplyAvailable
    }

    /// 润色键还是紫色「润色」，只把 ✨ 换成降饱和的绿色帮回 logo（情况 ②④、钉住以后）。
    var polishKeyHelpLogo: Bool { helpPending && !polishKeyIsHelp && helpReplyAvailable }

    enum HelpAskButtonLook { case solid, outline }

    /// 识意框右边的帮回按钮（回答卡展开、有待回的复制）：输入框空是绿色实心，有字是浅绿描边。生成中不出。
    var helpAskButton: HelpAskButtonLook? {
        guard aiExpanded, helpPending, helpReplyAvailable, !isRunning, target != .card else { return nil }
        return helpFieldHasText ? .outline : .solid
    }

    // MARK: 入口

    /// AI 栏上固定帮回键的那颗「钉子」（长按弹的取消固定用 pinMenu 记它；生成中、成功动效也按它找键）。
    static let helpPinID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    /// 帮回键在 AI 栏上：帮回能用，且钉上了（默认不钉，全键盘和九宫格同一个设置）。
    var helpPinnedOnBar: Bool { helpReplyAvailable && settings.helpPinned }

    /// 润色 ⌄ 那一行的图钉、长按 AI 栏上帮回键的「取消固定」。框不收。
    func toggleHelpPin() {
        updateSettings { $0.helpPinned.toggle() }
        if pinMenu != nil { pinMenu = nil }
    }

    /// 润色 ⌄ 最上面那一行「↩ 帮回 · 用『正式』」：帮回，下拉框收起。
    func helpRowTapped() {
        aiRow = nil
        startHelpReply()
    }

    /// 识意框右边的「帮回」按钮。
    func helpAskButtonTapped() {
        startHelpReply()
    }

    /// AI 栏上钉住的帮回键。生成中点了是停止。
    func pinnedHelpTapped() {
        pinMenu = nil
        startHelpReply(fromPin: true)
    }

    /// 剪贴板记录长按菜单「帮回这条」：用这条（本机存好的，不读剪贴板），挪到最前。
    func helpFromClip(_ item: ClipItem) {
        clipMenu = nil
        guard passGate(then: { [weak self] in self?.helpFromClip(item) }) else { return }
        clipItems = ClipboardHistory.add(item.text)
        closePanel()
        startHelpReply(text: item.text)
    }

    /// 帮回一次：读剪贴板（给了 text 就用它），用当前润色风格写一条，接在当前时间线后面。
    /// 回答卡收着：结果直接放进输入框（有字就替换），和收起时的润色一样能撤销；展开：结果出在卡上，识意框里的字是要求。
    func startHelpReply(text given: String? = nil, fromPin: Bool = false) {
        endCelebration()
        if isRunning { stop(); return }
        lastRunPin = fromPin ? Self.helpPinID : nil
        if aiRow != nil { aiRow = nil }
        guard passGate(then: { [weak self] in self?.startHelpReply(text: given, fromPin: fromPin) }) else { return }
        reload()
        if target == .card { finishCardEdit() }
        finishComposition()
        var message = given?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var changeCount: Int?
        if given == nil {
            // 这时才读剪贴板（系统「粘贴自…」横幅照常闪），存进剪贴板记录。剪贴板空就只提示。
            let board = UIPasteboard.general
            let count = board.changeCount
            let text = board.hasStrings ? (board.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !text.isEmpty else {
                showKeysToast(L("先复制对方的一句话", "Copy their message first", "まず相手のメッセージをコピーしてください"))
                return
            }
            ClipboardHistory.lastChangeCount = count
            if clipboardHasNew { clipboardHasNew = false }
            clipItems = ClipboardHistory.add(text)
            message = text
            changeCount = count
        }
        guard !message.isEmpty else { return }
        #if DEBUG
        if debugFakeRun { fakeCoachRun(); return }
        #endif
        let parsed = CommandParser.parse(readField(remember: true).text)
        dropSession(unlessItBelongsTo: parsed.content)
        // 输入框里自己打的字当「我想说的意思」；是上一版结果（替换进去的回复、润色结果）就不算。
        var meaning = parsed.content
        if let session, resultUse != nil || session.versions.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == meaning
        }) {
            meaning = ""
        }
        // 要求：回答卡展开时识意框里的字（点「问答」自动填进去的问题不算），加上输入框里的「// 要求」。
        var request = aiExpanded ? instruction.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if let auto = askAutoFill, request == auto { request = "" }
        if !parsed.instruction.isEmpty { request = request.isEmpty ? parsed.instruction : parsed.instruction + "\n" + request }
        let style = settings.selectedStyle
        let messages = HelpReply.messages(message: message, style: style, meaning: meaning, request: request)
        let reply = ReplyRequest(source: EditSession.ReplySource(message: message, request: request.isEmpty ? nil : request,
                                                                 meaning: meaning.isEmpty ? nil : meaning),
                                 changeCount: changeCount)
        let pending = session ?? EditSession(mode: .polish, original: parsed.content)
        if askSelected { askSelected = false }
        guard !aiExpanded else {
            start(from: .polish) { run(messages, pending: pending, reply: reply) }
            return
        }
        beginQuickMode(source: readField().text)
        start(from: .polish) { run(messages, pending: pending, reply: reply) }
        // 没开始（次数用完之类）就展开，把原因显示出来。
        if !isRunning {
            quickSource = nil
            clearQuickStatus()
            setAIExpanded(true)
        }
    }
}

// MARK: - 模拟器截图用

#if DEBUG
extension KeyboardModel {
    /// -keyboardDebug help:pending（有待回的复制）、help:typed（输入框里有字）、help:expanded（回答卡展开）、
    /// help:result（展开，卡上是帮回写的一版，复制算用过）、help:pinned（钉到 AI 栏）、help:dropdown（打开润色 ⌄）、
    /// help:consent（润色确认卡）、help:qwerty（全键盘）、help:panel（剪贴板面板）。
    func applyHelpDebug(_ options: [String]) {
        guard !options.isEmpty else { return }
        debugUnblocked = true
        debugHelpClipboard = true
        let wanted: KeyboardLayout = options.contains("qwerty") ? .qwerty : .nineKey
        if settings.keyboardLayout != wanted { setLayout(wanted) }
        if options.contains("pinned") != settings.helpPinned { updateSettings { $0.helpPinned = options.contains("pinned") } }
        helpPending = options.contains("pending") || options.contains("typed")
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
        if options.contains("consent") {
            debugShowGate(.consent(endpoint: "api.moonshot.cn", previous: nil, purpose: .polish))
            return
        }
        if options.contains("typed") { hostHasText = true }
        if options.contains("result") {
            var session = EditSession(mode: .polish, original: "")
            session.append("方案细节我再完善一下，后天上午发给您可以吗？有问题我随时沟通。")
            session.noteCurrent(style: settings.selectedStyle?.displayName, provider: settings.providerName,
                                source: EditSession.VersionSource.reply)
            session.markReply(EditSession.ReplySource(message: message))
            loadDebugSession(session)
            helpPending = false
        }
        if options.contains("expanded") || options.contains("result") {
            aiExpanded = true
            hostFocused = true
            target = .host
        }
        if options.contains("dropdown") { aiRow = .prompts }
    }
}
#endif
