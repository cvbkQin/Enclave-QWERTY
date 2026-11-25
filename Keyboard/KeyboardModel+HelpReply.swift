import SwiftUI
import UIKit

/// AI 帮回（T16）并进润色（方案 D v6，design/help-reply/merge-polish/）：帮回就是润色的一种，原文换成剪贴板里对方的那句话（点了才读），
/// 风格用当前润色风格，识意框里的字是要求，输入框里自己打的字当「我想说的意思」一起发。
/// 接口、回答卡、时间线、替换键、确认卡、次数全和润色共用：请求走 run(_:pending:reply:)，结果是会话里的一版（标「回」）。
/// 入口（T96，design/help-reply/entry-v2）：润色 ⌄ 最上面一行、剪贴板记录长按「帮回这条」，再加一个开关「复制后弹出帮回键」（settings.helpAuto）：
/// 开着时刚复制别人的话，问答键右边弹出帮回键；关着时润色键换成帮回图标，输入框空着时点润色就是帮回。
/// 键盘每次弹出只看剪贴板的 changeCount（已有的轮询）和一次 detectPatterns，没有别的帮回状态和视图。
extension KeyboardModel {
    private static let copyKey = "helpReply.copy.v2"
    private static let lookKey = "helpReply.lookedAt"
    /// 这个键盘进程上次看剪贴板的时间，和上次存进共享容器的时间（5 秒存一次）。
    private static var lastLook: Date?
    private static var lastLookSaved: Date?

    /// 润色开着、能用才有帮回（帮回走润色接口）。只看能不能用（polishUsable）不够：App 里关掉润色以后，
    /// 钉住的帮回键、「帮回这条」、剪贴板判断都还在（bug #34），和钉住的润色风格键（这时藏起来）不一致。
    var helpReplyAvailable: Bool {
        (hasFullAccess || debugUnblocked) && (settings.helpReplyUsable || debugUnblocked)
    }

    /// 键盘看剪贴板有没有可以帮回的新复制（T96 起开关开着关着都看：关着时要给润色键换图标）。
    /// 规则在 EnclaveSettings.helpAutoDetects（有单测），这里再加上完全访问；截图调试时不看接口能不能用。
    var helpAutoOn: Bool {
        (hasFullAccess || debugUnblocked) && (debugUnblocked || settings.helpAutoDetects)
    }

    /// 有待回的复制（⌄ 里帮回那一行的浅绿底）。
    var helpShowsPending: Bool { helpPending && helpAutoOn }

