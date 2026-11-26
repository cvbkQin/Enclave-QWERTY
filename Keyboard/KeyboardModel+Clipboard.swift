import SwiftUI
import UIKit

// 剪贴板（B1，CB1–CB4；T97 点开就存，design/clipboard-autosave CA1）：判断有没有新复制的内容只看 changeCount 和 hasStrings，
// 不读内容（系统不弹提示）。剪贴板一栏露出来时（打开面板、点竖条恢复、iPad 切到剪贴板标签）才读 UIPasteboard.general.string，
// 存成第一条、不粘贴，系统这时在顶部弹「粘贴自…」横幅。像密码或验证码的不读不存，留一行「点一下粘贴」。
// 「自动保存复制的内容」开着时（方案 B，CA2）：键盘出现、每秒轮询发现换过就读出来存。键盘上不出自己的提示，也不亮小紫点，
// 只有系统读剪贴板时自己弹的「粘贴自…」（cvbk 11-25 16:38、11-26 04:29，对齐清单第 95 条）。
// 只有 changeCount 和存在 App Group 里的上次值不同才读：没新复制时呼出键盘不读，系统也不弹横幅。
extension KeyboardModel {
    private static let splitKey = "quick.split"

    /// 键盘出现、回到前台时查一次。没开完全访问时读不了剪贴板。
    func checkClipboard() {
        #if DEBUG
        if debugHelpClipboard { return }
        #endif
        guard hasFullAccess else {
            if clipboardHasNew { clipboardHasNew = false }
            return
        }
        let board = UIPasteboard.general
        let count = board.changeCount
        let new = ClipboardHistory.hasNew(changeCount: count, hasStrings: board.hasStrings)
        if clipboardHasNew != new { clipboardHasNew = new }
        // 换了一次复制：上次「像密码」的判断不算数了。
        if clipboardSensitive && (!new || clipboardSensitiveCount != count) { clipboardSensitive = false }
        refreshHelpCopy()
    }

    /// 剪贴板一栏露出来了（ClipboardList 出现）：记录开着、有新复制的文字就读出来存成第一条，不粘贴（方案 A）。
    /// 收起成竖条时这一栏不在，不读；点竖条恢复后才读。像密码或验证码的不读，留虚线行等用户点。
    func clipboardColumnShown() {
        captureNewClipboard(auto: false)
    }

    /// 「自动保存复制的内容」开着（方案 B，CA2）：键盘出现时、每秒轮询发现 changeCount 变了时调用，
    /// 有新复制的文字就读出来存，不出提示。键盘收起时不轮询，不读。
    func autoSaveClipboard() {
        guard ClipboardHistory.autoSaveActive else { return }
        captureNewClipboard(auto: true)
    }

    /// 两种读法共用：先只看元数据（changeCount、hasStrings、条目类型、detectPatterns，系统不弹提示），
    /// 像密码或验证码的不读，其余读出来存成第一条。auto 为 false 时只在剪贴板一栏还开着时存。
    private func captureNewClipboard(auto: Bool) {
        #if DEBUG
        if debugHelpClipboard { return }
        #endif
        guard hasFullAccess else { return }
        let board = UIPasteboard.general
        let count = board.changeCount
        guard ClipboardHistory.shouldCapture(enabled: ClipboardHistory.isEnabled, columnVisible: true, changeCount: count,
                                             hasStrings: board.hasStrings, last: ClipboardHistory.lastChangeCount) else { return }
        if ClipboardHistory.isConcealed(types: board.types) { return markClipboardSensitive(count) }
        // 同一次复制已经在查了（轮询和打开面板撞在一起）：不重复查。
        guard clipboardChecking != count else { return }
        clipboardChecking = count
        // 纯数字（验证码、手机号）：系统判断，不读内容、不弹横幅。查不出来就当能存。
        board.detectPatterns(for: [.number]) { [weak self] result in
            let digits = (try? result.get())?.contains(.number) == true
            Task { @MainActor in
                guard let self else { return }
                if self.clipboardChecking == count { self.clipboardChecking = nil }
                let stillThere = auto ? ClipboardHistory.autoSaveActive : self.clipboardPanelShowing
                guard UIPasteboard.general.changeCount == count, stillThere else { return }
                if digits { return self.markClipboardSensitive(count) }
                // 面板开着时新的一条直接出现在列表最上面，标「新」；没开着就只是存下来。
                self.captureClipboard(count: count)
            }
        }
    }

    /// 剪贴板一栏收起时竖条上的 7pt 紫点：有新复制的内容。开了自动保存就不亮（cvbk 11-26 04:29「既然有横幅提示，
    /// 那就不要键盘上的这个点了」），新复制的已经存下来了。
    var clipboardDotShown: Bool { hasFullAccess && clipboardHasNew && !ClipboardHistory.autoSaveActive }

    /// 「常用 / 剪贴板」开着（iPhone 面板，或 iPad 9 键中间那块）。
    var clipboardPanelShowing: Bool { keysPanel == .quickWords || padMiddle == .quick }

    private func markClipboardSensitive(_ count: Int) {
        clipboardSensitiveCount = count
        if !clipboardSensitive { clipboardSensitive = true }
    }

