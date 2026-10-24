import AudioToolbox
import UIKit

/// 打字：按键、组字、上屏，以及把文字送到聊天输入框还是要求框。
extension KeyboardModel {
    enum InputTarget { case host, instruction }
    enum KeyLayer { case letters, numbers, symbols }
    enum ShiftState { case off, on, locked }

    var isComposing: Bool { !composition.isEmpty }

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
            guard !instruction.isEmpty else { return }
            setInstruction(String(instruction.dropLast()))
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
        if layer != .letters { layer = .letters }
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
        }
    }

    func selectCandidate(_ index: Int) {
        if let text = engine.select(index) { commit(text) }
        syncEngine()
    }

    // MARK: - 按键触摸（由 KeyTouchView 调用）

    var layoutState: KeyLayout.State {
        KeyLayout.State(layer: layer, nineKey: showsNineKey, chineseMode: chineseMode, needsGlobeKey: needsGlobeKey,
                        composing: isComposing)
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
        case .emoticon: isComposing ? clearComposition() : openPanel(.kaomoji)
        case .emoji: openPanel(.emoji)
        case .pickPinyin: if isComposing && !pinyinOptions.isEmpty { openPanel(.pinyin) }
        case .globe: break
        }
    }

    func keyPressed(_ key: KeySpec, feedback: Bool = true) {
        pressedKeys.insert(key.id)
        if feedback { keyFeedback(for: key.kind) }
    }

    func keyReleased(_ id: String) {
        pressedKeys.remove(id)
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
            case .letter, .symbol, .nine, .space: sound = 1104
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
        guard target == .host else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
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

    func showAlternates(for key: KeySpec, containerWidth: CGFloat) -> Bool {
        guard let options = KeyLayout.alternates(for: key.kind, chinese: chineseMode) else { return false }
        let shown = shift == .off ? options : options.map { $0.uppercased() }
        alternates = AlternatesPopup(key: key, options: shown, containerWidth: containerWidth)
        keyFeedback(for: .space)
        return true
    }

    func moveAlternates(toX x: CGFloat) {
        guard var popup = alternates else { return }
        let index = popup.index(atX: x)
        if index != popup.selected {
            popup.selected = index
            alternates = popup
        }
    }

    func commitAlternate() {
        guard let popup = alternates else { return }
        alternates = nil
        let text = popup.options[popup.selected]
        // 九宫格打拼音时长按选的字母接着拼，相当于把这一位定成这个字母。
        if showsNineKey && layer == .letters && isComposing && text.allSatisfy(\.isLetter) {
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
        pinyinReady = hasFullAccess && RimeEngine.shared.prepare(schema: RimeStore.schema(for: activeLayout))
        engine = chineseMode && pinyinReady ? RimeEngine.shared : DirectEngine()
        syncEngine()
    }

    func switchLayer(_ layer: KeyLayer) {
        self.layer = layer
    }

    // MARK: - AI 面板

    /// ✨：展开 AI 面板并直接执行（输入框有内容就润色或按要求改）。
    func sparkleTapped() {
        setAIExpanded(true)
        execute()
    }

    func setAIExpanded(_ expanded: Bool) {
        guard expanded != aiExpanded else { return }
        finishComposition()
        aiExpanded = expanded
    }

    /// 点「正式▾」：打开或关上风格浮层（只有这里能收起）。打开时光标进要求框，回车键变「执行」；关上回到原输入框。
    func toggleStyleMenu() {
        finishComposition()
        styleMenuOpen.toggle()
        target = styleMenuOpen ? .instruction : .host
    }

    /// 浮层里的「润色」：按选好的风格和要求开始改。浮层不收起，只有再点「正式▾」才收。
    func menuPolishTapped() {
        finishComposition()
        setAIExpanded(true)
        regenerate()
    }

    /// 点要求框：键盘的输入切到要求框，再点一下切回原输入框。
    func toggleInstructionEditing() {
        finishComposition()
        target = target == .instruction ? .host : .instruction
    }

    /// 把正在拼的字母原样上屏，然后清空引擎。
    private func finishComposition() {
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
            setInstruction(instruction + text)
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
    /// nil 表示空格键不写字（和 iOS 26 一样只在角落标语言）。九宫格的空格键照系统写「空格」。
    var spaceTitle: String? {
        if isComposing { return "选定" }
        // 词库没部署或没开完全访问时，中文模式也只能直接打字母。
        if chineseMode && !pinyinReady { return "空格（拼音未就绪）" }
        return showsNineKey ? "空格" : nil
    }

    /// nil 表示画系统的换行图标。
    var returnTitle: String? {
        if isComposing { return "确认" }
        return target == .instruction ? "执行" : nil
    }

    var returnHighlighted: Bool { target == .instruction && !isComposing }
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
            case "english": if chineseMode { toggleChinese() }
            case "instruction", "menu": styleMenuOpen = true; target = .instruction
            case "cardExpanded": aiExpanded = true; cardExpanded = true
            #if DEBUG
            case "versions": aiExpanded = true; debugUnblocked = true; loadDebugVersions()
            case "running": aiExpanded = true; debugUnblocked = true; loadDebugRunning()
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
    }
}