    /// 「复制后弹出帮回键」开着（⌄ 里帮回那一行的图钉）。
    var helpPopupOn: Bool { helpReplyAvailable && settings.helpAuto }

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
        guard hasFullAccess, helpAutoOn else {
            setHelpPending(false)
            helpExpiry?.cancel()
            helpExpiry = nil
            return
        }
        let board = UIPasteboard.general
        let stored = Self.storedCopy
        let now = Date()
        let copy = HelpCopy.observe(stored, count: board.changeCount, hasStrings: board.hasStrings, now: now, lookedAt: Self.previousLook())
        noteClipboardLook(now: now)
        if copy != stored { Self.storedCopy = copy }
        if copy.suits == nil, !copy.used, Date() < copy.expires {
            detectHelpCopy(count: copy.count)
        }
        applyHelpCopy(copy)
    }

    /// 键盘开着时剪贴板轮询每秒调一次、弹出查剪贴板时也调：记下键盘还看着剪贴板的时间。
    /// 键盘没开着时剪贴板换了，复制时间最早只能算到这里。各个 App 里的键盘进程共用，5 秒存一次。
    /// 润色关着（帮回用不了）时不记：再打开时，关着那段时间里换的剪贴板复制时间按很久以前算，不会突然弹出帮回键。
    func noteClipboardLook(now: Date = Date()) {
        guard helpAutoOn else { return }
        Self.lastLook = now
        if let saved = Self.lastLookSaved, now.timeIntervalSince(saved) >= 0, now.timeIntervalSince(saved) < 5 { return }
        Self.lastLookSaved = now
        SharedStorage.defaults.set(now.timeIntervalSince1970, forKey: Self.lookKey)
    }

    /// 键盘上次看剪贴板的时间：这个进程记的和别的 App 里的键盘存的，取晚的那个。都没有就是 nil（分不清，当很久以前）。
    private static func previousLook() -> Date? {
        let stored = SharedStorage.defaults.double(forKey: lookKey)
        let saved = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        switch (lastLook, saved) {
        case let (a?, b?): return max(a, b)
        case let (a, b): return a ?? b
        }
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

    /// 不在这里包动画：弹出、收回的动画在视图上按 helpKeyShown 带（AI 栏横排、iPad 九宫格竖排让位方向不一样）。
    private func setHelpPending(_ value: Bool) {
        if helpPending != value { helpPending = value }
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

    // MARK: 润色键、弹出的帮回键（T96）

    /// 输入框里有字（正在拼的拼音也算）。
    var helpFieldHasText: Bool { hostHasText || (target == .host && isComposing) }

    /// 开关关着、有待回的复制：润色键的 ✦ 换成彩色帮回 logo，字不变（图 ⑤⑥）；输入框空着时点润色就是帮回。
    var polishKeyHelpLogo: Bool { helpShowsPending && !settings.helpAuto }

    /// 关着、有待回的复制、输入框空：点润色键是帮回。
    var polishKeyHelps: Bool { polishKeyHelpLogo && !helpFieldHasText }

    /// 问答键右边弹出的帮回键（开关开着，图 ②③）：有待回的复制时弹出；用过或复制满 1 分钟收回，
    /// 但这颗键刚发起的帮回还在生成中、失败等着点重试、成功动效那两秒、回答卡开着正看着这一版时先不收。
    /// iPhone AI 栏和 iPad 九宫格那一列都看它；弹出、收回的动画在视图上带（HelpKeyPop）。
    var helpKeyShown: Bool {
        guard helpPopupOn else { return false }
        if helpShowsPending || helpWait != nil { return true }
        guard lastRunPin == Self.helpPinID else { return false }
        if isRunning || helpKeyCelebrating { return true }
        if quickStatus == .failed { return true }
        return aiExpanded && session?.currentIsReply == true
    }

    /// 回答卡展开、弹出了帮回键、输入框空：卡里和识意框的灰字说说帮回怎么用（框里写的是怎么回）。生成中不出。
    var helpReplyHint: Bool {
        aiExpanded && helpPopupOn && helpShowsPending && !helpFieldHasText && !isRunning && target != .card
    }

    // MARK: 入口

    /// 弹出的帮回键（生成中、成功动效按它找键；长按弹的「取消固定」用 pinMenu 记它）。
    static let helpPinID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    /// 「复制后弹出帮回键」开关：润色 ⌄ 那一行的图钉、长按帮回键的「取消固定」、App 里的开关是同一个。框不收。
    func toggleHelpPopup() {
        updateSettings { $0.helpAuto.toggle() }
        if pinMenu != nil { pinMenu = nil }
    }

    /// 润色 ⌄ 最上面那一行「↩ 帮回 · 用『正式』」：帮回，下拉框收起。
    func helpRowTapped() {
        aiRow = nil
        startHelpReply()
    }

    /// 弹出的帮回键：帮回，输入框有没有字都一样。生成中点了是停止。
    func helpKeyTapped() {
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

    /// 帮回一次：读剪贴板（给了 text 就用它），用当前润色风格写一条，接在当前时间线后面。结果出在回答卡上（收着时先展开），
    /// 识意框里的字是要求。帮回加要求（对齐清单第 94 条，design/help-reply/again）：
    /// - 卡上是帮回写的一版、又没有新的待回复制（HR1）：回这一版记下的原话，不读剪贴板，系统横幅不再闪。
    /// - 开新的一句、识意框空着（HW1）：先等 2 秒，等的时候点识意框就停下，写好要求再点帮回；再点帮回键马上回。
    /// keepPin：从润色键转过来的（写了要求点润色），执行动效留在被点的那颗键上。
    func startHelpReply(text given: String? = nil, fromPin: Bool = false, keepPin: Bool = false, style: StylePreset? = nil) {
        endCelebration()
        if isRunning { stop(); return }
        if !keepPin { lastRunPin = fromPin ? Self.helpPinID : nil }
        if aiRow != nil { aiRow = nil }
        // 正在等，或停下来等要求：不等了，马上回（HW1 第 6、7 条）。
        if helpWait != nil {
            runHelpWait(style: style)
            return
        }
        guard passGate(then: { [weak self] in self?.startHelpReply(text: given, fromPin: fromPin, keepPin: keepPin, style: style) }) else { return }
        reload()
        if target == .card { finishCardEdit() }
        finishComposition()
        var message = given?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var changeCount: Int?
        var again = false
        if given == nil, let source = HelpWait.againSource(expanded: aiExpanded, pending: helpShowsPending, current: session?.currentReplySource) {
            message = source.message
            again = true
        } else if given == nil {
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
        if HelpWait.waitsBeforeReply(again: again, request: helpRequest) {
            beginHelpWait(message: message, changeCount: changeCount, fromPin: fromPin)
            return
        }
        runHelpReply(message: message, changeCount: changeCount, style: style)
    }

    /// 识意框里的要求（回答卡展开时才算；点「问答」自动填进去的问题不算）。
    private var helpRequest: String {
        guard aiExpanded else { return "" }
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if let auto = askAutoFill, text == auto { return "" }
        return text
    }

    /// 识意框灰字「补充要求，再点「帮回」重写」（HR1 第 1 条）：回答卡展开、卡上是帮回写的一版、不在生成中。
    var helpAgainHint: Bool {
        aiExpanded && session?.currentIsReply == true && !isRunning
    }

    /// 正在等（还没被打断）。识意框这时不算在编辑：不亮紫线、不闪光标，点一下才停下来进编辑。
    var helpWaiting: Bool { helpWait?.interrupted == false }

    /// 识意框里有还没用过的要求：帮回键外面亮一圈绿（HW1 ③）。停下来等要求时，或卡上是帮回写的一版、框里的要求和这一版用的不一样。
    var helpKeyRing: Bool {
        guard aiExpanded, !isRunning else { return false }
        let request = helpRequest
        guard !request.isEmpty else { return false }
        if helpWait?.interrupted == true { return true }
        guard let source = session?.currentReplySource else { return false }
        return source.request?.trimmingCharacters(in: .whitespacesAndNewlines) != request
    }

    // MARK: 开始前的等待（HW1–HW3）

    /// 开始等：回答卡收着就先展开（结果不再直接进输入框，要留出写要求的地方），识意框清空，2 秒后自动回。
    private func beginHelpWait(message: String, changeCount: Int?, fromPin: Bool) {
        if !aiExpanded { setAIExpanded(true) }
        if !instruction.isEmpty { setInstruction("") }
        if askSelected { askSelected = false }
        askAutoFill = nil
        errorMessage = nil
        clearFailure()
        helpWaitTimer?.cancel()
        helpWaitLanded = nil
        helpWaitFlashing = false
        helpWait = HelpWait(message: message, changeCount: changeCount, fromPin: fromPin, startedAt: Date())
        helpWaitBrushOn = true
        let work = DispatchWorkItem { [weak self] in self?.landHelpWait() }
        helpWaitTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HelpWait.duration, execute: work)
        // 第一次读钥匙串慢（06 iPad 核对约 140ms）：趁等的时候在后台先读一次，走满那一刻不卡。
        DispatchQueue.global(qos: .userInitiated).async { _ = SettingsStore.apiKey }
        UIAccessibility.post(notification: .announcement,
                             argument: L("2 秒后自动帮回，点识意框可以先写要求", "Replying in 2 seconds. Tap the box to add a request first.",
                                         "2 秒後に自動で返信します。欄をタップすると先に指示を書けます"))
    }

    /// 2 秒走满：笔刷尽头一亮碎成光点，白光刷过、卡边绿光一闪，同一刻开始帮回。
    private func landHelpWait() {
        guard let wait = helpWait, !wait.interrupted else { return }
        let now = Date()
        helpWaitLanded = now
        helpWaitFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.helpWaitLanded == now else { return }
            self.helpWaitFlashing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.helpWaitLanded == now, self.helpWait == nil else { return }
            self.helpWaitBrushOn = false
            self.helpWaitLanded = nil
        }
        // 先让闪光那一帧画出来，下一帧再发请求（建请求在主线程上，第一次慢时会把闪光压住）。
        let started = wait.startedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self, self.helpWait?.startedAt == started else { return }
            self.runHelpWait(landed: true)
        }
    }

    /// 不等了，用等着的那句回（走满、再点帮回键、停下后写好要求点帮回或回车、写了要求点润色）。
    func runHelpWait(landed: Bool = false, style: StylePreset? = nil) {
        guard let wait = helpWait else { return }
        helpWaitTimer?.cancel()
        helpWaitTimer = nil
        helpWait = nil
        if !landed {
            helpWaitBrushOn = false
            helpWaitLanded = nil
            helpWaitFlashing = false
        }
        if target == .card { finishCardEdit() }
        finishComposition()
        runHelpReply(message: wait.message, changeCount: wait.changeCount, style: style)
    }

    /// 点识意框、在框里打字：计时停下，笔刷顿住、变灰往回收、淡掉，不再自动回；原话留着，等写要求。
    func interruptHelpWait() {
        guard var wait = helpWait, !wait.interrupted else { return }
        helpWaitTimer?.cancel()
        helpWaitTimer = nil
        let now = Date()
        wait.interruptedAt = now
        helpWait = wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.helpWait?.interruptedAt == now else { return }
            self.helpWaitBrushOn = false
        }
    }

    /// 收起回答卡、收起键盘、改点别的：取消，不回，也不算次数。
    func cancelHelpWait() {
        guard helpWait != nil else { return }
        helpWaitTimer?.cancel()
        helpWaitTimer = nil
        helpWait = nil
        helpWaitBrushOn = false
        helpWaitLanded = nil
        helpWaitFlashing = false
    }

    /// 真正发出去：输入框里自己打的字当「我想说的意思」，识意框的字（加上输入框里的「// 要求」）当要求。
    private func runHelpReply(message: String, changeCount: Int?, style override: StylePreset?) {
        let parsed = CommandParser.parse(readField(remember: true).text)
        dropSession(unlessItBelongsTo: parsed.content)
        // 输入框里自己打的字当「我想说的意思」；是上一版结果（替换进去的回复、润色结果）就不算。
        var meaning = parsed.content
        if let session, resultUse != nil || session.versions.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == meaning
        }) {
            meaning = ""
        }
        var request = helpRequest
        if !parsed.instruction.isEmpty { request = request.isEmpty ? parsed.instruction : parsed.instruction + "\n" + request }
        let style = override ?? settings.selectedStyle
        let messages = HelpReply.messages(message: message, style: style, meaning: meaning, request: request)
        let reply = ReplyRequest(source: EditSession.ReplySource(message: message, request: request.isEmpty ? nil : request,
                                                                 meaning: meaning.isEmpty ? nil : meaning),
                                 changeCount: changeCount)
        let pending = session ?? EditSession(mode: .polish, original: parsed.content)
        if askSelected { askSelected = false }
        // 结果出在回答卡上（HW1 第 1 条：原来收着时结果直接进输入框的做法不用了）。
        if !aiExpanded { setAIExpanded(true) }
        let previous = runStyleOverride
        runStyleOverride = override
        start(from: .polish) { run(messages, pending: pending, reply: reply) }
        runStyleOverride = previous
    }
}

// MARK: - 模拟器截图用

#if DEBUG
extension KeyboardModel {
    /// -keyboardDebug help:pending（有待回的复制）、help:typed（输入框里有字）、help:expanded（回答卡展开）、
    /// help:result（展开，卡上是帮回写的一版，复制算用过）、help:off（关掉「复制后弹出帮回键」）、help:dropdown（打开润色 ⌄）、
    /// help:consent（润色确认卡）、help:qwerty（全键盘）、help:panel（剪贴板面板）。
    func applyHelpDebug(_ options: [String]) {
        guard !options.isEmpty else { return }
        debugUnblocked = true
        debugHelpClipboard = true
        let wanted: KeyboardLayout = options.contains("qwerty") ? .qwerty : .nineKey
        if settings.keyboardLayout != wanted { setLayout(wanted) }
        if options.contains("off") == settings.helpAuto { updateSettings { $0.helpAuto = !options.contains("off") } }
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
