import AudioToolbox
import QuartzCore
import UIKit

/// 打字：按键、组字、上屏，以及把文字送到聊天输入框还是要求框。
extension KeyboardModel {
    /// card：在结果卡片里直接改。
    enum InputTarget { case host, instruction, card }
    /// digits 是九宫格的数字键盘；numbers、symbols 是全键盘那样的数字符号页（九宫格的 #@¥ 也进这里）。
    enum KeyLayer { case letters, numbers, symbols, digits }
    enum ShiftState { case off, on, locked }

    /// 正在拼，或者还有字母在后台引擎里排着（结果还没回来）。
    var isComposing: Bool { !composition.isEmpty || QueuedEngine.shared.pending > 0 }
    /// 现在画的是五列的九宫格（拼音或数字），按下不出放大气泡。
    var nineGrid: Bool { showsNineKey && (layer == .letters || layer == .digits) }

    func typeLetter(_ letter: String) {
        let text = shift == .off ? letter : letter.uppercased()
        if shift == .on { shift = .off }
        // 大写字母不进拼音组字，直接上屏（先把排着的字母处理完，顺序才对）。
        if text != letter {
            applyEngineResults(wait: true)
            commit(text)
            return
        }
        feedEngine(text)
    }

    /// 字母、九宫格数字交给拼音引擎。拼音引擎在后台算，这里不等，算完由 applyEngineResults 上屏、更新候选。
    func feedEngine(_ key: String) {
        recentCorrection = nil
        dismissCandidateMenu()
        closeCandidateUndo()
        guard let queued = engine as? QueuedEngine else {
            if let output = engine.input(key) { commit(output) }
            syncEngine()
            return
        }
        queued.inputLater(key, since: keyEventTime)
        keyEventTime = nil
    }

    /// 取回后台算完的按键：按顺序上屏，再显示最新的拼写和候选。wait：先等排着的键算完（同步操作前用）。
    func applyEngineResults(wait: Bool = false) {
        let queued = QueuedEngine.shared
        let results = wait ? queued.drain() : queued.takeResults()
        guard !results.isEmpty else { return }
        for result in results {
            if let text = result.commit { commit(text) }
        }
        syncEngine()
        // 下一轮主循环时界面已经按新候选画完，这时记耗时。
        DispatchQueue.main.async {
            let shown = CACurrentMediaTime()
            for result in results {
                QueuedEngine.signposter.endInterval("key", result.signpost)
                TypingStats.record(total: shown - result.queuedAt, engine: result.engineTime)
            }
        }
    }

    /// 候选只先取了第一屏：候选栏滑到最后、展开整页时再往后取。
    func loadMoreCandidates() {
        guard isComposing else { return }
        engine.loadMoreCandidates()
        if engine.candidates.count != candidates.count { candidates = engine.candidates }
    }

    /// 数字、标点等非字母键：先把正在组的字上屏。
    func typeSymbol(_ symbol: String) {
        if isComposing, let first = engine.select(0) { commit(first) }
        engine.reset()
        syncEngine()
        commit(symbol)
    }

    func deleteKey() {
        if undoCorrection() { return }
        if undoLastChoice() { return }
        if engine.backspace() {
            syncEngine()
            return
        }
        switch target {
        case .host:
            editProxy?.deleteBackward()
            notePickDeleted()
            updateAutoShift()
        case .instruction:
            deleteInInstruction()
        case .card:
            deleteInCard()
        }
    }

    func spaceKey() {
        if isComposing {
            selectCandidate(0)
            return
        }
        // 连按两下空格：把第一个空格换成句号，和系统的「句号快捷键」一样。
        let now = Date()
        if target == .host, now.timeIntervalSince(lastSpaceTime) < 0.45,
           let before = proxy?.documentContextBeforeInput, before.hasSuffix(" "),
           let previous = before.dropLast().last, !previous.isWhitespace, !previous.isPunctuation {
            editProxy?.deleteBackward()
            commit(chineseMode ? "。" : ". ")
            lastSpaceTime = .distantPast
        } else {
            commit(" ")
            lastSpaceTime = now
        }
        // 数字符号页打完空格回到字母；九宫格数字键盘和原生一样留着，方便接着打数字。
        if layer != .letters && layer != .digits { layer = .letters }
    }

    /// 组字时回车把字母原样上屏；在识意框里回车就是 ✨。
    func returnKey() {
        if isComposing {
            if let raw = engine.commitComposition() { commit(raw) }
            syncEngine()
            return
        }
        switch target {
        case .host: editProxy?.insertText("\n")
        case .instruction:
            askTapped(askButtonMode)
        case .card:
            commit("\n")
        }
    }

    func selectCandidate(_ index: Int) {
        // 选了候选：前面打的拼音键都没按错，算进手指习惯。
        TouchCalibration.confirm()
        let before = choiceState
        let segmented = !engine.selections.isEmpty
        let text = engine.select(index)
        if let text { commit(text) }
        if let text, commonWordTexts.contains(text) { UsageStats.wordCommitted(text) }
        syncEngine()
        recordChoice(from: before)
        // 一次点完、不是首选的词才记：首选本来就排第一，分段选的上屏的是几段拼起来的字。
        if let text, index > 0, !segmented, !isComposing, chineseMode, target == .host {
            recentPick = RecentPick(word: text, left: text.count, time: Date())
        }
        if let text, let corrected = engine.lastCorrection, corrected.text == text, !isComposing, target == .host {
            recentCorrection = corrected
            recentPick = nil
        }
        if let text, !isComposing, chineseMode { showPredictions(after: text) }
    }

    /// 候选长按「删除」：只删拼音学到的词，词库自带的词 librime 只会降回原位，不动词库。
    /// 返回 false 表示没删掉。
    @discardableResult
    func deleteLearnedCandidate(_ index: Int) -> Bool {
        guard chineseMode, engine.candidates.indices.contains(index) else { return false }
        let deleted = engine.deleteCandidate(index)
        syncEngine()
        return deleted
    }

    // MARK: - 撤回纠错

    /// 纠正的词上屏后马上按删除：删掉这几个字，恢复成原样按的拼音，和 iOS 撤销自动更正一样；
    /// 同样的输入以后不再纠（CorrectionMemory.reject）。
    func undoCorrection() -> Bool {
        guard let undo = recentCorrection else { return false }
        recentCorrection = nil
        guard target == .host, !isComposing else { return false }
        for _ in 0..<undo.text.count { editProxy?.deleteBackward() }
        CorrectionMemory.reject(undo.typed)
        engine.replaceInput(undo.typed, keeping: [])
        syncEngine()
        return true
    }

