import AudioToolbox
import UIKit

/// 打字：按键、组字、上屏，以及把文字送到聊天输入框还是要求框。
extension KeyboardModel {
    /// card：在结果卡片里直接改。
    enum InputTarget { case host, instruction, card }
    /// digits 是九宫格的数字键盘；numbers、symbols 是全键盘那样的数字符号页（九宫格的 #@¥ 也进这里）。
    enum KeyLayer { case letters, numbers, symbols, digits }
    enum ShiftState { case off, on, locked }

    var isComposing: Bool { !composition.isEmpty }
    /// 现在画的是五列的九宫格（拼音或数字），按下不出放大气泡。
    var nineGrid: Bool { showsNineKey && (layer == .letters || layer == .digits) }

    func typeLetter(_ letter: String) {
        let text = shift == .off ? letter : letter.uppercased()
        if shift == .on { shift = .off }
        // 大写字母不进拼音组字，直接上屏。
        if text != letter {
            commit(text)
            return
        }
        if let output = engine.input(text) { commit(output) }
        syncEngine()
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
        if let text = engine.select(index) { commit(text) }
        syncEngine()
    }

    // MARK: - 按键触摸（由 KeyTouchView 调用）

    var layoutState: KeyLayout.State {
        KeyLayout.State(layer: layer, nineKey: showsNineKey, chineseMode: chineseMode, needsGlobeKey: needsGlobeKey,
                        composing: isComposing, digitsMore: digitsMore)
    }

    func perform(_ kind: KeyKind) {
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
        case .pickPinyin: if isComposing && !pinyinOptions.isEmpty { openPanel(.pinyin) }
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
        if let output = engine.input(key) { commit(output) }
        syncEngine()
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
        let (fixed, rest) = pinyinSplit
        var raw = fixed.isEmpty ? syllable : fixed + "'" + syllable
        let remaining = rest.dropFirst(syllable.count)
        if !remaining.isEmpty { raw += (remaining.hasPrefix("'") ? "" : "'") + remaining }
        engine.replaceInput(raw)
        syncEngine()
        if keysPanel == .pinyin { keysPanel = nil }
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

    func moveAlternates(to point: CGPoint) {
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
            if let output = engine.input(text.lowercased()) { commit(output) }
            syncEngine()
        } else {
            typeSymbol(text)
        }
        if shift == .on { shift = .off }
    }

    /// 九宫格「重输」：清掉正在拼的内容。
    func clearComposition() {
        engine.reset()
        syncEngine()
    }

    /// 中文模式用拼音引擎，英文模式或词库不可用时字母直接上屏。
    func selectEngine() {
        engine.reset()
        pinyinReady = RimeEngine.shared.prepare(schema: RimeStore.schema(for: activeLayout), useShared: hasFullAccess)
        #if DEBUG
        KeyboardProbe.run(fullAccess: hasFullAccess, pinyinReady: pinyinReady, source: RimeEngine.shared.source)
        #endif
        engine = chineseMode && pinyinReady ? RimeEngine.shared : DirectEngine()
        syncEngine()
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
        if keysPanel == .pinyin && !isComposing { keysPanel = nil }
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
        if target == .instruction { return ReturnLook(title: "执行", solid: true) }
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
            case "undo": loadDebugUndo()
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
        if options.contains("pinyin") && isComposing { keysPanel = .pinyin }
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
