import Foundation

/// 打字出 emoji 候选（0.95 A5）：首选正好是词表里的词（开心、猫、生日）时，在候选第三个放一个 emoji，不抢首选。
/// 词表 Keyboard/Emoji/zh_emoji.tsv 由 scripts/build-emoji.py 从 Unicode CLDR 的中文 emoji 注释生成。
/// 只在引擎队列上用（见 QueuedEngine）。
enum EmojiTable {
    /// 键盘弹出时从 EmojiSuggestions 读。
    static var enabled = true
    /// emoji 放在候选的第几个（从 0 数）；候选不够时放最后。
    static let position = 2

    private static let table: [String: String] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "zh_emoji", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let first = parts[1].split(separator: " ").first else { continue }
            result[String(parts[0])] = String(first)
        }
        return result
    }()

    static func emoji(for word: String) -> String? {
        enabled ? table[word] : nil
    }

    private final class BundleToken {}
}
