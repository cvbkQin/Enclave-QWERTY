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
            target = .host
            execute()
        }
    }

    func selectCandidate(_ index: Int) {
        if let text = engine.select(index) { commit(text) }
        syncEngine()
    }

    // MARK: - 按键触摸（由 KeyTouchView 调用）

    var layoutState: KeyLayout.State {
        KeyLayout.State(layer: layer, nineKey: showsNineKey, chineseMode: chineseMode, needsGlobeKey: needsGlobeKey)
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
        case .clearComposition: clearComposition()
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
        finishComposition()
        aiExpanded = expanded
        // 展开后打字仍然进原输入框；收起时也退出要求框。
        if !expanded { target = .host }
    }

    /// 点要求框：键盘的输入切到要求框，再点一下切回原输入框。
    func toggleInstructionEditing() {
        finishComposition()
        if target == .instruction {
            target = .host
        } else {
            // 从常用要求切到自己写：清掉选中的常用要求，从空白开始。
            if Self.presets.contains(where: { $0.instruction == instruction }) { setInstruction("") }
            target = .instruction
        }
    }

    /// 选一个常用要求；再点一次取消。选用后退出自己写要求的输入。
    func selectPreset(_ text: String) {
        finishComposition()
        setInstruction(instruction == text ? "" : text)
        target = .host
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
            case "instruction": aiExpanded = true; target = .instruction
            #if DEBUG
            case "versions": aiExpanded = true; loadDebugVersions()
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
    }
}
