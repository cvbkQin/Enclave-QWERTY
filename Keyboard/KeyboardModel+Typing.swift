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
        case .instruction:
            guard !instruction.isEmpty else { return }
            setInstruction(String(instruction.dropLast()))
        }
    }

    func spaceKey() {
        if isComposing {
            selectCandidate(0)
        } else {
            commit(" ")
        }
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
        case .instruction: execute()
        }
    }

    func selectCandidate(_ index: Int) {
        if let text = engine.select(index) { commit(text) }
        syncEngine()
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
    }

    /// 中文模式用拼音引擎，英文模式或词库不可用时字母直接上屏。
    func selectEngine() {
        engine.reset()
        pinyinReady = hasFullAccess && RimeEngine.shared.prepare()
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
        if isComposing, let raw = engine.commitComposition() { commit(raw) }
        engine.reset()
        syncEngine()
        aiExpanded = expanded
        // 展开时打字进要求框，收起后回到聊天输入框。
        target = expanded ? .instruction : .host
    }

    // MARK: - 内部

    func commit(_ text: String) {
        switch target {
        case .host: proxy?.insertText(text)
        case .instruction: setInstruction(instruction + text)
        }
    }

    func syncEngine() {
        composition = engine.composition
        candidates = engine.candidates
    }
}
