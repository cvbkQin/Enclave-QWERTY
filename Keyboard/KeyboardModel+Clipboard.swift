import SwiftUI
import UIKit

// 剪贴板（B1，CB1–CB4）：判断有没有新复制的内容只看 changeCount 和 hasStrings，不读内容（系统不弹提示）；
// 用户点「有新复制的内容，点一下粘贴」时才读 UIPasteboard.general.string，系统这时在顶部弹「粘贴自…」横幅。
extension KeyboardModel {
    private static let splitKey = "quick.split"

    /// 键盘出现、回到前台时查一次。没开完全访问时读不了剪贴板。
    func checkClipboard() {
        guard hasFullAccess else {
            if clipboardHasNew { clipboardHasNew = false }
            return
        }
        let board = UIPasteboard.general
        let new = ClipboardHistory.hasNew(changeCount: board.changeCount, hasStrings: board.hasStrings)
        if clipboardHasNew != new { clipboardHasNew = new }
    }

    /// 打开「常用 / 剪贴板」（对齐清单第 62 条）：左常用语、右剪贴板，比例照上次。
    func openQuickPanel() {
        checkClipboard()
        reloadClips()
        quickPhrases = CommonWordStore.keyboardPhrases
        phraseDisplay = CommonWordStore.phraseDisplay
        quickSplit = QuickSplit.stored(SharedStorage.defaults.object(forKey: Self.splitKey) as? Double)
        clipMenu = nil
        clipClearArmed = false
        openPanel(.quickWords)
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

    /// 点提示行：这时才读剪贴板。读到的文字上屏，存成第一条（开着记录时），记下 changeCount，紫点消失。
    func pasteNewClipboard() {
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
        clipItems = ClipboardHistory.add(text)
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
            // 自己写进去的不算「新复制的内容」。
            ClipboardHistory.lastChangeCount = UIPasteboard.general.changeCount
            clipboardHasNew = false
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