    // MARK: - 点错的候选

    struct RecentPick {
        let word: String
        /// 还剩几个字没被删。
        var left: Int
        let time: Date
    }

    struct RejectedPick {
        let word: String
        let time: Date
    }

    /// 点了候选后马上退格：删完整个词（中间没打别的、没挪光标）就当是点错了。
    /// librime 选一次就把词提到第一（点错「触达」后，再打 chu da 首选就成了「触达」），记下来等它再出现时忘掉。
    func notePickDeleted() {
        guard var pick = recentPick else { return }
        pick.left -= 1
        guard pick.left <= 0 else {
            recentPick = pick
            return
        }
        recentPick = nil
        if Date().timeIntervalSince(pick.time) < 20 {
            rejectedPick = RejectedPick(word: pick.word, time: Date())
        }
    }

    /// 点错删掉的词又排到了第一：删掉学到的记录，词库自带的词回到原来的位置（和长按候选「删除」一样）。
    /// 两分钟内没再打出来就算了。
    private func forgetRejectedPick() {
        guard let rejected = rejectedPick, QueuedEngine.shared.pending == 0 else { return }
        guard Date().timeIntervalSince(rejected.time) < 120 else {
            rejectedPick = nil
            return
        }
        guard candidates.first == rejected.word, !commonWordTexts.contains(rejected.word) else { return }
        rejectedPick = nil
        deleteLearnedCandidate(0)
    }

    // MARK: - 候选长按（CL1–CL4）

    struct CandidateMenu: Equatable {
        enum Action { case delete, pin, removeCommon }
        let index: Int
        let word: String
        /// 被按的词在候选栏里的中心横坐标（候选栏左边算 0），气泡的尖角对准它。
        let midX: CGFloat
        let actions: [Action]
    }

    /// 长按候选 0.45 秒：按词的来源给不同项。常用词只有「从常用词移除」（系统文本替换、通讯录来的改不了，不弹）；
    /// 拼音候选「删除 | 置顶」；英文候选没有置顶，也没有学到的词可删，不弹。
    func showCandidateMenu(index: Int, midX: CGFloat) {
        guard isComposing, chineseMode, candidates.indices.contains(index) else { return }
        let word = candidates[index]
        let actions: [CandidateMenu.Action]
        if commonWordTexts.contains(word) {
            guard CommonWordStore.load().contains(where: { $0.text == word }) else { return }
            actions = [.removeCommon]
        } else {
            actions = CommonWordStore.containsHanzi(word) ? [.delete, .pin] : [.delete]
        }
        keyFeedback(for: .space)
        candidateMenu = CandidateMenu(index: index, word: word, midX: midX, actions: actions)
    }

    func performCandidateMenu(_ action: CandidateMenu.Action) {
        guard let menu = candidateMenu else { return }
        candidateMenu = nil
        keyFeedback(for: .space)
        switch action {
        case .delete:
            // 马上删，再取一遍候选：词还在说明是词库自带的，只是降回了原位（CL4 改提示）。
            closeCandidateUndo()
            applyEngineResults(wait: true)
            let raw = engine.rawInput
            guard let index = engine.candidates.firstIndex(of: menu.word), deleteLearnedCandidate(index) else { return }
            candidateUndo = CandidateUndo(word: menu.word, raw: raw, restored: engine.candidates.contains(menu.word))
            let timer = DispatchWorkItem { [weak self] in self?.closeCandidateUndo() }
            candidateUndoTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
        case .pin:
            // 加进常用词（排在候选最前），不弹提示，候选顺序马上变。
            let pinyin = CommonWordStore.pinyin(of: menu.word)
            guard !pinyin.isEmpty else { return }
            var words = CommonWordStore.load()
            if !words.contains(where: { $0.text == menu.word }) {
                words.append(CommonWord(text: menu.word, pinyin: pinyin))
                CommonWordStore.save(words)
            }
            refreshCandidatesAfterPhraseChange()
        case .removeCommon:
            CommonWordStore.save(CommonWordStore.load().filter { $0.text != menu.word })
            refreshCandidatesAfterPhraseChange()
        }
    }

    func dismissCandidateMenu() {
        if candidateMenu != nil { candidateMenu = nil }
    }

    struct CandidateUndo: Equatable {
        let word: String
        /// 删的时候的原始输入，撤销时按它把拼写恢复回来。
        let raw: String
        /// 删完词还在：词库自带的词，只是降回了默认位置。
        let restored: Bool
    }

    /// 撤销条上的「撤销」：librime 没有「加回用户词」的接口，就在引擎里把这个词选一次让它重新学到（不上屏），
    /// 再把拼写原样输回去。删完已经打不出这个词时没法撤销，只关掉撤销条。
    func undoCandidateDelete() {
        guard let undo = candidateUndo else { return }
        closeCandidateUndo()
        keyFeedback(for: .space)
        applyEngineResults(wait: true)
        guard engine.rawInput == undo.raw, let index = engine.candidates.firstIndex(of: undo.word) else { return }
        let kept = engine.selections
        _ = engine.select(index)
        engine.replaceInput(undo.raw, keeping: kept)
        syncEngine()
    }

    /// 撤销条到时间或继续打字时关掉。
    func closeCandidateUndo() {
        candidateUndoTimer?.cancel()
        candidateUndoTimer = nil
        if candidateUndo != nil { candidateUndo = nil }
    }

    /// 常用词短语表重写后引擎会重建会话，拼了一半的字母要原样再输一遍。
    private func refreshCandidatesAfterPhraseChange() {
        applyEngineResults(wait: true)
        let raw = engine.rawInput
        let kept = engine.selections
        reloadCommonWords()
        if !raw.isEmpty { engine.replaceInput(raw, keeping: kept) }
        syncEngine()
    }

    private func showPredictions(after text: String) {
        predictions = Predictor.next(after: text)
        if !predictions.isEmpty { DailyStats.add("prediction.shown") }
    }

    /// 候选栏里有联想时显示候选栏（没在打拼音）。
    var showsPredictions: Bool { !predictions.isEmpty && !isComposing }

