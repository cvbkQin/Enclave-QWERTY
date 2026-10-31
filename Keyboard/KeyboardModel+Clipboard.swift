import SwiftUI
import UIKit

/// 九宫格「常用」面板的两个标签。
enum QuickTab: String {
    case phrases, clipboard
}

// 剪贴板（B1，CB1–CB4）：判断有没有新复制的内容只看 changeCount 和 hasStrings，不读内容（系统不弹提示）；
// 用户点「有新复制的内容，点一下粘贴」时才读 UIPasteboard.general.string，系统这时在顶部弹「粘贴自…」横幅。
extension KeyboardModel {
    private static let quickTabKey = "quick.lastTab"

    /// 键盘出现、回到前台时查一次。没开完全访问时读不了剪贴板，不出紫点。
    func checkClipboard() {
        guard hasFullAccess else {
            if clipboardHasNew { clipboardHasNew = false }
            return
        }
        let board = UIPasteboard.general
        let new = ClipboardHistory.hasNew(changeCount: board.changeCount, hasStrings: board.hasStrings)
        if clipboardHasNew != new { clipboardHasNew = new }
    }

    /// 打开「常用」：有新内容时直接停在剪贴板，否则停在上次用的标签。
    func openQuickPanel() {
        checkClipboard()
        let last = SharedStorage.defaults.string(forKey: Self.quickTabKey).flatMap(QuickTab.init(rawValue:)) ?? .phrases
        quickTab = clipboardHasNew ? .clipboard : last
        if quickTab == .clipboard { reloadClips() }
        clipMenu = nil
        clipClearArmed = false
        openPanel(.quickWords)
    }

    func selectQuickTab(_ tab: QuickTab) {
        guard quickTab != tab else { return }
        quickTab = tab
        clipMenu = nil
        clipClearArmed = false
        SharedStorage.defaults.set(tab.rawValue, forKey: Self.quickTabKey)
        if tab == .clipboard {
            checkClipboard()
            reloadClips()
        }
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
            var texts = CommonWordStore.keyboardTexts
            if !texts.contains(item.text) {
                texts.append(item.text)
                CommonWordStore.keyboardTexts = texts
            }
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