    /// 读出新复制的文字，存成第一条（和已有的一条相同时挪到最前），记下 changeCount。不上屏。图片之类不存。
    @discardableResult
    private func captureClipboard(count: Int) -> Bool {
        let board = UIPasteboard.general
        ClipboardHistory.lastChangeCount = count
        clipboardHasNew = false
        clipboardSensitive = false
        guard let text = board.string, !text.isEmpty else { return false }
        withAnimation(.easeOut(duration: 0.25)) { clipItems = ClipboardHistory.add(text) }
        return true
    }

    /// 离开面板（返回、点常用语上屏、收起键盘）：记下时间，之后再存的下次标「新」。
    func noteClipboardPanelLeft() {
        ClipboardHistory.panelLeftAt = Date()
    }

    /// 打开「常用 / 剪贴板」（对齐清单第 62 条）：左常用语、右剪贴板，比例照上次。
    func openQuickPanel() {
        loadQuickWords()
        openPanel(.quickWords)
    }

    /// 读常用语、剪贴板记录：打开「常用 / 剪贴板」面板、iPad 9 键中间那块换成常用剪贴板（PK17）时各读一次。
    func loadQuickWords() {
        checkClipboard()
        reloadClips()
        quickPhrases = CommonWordStore.keyboardPhrases
        phraseDisplay = CommonWordStore.phraseDisplay
        quickSplit = QuickSplit.stored(SharedStorage.defaults.object(forKey: Self.splitKey) as? Double)
        // 上次离开面板以后存进来的标「新」；第一次打开没有记录，从现在算。
        clipNewAfter = ClipboardHistory.panelLeftAt ?? Date()
        clipMenu = nil
        clipClearArmed = false
    }

    /// 常用语栏头的切换钮：标题和内容 → 标题 → 内容 → 标题和内容。和 App 共用一个值。
    func cyclePhraseDisplay() {
        phraseDisplay = phraseDisplay.next
        CommonWordStore.phraseDisplay = phraseDisplay
    }

    /// 拖完分割线、点竖条恢复：记下比例，下次打开照旧。
    func setQuickSplit(_ split: CGFloat) {
        quickSplit = split
        SharedStorage.defaults.set(Double(split), forKey: Self.splitKey)
    }

    func reloadClips() {
        clipItems = hasFullAccess ? ClipboardHistory.load() : []
    }

    /// 点提示行：这时才读剪贴板。读到的文字上屏，记下 changeCount，紫点消失。
    /// 两种情况才有这一行：记录关着（只粘贴，add 不存）；像密码或验证码（save 为 false，不存）。
    func pasteNewClipboard(save: Bool = true) {
        let board = UIPasteboard.general
        let count = board.changeCount
        guard let text = board.string, !text.isEmpty else {
            // 图片之类：不存，也算看过了。
            ClipboardHistory.lastChangeCount = count
            clipboardHasNew = false
            showKeysToast(L("只能粘贴文字", "Only text can be pasted", "貼り付けられるのはテキストだけです"))
            return
        }
        commit(text)
        ClipboardHistory.lastChangeCount = count
        clipboardHasNew = false
        clipboardSensitive = false
        if save { clipItems = ClipboardHistory.add(text) }
    }

    /// 点列表里的一条：插入到光标处，面板不关（方便连续粘贴）。
    func pasteClip(_ item: ClipItem) {
        clipMenu = nil
        commit(item.text)
    }

    enum ClipAction { case paste, addToPhrases, copy, delete }

    func performClipAction(_ action: ClipAction, item: ClipItem) {
        clipMenu = nil
        switch action {
        case .paste:
            commit(item.text)
        case .addToPhrases:
            // 存进常用词（拼音按词自动生成，英文、数字没有拼音就空着，用户可以在 App 里补），也放到键盘常用语。
            var words = CommonWordStore.load()
            if !words.contains(where: { $0.text == item.text }) {
                words.append(CommonWord(text: item.text, pinyin: CommonWordStore.pinyin(of: item.text)))
                CommonWordStore.save(words)
            }
            var phrases = CommonWordStore.keyboardPhrases
            if !phrases.contains(where: { $0.text == item.text }) {
                phrases.append(KeyboardPhrase(text: item.text))
                CommonWordStore.keyboardPhrases = phrases
            }
            quickPhrases = phrases
            refreshCandidatesAfterPhraseChange()
            showKeysToast(L("★ 已加到常用语，可在 App 里改拼音和简码", "★ Added to phrases. Edit pinyin and shortcut in the app.",
                            "★ 定型文に追加しました。読みと短縮はアプリで変更できます"))
            objectWillChange.send()
        case .copy:
            UIPasteboard.general.string = item.text
            // 自己写进去的不算「新复制的内容」，也不是待回的复制。
            noteOwnCopy()
            showKeysToast(L("已复制", "Copied", "コピーしました"))
        case .delete:
            ClipboardHistory.remove(item.id)
            withAnimation(.easeOut(duration: 0.2)) { reloadClips() }
        }
    }

    /// 「清空」：第一次点变成「确认清空」，3 秒内再点才清。
    func tapClearClips() {
        if clipClearArmed {
            clipClearArmed = false
            ClipboardHistory.clear()
            withAnimation(.easeOut(duration: 0.2)) { reloadClips() }
        } else {
            clipClearArmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.clipClearArmed = false }
        }
    }

    func showKeysToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { keysToast = text }
        keysToastTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.25)) { self?.keysToast = nil }
        }
        keysToastTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: timer)
    }
}