    /// 点了联想词：上屏，再接着联想它后面的词。
    func selectPrediction(_ index: Int) {
        guard predictions.indices.contains(index) else { return }
        if !chineseMode { return selectEnglishSuggestion(index) }
        let word = predictions[index]
        commit(word)
        // 点联想词省掉的字数（首页「联想帮你少打了 N 个字」）。
        DailyStats.add("prediction.tapped")
        DailyStats.add("prediction.chars", word.count)
        showPredictions(after: word)
    }

    func dismissPredictions() {
        if !predictions.isEmpty { predictions = [] }
    }

    // MARK: - 按键触摸（由 KeyTouchView 调用）

    var layoutState: KeyLayout.State {
        KeyLayout.State(layer: layer, nineKey: showsNineKey, chineseMode: chineseMode, needsGlobeKey: needsGlobeKey,
                        englishOnly: settings.inputLanguage == .englishOnly,
                        composing: isComposing, digitsMore: digitsMore)
    }

    func perform(_ kind: KeyKind) {
        dismissCandidateMenu()
        closeCandidateUndo()
        // 英文的补全和联想每按一个键重新算（删除照常删字，空格照常打空格）。
        if !chineseMode {
            learnCurrentEnglishWord(before: kind)
            performKey(kind)
            // 切回中文时英文的候选不留。
            if chineseMode { dismissPredictions() } else { updateEnglishSuggestions() }
            return
        }
        if showsPredictions {
            switch kind {
            // 有联想时：删除只收起联想，不删字；开了「空格连续联想」时空格上屏第一个联想词。
            case .delete:
                dismissPredictions()
                return
            case .space where Predictor.spaceChains:
                selectPrediction(0)
                return
            default: break
            }
        }
        // 按了别的键：联想收起（打字母时候选栏换成拼音候选）。
        dismissPredictions()
        performKey(kind)
        if !chineseMode { updateEnglishSuggestions() }
    }

    private func performKey(_ kind: KeyKind) {
        switch kind {
        case .letter(let letter): typeLetter(letter)
        case .symbol(let symbol): typeSymbol(symbol)
        case .nine(let key): typeNineKey(key)
        case .shift: shiftKey()
        case .delete: deleteKey()
        case .space: spaceKey()
        case .returnKey: returnKey()
        case .toggleChinese: toggleChinese()
        // 打字时左列 123 / #@¥ 还在：先把拼音原样上屏（同「确认」），再切过去。
        case .layer(let layer):
            if isComposing { returnKey() }
            switchLayer(layer)
        case .digitPunct: typeSymbol(".")
        case .digitsMore: digitsMore.toggle()
        case .emoticon: isComposing ? clearComposition() : openPanel(.kaomoji)
        case .emoji: openPanel(.emoji)
        // 「常用」打字时也在：先把拼音原样上屏，再打开。
        case .quickWords:
            if isComposing { returnKey() }
            openPanel(.quickWords)
        case .globe: break
        }
    }

    func keyPressed(_ key: KeySpec, feedback: Bool = true) {
        // 开始打字就把提示卡收起来。
        if gate != nil { dismissGate() }
        // 开始打字，小手指引导就结束。
        endCoach()
        hideEmptyTapHint()
        pressedKeys.insert(key.id)
        if feedback { keyFeedback(for: key.kind) }
    }

    func keyReleased(_ id: String) {
        pressedKeys.remove(id)
        // 自己打的字系统不一定发 textDidChange，松手时顺便更新发送键。
        refreshHostState()
    }

    func refreshHostState() {
        let hasText = proxy?.hasText ?? false
        var returnKey = proxy?.returnKeyType ?? .default
        #if DEBUG
        // 截图用：-keyboardDebug send 假装对方是发送键。
        if KeyboardDebug.options.contains("send") { returnKey = .send }
        #endif
        if hasText != hostHasText { hostHasText = hasText }
        if returnKey != hostReturnKey { hostReturnKey = returnKey }
        let keyboardType = proxy?.keyboardType ?? .default
        if keyboardType != hostKeyboardType {
            hostKeyboardType = keyboardType
            applyLayer(for: keyboardType)
        }
    }

    /// 数字、电话、金额输入框直接出数字键盘；数字和标点框出数字符号页；其他输入框回到字母（正在组字时不动）。
    private func applyLayer(for keyboardType: UIKeyboardType) {
        guard target == .host, !isComposing else { return }
        switch keyboardType {
        case .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad:
            if layer != .digits { switchLayer(.digits) }
        case .numbersAndPunctuation:
            if layer != .numbers { switchLayer(.numbers) }
        default:
            if layer == .digits || layer == .numbers || layer == .symbols { switchLayer(.letters) }
        }
    }

    /// 按下时的震动和声音，声音和系统键盘一样分字符、删除、功能键三种。
    func keyFeedback(for kind: KeyKind) {
        if settings.keyHaptics && hasFullAccess {
            haptic.impactOccurred()
            haptic.prepare()
        }
        if settings.keySound {
            let sound: SystemSoundID
            switch kind {
            case .letter, .symbol, .nine, .digitPunct, .space: sound = 1104
            case .delete: sound = 1155
            default: sound = 1156
            }
            AudioServicesPlaySystemSound(sound)
        }
    }

    func setTrackpad(_ active: Bool) {
        if !active { flushCursorMove() }
        trackpadActive = active
        if active { keyFeedback(for: .space) }
        // 拖的时候对方输入框的通知都跳过了（见 KeyboardViewController），松手补一次。
        if !active {
            recordHostCaret()
            fieldDidChange()
            if !chineseMode { updateEnglishSuggestions() }
        }
    }

