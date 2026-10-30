import Foundation

/// 设置 · 拼音「emoji 候选」开关（0.95 A5），默认开，存在 App Group；键盘弹出时读一次（见 KeyboardModel.reload）。
enum EmojiSuggestions {
    private static let key = "emojiSuggestions.enabled"

    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: key) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: key) }
    }
}
