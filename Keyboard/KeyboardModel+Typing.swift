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
        if engine.backspace() {
            syncEngine()
            return
        }
        switch target {
        case .host:
            proxy?.deleteBackward()
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
            proxy?.deleteBackward()
            commit(chineseMode ? "。" : ". ")
            lastSpaceTime = .distantPast
        } else {
            commit(" ")
            lastSpaceTime = now
        }
        // 数字符号页打完空格回到字母；九宫格数字键盘和原生一样留着，方便接着打数字。
        if layer != .letters && layer != .digits { layer = .letters }
    }

    /// 组字时回车把字母原样上屏；在要求框里回车就是「执行」。
    func returnKey() {
        if isComposing {
            if let raw = engine.commitComposition() { commit(raw) }
            syncEngine()
            return
        }
        switch target {
        case .host: proxy?.insertText("\n")
        case .instruction:
            menuPolishTapped()
        case .card:
            commit("\n")
        }
    }

    func selectCandidate(_ index: Int) {
        // 选了候选：前面打的拼音键都没按错，算进手指习惯。
        TouchCalibration.confirm()
        let text = engine.select(index)
        if let text { commit(text) }
        syncEngine()
        if let text, !isComposing, chineseMode { showPredictions(after: text) }
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
                        composing: isComposing, digitsMore: digitsMore)
    }

    func perform(_ kind: KeyKind) {
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
        switch kind {
        case .letter(let letter): typeLetter(letter)
        case .symbol(let symbol): typeSymbol(symbol)
        case .nine(let key): typeNineKey(key)
        case .shift: shiftKey()
        case .delete: deleteKey()
        case .space: spaceKey()
        case .returnKey: returnKey()
        case .toggleChinese: toggleChinese()
        case .layer(let layer): switchLayer(layer)
        case .digitPunct: typeSymbol(".")
        case .digitsMore: digitsMore.toggle()
        case .emoticon: isComposing ? clearComposition() : openPanel(.kaomoji)
        case .emoji: openPanel(.emoji)
        // 「常用」只在没打拼音时露出来；万一打字时触发，不打开，免得丢掉没上屏的拼音。
        case .quickWords: if !isComposing { openPanel(.quickWords) }
        case .globe: break
        }
    }

    func keyPressed(_ key: KeySpec, feedback: Bool = true) {
        // 开始打字就把提示卡收起来。
        if gate != nil { dismissGate() }
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
        trackpadActive = active
        if active { keyFeedback(for: .space) }
    }

    func moveCursor(by offset: Int) {
        switch target {
        case .host: proxy?.adjustTextPosition(byCharacterOffset: offset)
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
        if isComposing, let raw = engine.commitComposition() { commit(raw) }
        engine.reset()
        chineseMode.toggle()
        // 九宫格数字键盘上切英文：回到英文字母。
        if layer == .digits { switchLayer(.letters) }
        selectEngine()
        if chineseMode { shift = .off } else { updateAutoShift() }
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
            proxy?.deleteBackward()
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

    /// 九宫格原始输入拆成两段：最后一个字母为止是已经选定的拼音，后面是还没定的数字（可能带分词符）。
    private var pinyinSplit: (fixed: String, rest: Substring) {
        let raw = engine.rawInput
        guard let lastLetter = raw.lastIndex(where: \.isLetter) else { return ("", Substring(raw)) }
        let rest = raw[raw.index(after: lastLetter)...].drop { $0 == "'" }
        return (String(raw[...lastLetter]), rest)
    }

    /// 第一段没定的数字可以拼成的音节，长的在前；最后是这个数字键上的单个字母。
    var pinyinOptions: [String] {
        guard showsNineKey, isComposing else { return [] }
        return PinyinSyllables.options(forDigits: String(pinyinSplit.rest.prefix(while: \.isNumber)))
    }

    /// 选定一个音节：把对应的数字换成字母交回引擎，后面的数字接着拼。
    func choosePinyin(_ syllable: String) {
        // 拼音栏按的是已经算完的输入，后面还排着的数字先算完再拆。
        applyEngineResults(wait: true)
        let (fixed, rest) = pinyinSplit
        var raw = fixed.isEmpty ? syllable : fixed + "'" + syllable
        let remaining = rest.dropFirst(syllable.count)
        if !remaining.isEmpty { raw += (remaining.hasPrefix("'") ? "" : "'") + remaining }
        engine.replaceInput(raw)
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

    /// 系统内存警告：只记下次数。试过关掉 Rime 引擎，实测只省 0.2–0.4MB（词典和整句模型是文件映射，本来就不算进占用），
    /// 还要丢掉正在拼的内容，不值得。
    func noteMemoryWarning() {
        TypingStats.noteMemoryWarning()
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
        guard passGate(then: { [weak self] in self?.sparkleTapped() }) else { return }
        if target == .card { finishCardEdit() }
        guard !aiExpanded else {
            start(from: .polish) { execute() }
            return
        }
        finishComposition()
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
        if expanded { clearQuickStatus() }
        aiExpanded = expanded
    }

    /// 点「正式▾」：打开或关上风格浮层（只有这里能收起）。打开时光标进要求框，回车键变「执行」；关上回到原输入框。
    func toggleStyleMenu() {
        if target == .card { finishCardEdit() }
        finishComposition()
        styleMenuOpen.toggle()
        target = styleMenuOpen ? .instruction : .host
    }

    /// 浮层里的「润色」：按选好的风格和要求开始改。浮层不收起，只有再点「正式▾」才收。
    /// 面板收起时是快速模式，润完直接替换输入框（AI 栏上流光）；展开时进结果卡片，等替换或插入。
    func menuPolishTapped() {
        guard passGate(then: { [weak self] in self?.menuPolishTapped() }) else { return }
        if target == .card { finishCardEdit() }
        finishComposition()
        guard !aiExpanded else {
            start(from: .rerun) { regenerate() }
            return
        }
        beginQuickMode(source: readField().text)
        start(from: .rerun) { regenerate() }
        if !isRunning {
            quickSource = nil
            clearQuickStatus()
            setAIExpanded(true)
        }
    }

    /// 点要求框：键盘的输入切到要求框，再点一下切回原输入框。
    func toggleInstructionEditing() {
        // 同一时间只有一处接收打字：正在改卡片就先保存，焦点给要求框。
        if target == .card { finishCardEdit() }
        finishComposition()
        target = target == .instruction ? .host : .instruction
    }

    /// 把正在拼的字母原样上屏，然后清空引擎。
    func finishComposition() {
        if isComposing, let raw = engine.commitComposition() { commit(raw) }
        engine.reset()
        syncEngine()
    }

    // MARK: - 内部

    func commit(_ text: String) {
        switch target {
        case .host:
            clearMarkedText()
            proxy?.insertText(text)
            updateAutoShift()
        case .instruction:
            insertInInstruction(text)
        case .card:
            insertInCard(text)
        }
    }

    func syncEngine() {
        composition = engine.composition
        candidates = engine.candidates
        if candidates.isEmpty { candidatesExpanded = false }
        // 拼音像系统输入法一样带下划线显示在输入框里；打进要求框时不显示。
        if target == .host && isComposing {
            proxy?.setMarkedText(composition, selectedRange: NSRange(location: (composition as NSString).length, length: 0))
            hasMarkedText = true
        } else {
            clearMarkedText()
        }
    }

    func clearMarkedText() {
        guard hasMarkedText else { return }
        proxy?.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        proxy?.unmarkText()
        hasMarkedText = false
    }

    /// 英文模式在句首自动大写，和系统一样。
    func updateAutoShift() {
        guard !chineseMode, target == .host, layer == .letters, shift != .locked else { return }
        let before = proxy?.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let sentenceStart = trimmed.isEmpty || before.hasSuffix("\n")
            || (before.hasSuffix(" ") && [".", "?", "!"].contains(trimmed.last.map(String.init) ?? ""))
        shift = sentenceStart ? .on : .off
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
            case "instruction", "menu": styleMenuOpen = true; target = .instruction
            case "cardExpanded": aiExpanded = true; cardExpanded = true
            #if DEBUG
            case "versions": aiExpanded = true; debugUnblocked = true; loadDebugVersions()
            // cardEdit：停在卡片修改中；cardEdited：已经存了一版「已改」。
            case "cardEdit": aiExpanded = true; debugUnblocked = true; loadDebugVersions(); beginCardEdit(caret: 8)
            case "cardEdited":
                aiExpanded = true; debugUnblocked = true; loadDebugVersions()
                beginCardEdit(); insertInCard("周五补上进度。"); finishCardEdit()
            case "running": aiExpanded = true; debugUnblocked = true; loadDebugRunning()
            case "quick:running": loadDebugQuick(.running)
            case "quick:done": loadDebugQuick(.done)
            case "quick:failed": loadDebugQuick(.failed)
            case "quick:cycle": loadDebugQuickCycle()
            case "rerun:running": loadDebugRerun(cycle: false)
            case "rerun:cycle": loadDebugRerun(cycle: true)
            case "emoji": keysPanel = .emoji
            case "kaomoji": keysPanel = .kaomoji
            case "quickWords": keysPanel = .quickWords
            case "undo": loadDebugUndo()
            case "memtest": runMemoryTest()
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