    /// 触控板拖动：同一帧里的几次移动并成一次 adjustTextPosition。每次调用都要和对方 App 来回一趟，
    /// 手指一动就调、再加上每次调完对方发回来的通知都去读输入框，拖起来一顿一顿的。
    func queueCursorMove(_ offset: Int) {
        pendingCursorMove += offset
        guard !cursorFlushScheduled else { return }
        cursorFlushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushCursorMove() }
    }

    func flushCursorMove() {
        cursorFlushScheduled = false
        let offset = pendingCursorMove
        pendingCursorMove = 0
        if offset != 0 { moveCursor(by: offset) }
    }

    func moveCursor(by offset: Int) {
        recentPick = nil
        recentCorrection = nil
        switch target {
        case .host: editProxy?.adjustTextPosition(byCharacterOffset: offset)
        case .card: moveCardCaret(by: offset)
        case .instruction: moveInstructionCaret(by: offset)
        }
    }

    func shiftKey() {
        let now = Date()
        switch shift {
        case .off: shift = .on
        case .on: shift = now.timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .off
        case .locked: shift = .off
        }
        lastShiftTap = now
    }

    func toggleChinese() {
        // 只用英文时没有中文；九宫格布局菜单之类的入口也不切过去。
        if !chineseMode && settings.inputLanguage == .englishOnly { return }
        if isComposing, let raw = engine.commitComposition() { commit(raw) }
        engine.reset()
        chineseMode.toggle()
        // 九宫格数字键盘上切英文：回到英文字母。
        if layer == .digits { switchLayer(.letters) }
        selectEngine()
        if chineseMode { shift = .off } else { updateAutoShift() }
    }

    /// 键盘弹出时按「主要语言」定中英：英文为主、只用英文每次都从英文开始；
    /// 中文保持上次的状态，只在刚从英文设置改回中文时切回中文。
    func applyInputLanguage() {
        let language = settings.inputLanguage
        defer { appliedLanguage = language }
        switch language {
        case .englishFirst, .englishOnly:
            if chineseMode { toggleChinese() }
        case .chinese:
            if appliedLanguage != nil, appliedLanguage != .chinese, !chineseMode { toggleChinese() }
        }
    }

    /// 九宫格只用于中文拼音；英文模式和拼音不可用时用全键盘。
    var activeLayout: KeyboardLayout {
        chineseMode ? settings.keyboardLayout : .qwerty
    }

    var showsNineKey: Bool { activeLayout == .nineKey && pinyinReady }

    func setLayout(_ layout: KeyboardLayout) {
        updateSettings { $0.keyboardLayout = layout }
        selectEngine()
    }

    /// 九宫格的数字键和分词键，直接交给拼音引擎。
    /// 没在打拼音时，分词键是标点键：连按在「，。？！」之间切换，和老式九宫格一样。
    func typeNineKey(_ key: String) {
        if key == "'" && !isComposing {
            cyclePunctuation()
            return
        }
        feedEngine(key)
    }

    private static let cycledMarks = ["，", "。", "？", "！"]

    private func cyclePunctuation() {
        let now = Date()
        let marks = Self.cycledMarks
        if target == .host, now.timeIntervalSince(lastPunctuationTap) < 0.8,
           let last = proxy?.documentContextBeforeInput?.last.map(String.init),
           let index = marks.firstIndex(of: last) {
            editProxy?.deleteBackward()
            commit(marks[(index + 1) % marks.count])
        } else {
            commit(marks[0])
        }
        lastPunctuationTap = now
    }

    // MARK: - 面板

    func openPanel(_ panel: KeysPanel) {
        candidatesExpanded = false
        keysPanel = panel
    }

    func closePanel() {
        keysPanel = nil
    }

    /// 表情、颜文字面板里点了一个：直接上屏，记进最近使用。
    func pickFromPanel(_ text: String) {
        typeSymbol(text)
        if keysPanel == .emoji { RecentEmoji.add(text) }
    }

    /// 「常用」面板里的词句：App 里的键盘常用语，按用户排的顺序。
    var quickWords: [String] {
        CommonWordStore.keyboardTexts
    }

    /// 「常用」面板里点了一个：上屏，回到九宫格。
    func pickQuickWord(_ text: String) {
        typeSymbol(text)
        closePanel()
    }

    // MARK: - 选拼音

    /// 九宫格原始输入拆成三段：分段选过词的部分（原样留着），之后到最后一个字母为止是已经选定的拼音，
    /// 后面是还没定的数字（可能带分词符）。拼音栏接着选的是最后一段。原始输入只有数字、字母和分词符，一个字符一个字节。
    private var pinyinSplit: (selected: String, fixed: String, rest: Substring) {
        let raw = engine.rawInput
        let end = min(engine.selections.last?.end ?? 0, raw.count)
        let open = raw.dropFirst(end).drop { $0 == "'" }
        let selected = String(raw.prefix(end))
        guard let lastLetter = open.lastIndex(where: \.isLetter) else { return (selected, "", open) }
        let rest = open[open.index(after: lastLetter)...].drop { $0 == "'" }
        return (selected, String(open[...lastLetter]), rest)
    }

    /// 第一个还没定的字的读法，长的在前；最后是这个数字键上的单个字母。首选候选的读法排第一（94664 的「中」：zhong 在 xiong 前面）。
    var pinyinOptions: [String] {
        guard showsNineKey, isComposing else { return [] }
        let split = pinyinSplit
        var options = PinyinSyllables.options(forDigits: String(split.rest.prefix(while: \.isNumber)))
        if let top = firstOpenSyllable(fixed: split.fixed), let index = options.firstIndex(of: top), index > 0 {
            options.insert(options.remove(at: index), at: 0)
        }
        return options
    }

    /// 全键盘：正在拼的拼音有几种切法时并列（xi'an、xian），现在这种在前；只有一种就只显示这一种。
    /// 分段选过词（拼写栏开头是汉字）时不列，免得重输把选过的词冲掉。
    var pinyinSegmentations: [String] {
        guard !showsNineKey, isComposing, composition.allSatisfy(\.isASCII) else { return [] }
        let letters = engine.rawInput.filter(\.isLetter).lowercased()
        let current = composition.split(whereSeparator: { $0 == " " || $0 == "'" }).joined(separator: "'").lowercased()
        guard !letters.isEmpty, letters.count <= 16 else { return current.isEmpty ? [] : [current] }
        var options = PinyinSyllables.segmentations(letters)
        guard !options.isEmpty else { return current.isEmpty ? [] : [current] }
        if let index = options.firstIndex(of: current) { options.insert(options.remove(at: index), at: 0) }
        return options
    }

    /// 全键盘点了一种切法：按这种切法重输。
    func chooseSegmentation(_ segmentation: String) {
        applyEngineResults(wait: true)
        engine.replaceInput(segmentation, keeping: [])
        syncEngine()
    }

    /// 首选候选在第一个没定的字上的读法：拼写栏是首选的拼音（「你好ma」「mi hao」），去掉前面选过的词和已经定下的音节。
    private func firstOpenSyllable(fixed: String) -> String? {
        let spelling = composition.drop { !$0.isASCII }
        let syllables = spelling.split(whereSeparator: { $0 == " " || $0 == "'" })
        let fixedCount = fixed.isEmpty ? 0 : fixed.split(separator: "'").count
        guard syllables.count > fixedCount else { return nil }
        let syllable = String(syllables[fixedCount])
        return syllable.allSatisfy(\.isLetter) ? syllable.lowercased() : nil
    }

    /// 分段选过、还没上屏的词（拼音栏顶上显示）。
    var selectedWords: String {
        guard showsNineKey, isComposing else { return "" }
        return engine.selections.map(\.text).joined()
    }

    /// 选定一个音节：把对应的数字换成字母交回引擎，后面的数字接着拼；分段选过的词重输后选回来。
    func choosePinyin(_ syllable: String) {
        // 拼音栏按的是已经算完的输入，后面还排着的数字先算完再拆。
        applyEngineResults(wait: true)
        let kept = engine.selections
        let (selected, fixed, rest) = pinyinSplit
        var open = fixed.isEmpty ? syllable : fixed + "'" + syllable
        let remaining = rest.dropFirst(syllable.count)
        if !remaining.isEmpty { open += (remaining.hasPrefix("'") ? "" : "'") + remaining }
        let raw = selected.isEmpty || selected.hasSuffix("'") ? selected + open : selected + "'" + open
        let before = choiceState
        engine.replaceInput(raw, keeping: kept)
        syncEngine()
        recordChoice(from: before)
    }

    // MARK: - 退格撤回上一步

    /// 九宫格组字时的一个状态：原始输入和分段选过的词。
    struct ChoiceState: Equatable {
        var raw: String
        var selections: [InputSelection]
    }

    /// 选了一次拼音或分段选了一个词：选之前、选之后的状态。
    struct ChoiceStep {
        var before: ChoiceState
        var after: ChoiceState
    }

    /// 九宫格组字时现在的状态；不是九宫格或没在组字时为 nil。
    private var choiceState: ChoiceState? {
        guard showsNineKey, isComposing else { return nil }
        applyEngineResults(wait: true)
        return ChoiceState(raw: engine.rawInput, selections: engine.selections)
    }

    /// 选完还在组字（选的是拼音或词的一段）就记一步；上屏了就清空。
    private func recordChoice(from before: ChoiceState?) {
        guard let before, let after = choiceState, after != before else {
            if !isComposing { choiceSteps = [] }
            return
        }
        choiceSteps.append(ChoiceStep(before: before, after: after))
    }

    /// 退格和别的输入法一样分情况：刚选了词就取消这个词，刚选了拼音就退回数字，之后又打了键就先删键。
    /// 状态正好停在最后一步选完的样子才撤回；之后打了键，先照常删键，删回那个样子再撤回。
    /// Rime 自己的退格在分段选词后又打过键时会直接删掉前面的数字，不会取消选词，所以撤回由这里按记下的状态重输。
    private func undoLastChoice() -> Bool {
        // 还有键排着没算完：最后一步是打键，照常删键。
        guard QueuedEngine.shared.pending == 0 else { return false }
        guard let current = choiceState else {
            choiceSteps = []
            return false
        }
        // 已经删到这一步之前（或者 Rime 自己取消了选词）的步子不用再撤。
        while let last = choiceSteps.last,
              !(current.raw.hasPrefix(last.after.raw) && current.selections.starts(with: last.after.selections)) {
            choiceSteps.removeLast()
        }
        guard let last = choiceSteps.last, last.after == current else { return false }
        choiceSteps.removeLast()
        engine.replaceInput(last.before.raw, keeping: last.before.selections)
        syncEngine()
        return true
    }

    /// 拼音栏顶上点已选的词：取消最后选的那个词（选过的拼音留着）。
    func unselectLastWord() {
        applyEngineResults(wait: true)
        let selections = engine.selections
        guard !selections.isEmpty else { return }
        engine.replaceInput(engine.rawInput, keeping: Array(selections.dropLast()))
        syncEngine()
    }

    // MARK: - 长按备选

    func showAlternates(for key: KeySpec, containerWidth: CGFloat, origin: CGPoint? = nil) -> Bool {
        if let options = KeyLayout.cross(for: key.kind, chinese: chineseMode) {
            cross = CrossPopup(key: key, options: options, containerWidth: containerWidth, origin: origin)
            keyFeedback(for: .space)
            return true
        }
        guard let options = KeyLayout.alternates(for: key.kind, chinese: chineseMode) else { return false }
        let shown = shift == .off ? options : options.map { $0.uppercased() }
        alternates = AlternatesPopup(key: key, options: shown, containerWidth: containerWidth)
        keyFeedback(for: .space)
        return true
    }

    /// 长按「中/英」：弹出拼音布局菜单，先选中当前的布局。
    func showLayoutMenu(for key: KeySpec, containerWidth: CGFloat) {
        layoutMenu = LayoutMenuPopup(key: key, containerWidth: containerWidth, selected: settings.keyboardLayout)
        keyFeedback(for: .space)
    }

    func moveAlternates(to point: CGPoint) {
        if var menu = layoutMenu {
            let option = menu.option(at: point)
            if option != menu.selected {
                menu.selected = option
                layoutMenu = menu
                if option != nil { keyFeedback(for: .space) }
            }
            return
        }
        if var popup = cross {
            let direction = popup.direction(at: point)
            if direction != popup.selected {
                popup.selected = direction
                cross = popup
            }
            return
        }
        let x = point.x
        guard var popup = alternates else { return }
        let index = popup.index(atX: x)
        if index != popup.selected {
            popup.selected = index
            alternates = popup
        }
    }

    /// 松手：十字滑回中间算取消。
    func commitAlternate() {
        if let menu = layoutMenu {
            layoutMenu = nil
            // 布局存在键盘这边，开了完全访问时和 App 里的设置是同一份，以最后一次改的为准。
            if let layout = menu.selected, layout != settings.keyboardLayout {
                if !chineseMode { toggleChinese() }
                setLayout(layout)
            }
            return
        }
        let text: String
        if let popup = cross {
            cross = nil
            guard let direction = popup.selected, let option = popup.options[direction] else { return }
            text = option.allSatisfy(\.isLetter) ? option.lowercased() : option
        } else if let popup = alternates {
            alternates = nil
            text = popup.options[popup.selected]
        } else {
            return
        }
        // 九宫格中文下划出来的字母也是拼音：在拼就接着拼（把这一位定成这个字母），没在拼就从它开始拼，
        // 不然空输入框里划一个字母会直接上屏成英文。
        if showsNineKey && layer == .letters && (isComposing || chineseMode) && text.allSatisfy(\.isLetter) {
            feedEngine(text.lowercased())
        } else {
            typeSymbol(text)
        }
        if shift == .on { shift = .off }
    }

    #if DEBUG
    /// 模拟器测内存（debug 选项 memtest）：打一组整句，记下首选、耗时和内存，
    /// 结果写到共享目录 Library/Diagnostics/memtest-gram.json（有整句模型）或 memtest-plain.json。
    func runMemoryTest() {
        let sentences = [
            "woxiangqugongsishangban", "jintiantianqizhenhao", "womenyiqiquchifanba", "zhegewentiwomenmingtianzaitaolun",
            "tazuotianwanshangmeiyouhuijia", "qingbangwochayixiahuochepiao", "zhejianshiqingbiwoxiangdeyaofuza",
            "nikanjianwodeshoujilema", "xiawusandianzaihuiyishikaihui", "zhegexiangmudejindubijiaoman",
        ]
        let engine = QueuedEngine.shared
        guard self.engine === engine else { return }
        var report: [String: Any] = ["model": TypingStats.modelInUse, "startMB": TypingStats.footprintMB() ?? -1]
        var results: [[String: Any]] = []
        var peak = 0.0
        for sentence in sentences {
            engine.reset()
            let start = CACurrentMediaTime()
            for letter in sentence { _ = engine.input(String(letter)) }
            let memory = TypingStats.footprintMB() ?? -1
            peak = max(peak, memory)
            results.append(["input": sentence, "first": engine.candidates.first ?? "",
                            "ms": (CACurrentMediaTime() - start) * 1000, "mb": memory])
        }
        engine.reset()
        report["sentences"] = results
        report["peakMB"] = peak
        report["afterTypingMB"] = TypingStats.footprintMB() ?? -1
        syncEngine()
        guard let group = SharedStorage.appGroupID.flatMap({ FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        let out = group.appendingPathComponent("Library/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? data.write(to: out.appendingPathComponent(TypingStats.modelInUse ? "memtest-gram.json" : "memtest-plain.json"))
    }
    #endif

    /// 系统内存警告：记下次数，放掉眼下用不上的那份联想表（各几 MB），少被系统杀掉，下次弹出就少一次冷启动。
    /// 不关 Rime 引擎：试过，实测只省 0.2–0.4MB（词典和整句模型是文件映射，本来就不算进占用），还要丢掉正在拼的内容。
    func noteMemoryWarning() {
        TypingStats.noteMemoryWarning()
        if chineseMode { EnglishPredictor.unload() } else { Predictor.unload() }
    }

    /// 动态热区用的拼音上下文：中文全键盘字母页、拼音引擎在用、没按 Shift 时才有。
    var pinyinContextForTouch: String? {
        guard chineseMode, layer == .letters, shift == .off, engine === QueuedEngine.shared else { return nil }
        return QueuedEngine.shared.expectedRawInput
    }

    /// 九宫格「重输」：清掉正在拼的内容。
    func clearComposition() {
        engine.reset()
        syncEngine()
    }

    /// 中文模式用拼音引擎，英文模式或词库不可用时字母直接上屏。
    /// 启动 Rime、切方案在后台做，键盘不等它就弹出来：有词库就先当作能用，按键排在引擎准备好之后。
    func selectEngine() {
        engine.reset()
        let queued = QueuedEngine.shared
        let useShared = hasFullAccess
        pinyinReady = RimeEngine.hasDictionary(useShared: useShared)
        TypingStats.modelInUse = useShared && RimeStore.isDeployed
            && (RimeStore.deployedVersion?.hasSuffix(GrammarModel.versionTag(installed: true)) ?? false)
        engine = chineseMode && pinyinReady ? queued : DirectEngine()
        syncEngine()
        queued.prepare(schema: RimeStore.schema(for: activeLayout), useShared: useShared) { [weak self] ok, source in
            #if DEBUG
            KeyboardProbe.run(fullAccess: useShared, pinyinReady: ok, source: source)
            #endif
            // 联想数据等拼音引擎启动完再读：冷启动时两边一起读词库，抢 CPU 和磁盘，键盘出来得慢。
            if ok {
                TypingStats.noteLaunchEngineReady()
                Predictor.prepare()
            }
            guard let self, !ok, self.pinyinReady else { return }
            // 词库其实读不出来：退回直接打字母。
            self.pinyinReady = false
            if self.engine === queued {
                self.engine.reset()
                self.engine = DirectEngine()
                self.syncEngine()
            }
        }
    }

    func switchLayer(_ layer: KeyLayer) {
        self.layer = layer
        if digitsMore { digitsMore = false }
    }

    // MARK: - AI 面板

    /// ✨：展开时照常生成到卡片里；收起时是快速模式，润完直接替换输入框，撤销能退回原文。
    func sparkleTapped() {
        // 快速模式、输入框里没字：不展开回答卡、不调接口、不计次数，也不先弹提示卡；按钮晃一下、右边提示「未检测到内容」（NC1）。
        if !aiExpanded, target == .host, !isComposing, !isRunning, fieldIsBlank {
            showEmptyTapHint()
            return
        }
        guard passGate(then: { [weak self] in self?.sparkleTapped() }) else { return }
        #if DEBUG
        if debugFakeRun { coachTapped(.sparkle); fakeCoachRun(); return }
        #endif
        coachTapped(.sparkle)
        if target == .card { finishCardEdit() }
        guard !aiExpanded else {
            start(from: .polish) { execute() }
            return
        }
        finishComposition()
        hideEmptyTapHint()
        beginQuickMode(source: readField().text)
        start(from: .polish) { execute() }
        // 没开始生成（空输入框提示、没配置、没开完全访问）就展开，把原因显示出来。
        if !isRunning {
            quickSource = nil
            clearQuickStatus()
            setAIExpanded(true)
        }
    }

    func setAIExpanded(_ expanded: Bool) {
        guard expanded != aiExpanded else { return }
        // 收起就看不到卡片了，改到一半的先存下来。
        if target == .card { finishCardEdit() }
        finishComposition()
        if expanded { clearQuickStatus(); hideEmptyTapHint() }
        aiExpanded = expanded
    }

    /// 把正在拼的字母原样上屏，然后清空引擎。
    func finishComposition() {
        if isComposing, let raw = engine.commitComposition() { commit(raw) }
        engine.reset()
        syncEngine()
    }

    // MARK: - 内部

    func commit(_ text: String) {
        // 上屏了别的字，之前点的候选、纠正的词就不是「点了马上删」了。
        recentPick = nil
        recentCorrection = nil
        switch target {
        case .host:
            // 有组字时把标记区直接换成要上屏的字再 unmark，不 insertText：
            // 闲鱼等 Flutter 输入框里，insertText 和空的 setMarkedText 都不会替换标记区，拼音会当正文留下（「hao de好的」）；
            // 非空的 setMarkedText 各家都会老实替换（打拼音时一直靠它更新），unmark 后就是正文。
            if hasMarkedText, !text.isEmpty {
                editProxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
                editProxy?.unmarkText()
                hasMarkedText = false
            } else {
                clearMarkedText()
                editProxy?.insertText(text)
            }
            updateAutoShift()
        case .instruction:
            insertInInstruction(text)
        case .card:
            insertInCard(text)
        }
    }

    func syncEngine() {
        if !isComposing && !choiceSteps.isEmpty { choiceSteps = [] }
        // 没变的不设：@Published 设一次就让整个键盘重画一遍。
        let newComposition = engine.composition
        if newComposition != composition { composition = newComposition }
        let row = layer == .letters && !composition.isEmpty
        if row != pinyinRowShown { pinyinRowShown = row }
        let newCandidates = engine.candidates
        let candidatesChanged = newCandidates != candidates
        if candidatesChanged { candidates = newCandidates }
        if candidates.isEmpty && candidatesExpanded { candidatesExpanded = false }
        // 拼音像系统输入法一样带下划线显示在输入框里；打进要求框时不显示。
        if target == .host && isComposing {
            editProxy?.setMarkedText(composition, selectedRange: NSRange(location: (composition as NSString).length, length: 0))
            hasMarkedText = true
        } else {
            clearMarkedText()
        }
        if candidatesChanged { forgetRejectedPick() }
    }

    func clearMarkedText() {
        guard hasMarkedText else { return }
        editProxy?.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        editProxy?.unmarkText()
        hasMarkedText = false
    }

    /// 英文模式在句首自动大写，和系统一样；设置里关掉时不动 shift。
    func updateAutoShift() {
        guard settings.autoCapitalize, !chineseMode, target == .host, layer == .letters, shift != .locked else { return }
        let before = proxy?.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let sentenceStart = trimmed.isEmpty || before.hasSuffix("\n")
            || (before.hasSuffix(" ") && [".", "?", "!"].contains(trimmed.last.map(String.init) ?? ""))
        let wanted: ShiftState = sentenceStart ? .on : .off
        // 没变就不设（同 syncEngine），英文打字时每个键都会走到这里。
        if shift != wanted { shift = wanted }
    }
}

// MARK: - 按键上的字

extension KeyboardModel {
    /// 空格键：中文写「空格」，英文写「space」，打拼音时是「选定」。
    var spaceTitle: String {
        if isComposing { return "选定" }
        // 词库没部署或没开完全访问时，中文模式也只能直接打字母。
        if chineseMode && !pinyinReady { return "空格（拼音未就绪）" }
        return chineseMode ? "空格" : "space"
    }

    /// 回车键的样子：换行和确认是浅紫底紫字；「执行」实心紫；发送类按输入框有没有字在浅紫和实心紫之间切。
    struct ReturnLook: Equatable {
        /// nil 画换行图标。
        var title: String?
        var solid: Bool
        var bold = false
    }

    var returnLook: ReturnLook {
        if isComposing { return ReturnLook(title: "确认", solid: false) }
        if target == .instruction { return ReturnLook(title: L("执行", "Go", "実行"), solid: true) }
        if target == .card { return ReturnLook(title: nil, solid: false) }
        if let title = sendTitle { return ReturnLook(title: title, solid: hostHasText, bold: true) }
        return ReturnLook(title: nil, solid: false)
    }

    /// 对方输入框的回车键是发送、搜索、前往这一类时的文字。
    private var sendTitle: String? {
        let titles: (String, String)
        switch hostReturnKey {
        case .send: titles = ("发送", "send")
        case .search, .google, .yahoo: titles = ("搜索", "search")
        case .go, .route: titles = ("前往", "go")
        case .join: titles = ("加入", "join")
        case .done: titles = ("完成", "done")
        case .next: titles = ("下一项", "next")
        case .continue: titles = ("继续", "continue")
        default: return nil
        }
        return chineseMode ? titles.0 : titles.1
    }
}

// MARK: - 模拟器截图用的调试状态

extension KeyboardModel {
    /// 读取主 App 写入的调试选项：expanded（展开面板）、nine / qwerty（布局）、
    /// numbers / symbols（数字、符号层）、english（英文模式）、compose:拼音（模拟正在打拼音）、
    /// instruction（输入要求）、candidates（展开候选）。
    func applyDebugState() {
        let options = KeyboardDebug.options
        guard !options.isEmpty else { return }
        for option in options {
            switch option {
            case "expanded": aiExpanded = true
            case "nine": if settings.keyboardLayout != .nineKey { setLayout(.nineKey) }
            case "qwerty": if settings.keyboardLayout != .qwerty { setLayout(.qwerty) }
            case "numbers": layer = .numbers
            case "symbols": layer = .symbols
            case "digits": layer = .digits
            case "digitsMore": layer = .digits; digitsMore = true
            case "english": if chineseMode { toggleChinese() }
            case "prompts": aiRow = .prompts
            case "instruction", "menu": aiExpanded = true
            case "answerStyles": aiExpanded = true; aiRow = .answerStyles
            case "cardExpanded": aiExpanded = true; cardExpanded = true
            #if DEBUG
            case "versions": aiExpanded = true; debugUnblocked = true; loadDebugVersions()
            // cardEdit：停在卡片修改中；cardEdited：已经存了一版「已改」。
            case "cardEdit": aiExpanded = true; debugUnblocked = true; loadDebugVersions(); beginCardEdit(caret: 8)
            case "cardEdited":
                aiExpanded = true; debugUnblocked = true; loadDebugVersions()
                beginCardEdit(); insertInCard("周五补上进度。"); finishCardEdit()
            case "running": aiExpanded = true; debugUnblocked = true; loadDebugRunning()
            case "ask", "askEmpty", "askSelected", "askRewrite", "askAnswerMode", "askAnswer", "askRewriteResult", "askRunning":
                loadDebugAsk(option)
            case "askHold": debugAskHold = true; askHoldShowing = true
            // 结果卡左边的键：key:insert 默认插入，key:down 滚轮下滑，key:pop 弹出；key:rolled / key:popped 停在换过去的样子。
            case "key:insert": debugResultKey(primary: .insert)
            case "key:down": debugResultKey(swipe: .wheel, wheelUp: false)
            case "key:pop": debugResultKey(swipe: .pop)
            case "key:rolled", "key:popped": debugResultKeyPose = String(option.dropFirst(4))
            // 截图用：替换后「只替换了读到的一段」、拉起 App 失败的提示，停住不消失。
            case "partialReplace": aiExpanded = true; debugUnblocked = true; loadDebugVersions(); debugShowNotes(partial: true)
            case "openAppFailed": debugShowNotes(partial: false)
            case "quotaUsed": debugShowGate(.quotaUsed)
            case "quick:running": loadDebugQuick(.running)
            case "quick:done": loadDebugQuick(.done)
            case "quick:failed": loadDebugQuick(.failed)
            case "quick:cycle": loadDebugQuickCycle()
            // 截图用：输入框空着时点 ✨ 的「未检测到内容」（NC1）；1 秒后点一次，再过 1 秒又点一次看重新计时。
            case "emptyTap":
                debugUnblocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sparkleTapped() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.sparkleTapped() }
            case "emoji": keysPanel = .emoji
            case "kaomoji": keysPanel = .kaomoji
            case "quickWords": keysPanel = .quickWords
            case "undo": loadDebugUndo()
            case "memtest": runMemoryTest()
            // 小手指引导：quick / quickrun 是快速模式（收起），其余展开。
            case "coach:quick": debugCoach([.sparkle], expanded: false, menuOpen: false)
            case "coach:quickrun": debugCoach([.run], expanded: false, menuOpen: true)
            case "coach:sparkle": debugCoach([.sparkle, .replace], expanded: true, menuOpen: false)
            case "coach:run": debugCoach([.run, .replace], expanded: true, menuOpen: true)
            case "coach:versions": debugCoach([.run, .versions, .replace], expanded: true, menuOpen: true)
            case "coach:proofread": debugCoach([.sparkle, .versions, .replace], expanded: true, menuOpen: false)
            case "coach:insert": debugCoach([.run, .insert], expanded: true, menuOpen: true)
            #endif
            default: break
            }
        }
        for option in options where option.hasPrefix("compose:") {
            engine.reset()
            for character in option.dropFirst("compose:".count) {
                if let output = engine.input(String(character)) { commit(output) }
            }
            syncEngine()
        }
        if options.contains("candidates") && !candidates.isEmpty { candidatesExpanded = true }
        #if DEBUG
        // cross:1:right 按住「,｡?!」往右滑；cross:3:up 按住 DEF 往上滑。
        for option in options where option.hasPrefix("cross:") {
            let parts = option.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { continue }
            let width = UIScreen.main.bounds.width - KeyboardMetrics.sidePadding * 2
            let layout = KeyLayout.build(layoutState, size: CGSize(width: width, height: KeyboardMetrics.keysHeight))
            guard let key = layout.keys.first(where: { $0.id == "n\(parts[1])" }),
                  showAlternates(for: key, containerWidth: width) else { continue }
            let directions: [String: CrossPopup.Direction] = ["left": .left, "up": .up, "right": .right, "down": .down]
            if parts.count > 2 { cross?.selected = directions[parts[2]] }
        }
        #endif
    }
}

// MARK: - 英文补全和联想

extension KeyboardModel {
    /// 光标前正在打的英文单词（字母和撇号）。
    private var currentEnglishWord: Substring {
        let before = proxy?.documentContextBeforeInput ?? ""
        return before.suffix { $0.isASCII && ($0.isLetter || $0 == "'") }
    }

    /// 英文状态下：正在打一个词时给补全；刚打完一个词加空格时给它后面常跟的词。
    func updateEnglishSuggestions() {
        guard !chineseMode, target == .host, layer == .letters, Predictor.englishEnabled,
              hostKeyboardType != .URL, hostKeyboardType != .emailAddress else {
            predictionReplaces = 0
            dismissPredictions()
            return
        }
        EnglishPredictor.prepare()
        let before = proxy?.documentContextBeforeInput ?? ""
        let word = before.suffix { $0.isASCII && ($0.isLetter || $0 == "'") }
        var words: [String] = []
        var replaces = 0
        if !word.isEmpty {
            words = EnglishPredictor.complete(String(word))
            replaces = word.count
        } else if before.hasSuffix(" ") {
            let previous = before.dropLast().suffix { $0.isASCII && ($0.isLetter || $0 == "'") }
            if !previous.isEmpty { words = EnglishPredictor.next(after: String(previous)) }
        }
        predictionReplaces = replaces
        if words != predictions { predictions = words }
    }

    /// 点了英文补全或联想：换掉正在打的半个词，补上空格，接着联想下一个词。
    func selectEnglishSuggestion(_ index: Int) {
        let word = predictions[index]
        for _ in 0..<predictionReplaces { editProxy?.deleteBackward() }
        commit(word + " ")
        EnglishPredictor.learn(word)
        DailyStats.add("prediction.tapped")
        DailyStats.add("prediction.chars", max(word.count - predictionReplaces, 0))
        predictionReplaces = 0
        updateEnglishSuggestions()
    }

    /// 打完一个词（按了空格、标点、换行）：记住这个词，下次补全排前面。
    func learnCurrentEnglishWord(before kind: KeyKind) {
        switch kind {
        case .space, .symbol, .returnKey: break
        default: return
        }
        guard target == .host else { return }
        let word = currentEnglishWord
        if word.count >= 2 { EnglishPredictor.learn(String(word)) }
    }
}

private extension StringProtocol {
    /// 末尾连续满足条件的那一段（标准库只有 prefix(while:)）。
    func suffix(while predicate: (Character) -> Bool) -> SubSequence {
        var start = endIndex
        while start > startIndex {
            let previous = index(before: start)
            guard predicate(self[previous]) else { break }
            start = previous
        }
        return self[start...]
    }
}
