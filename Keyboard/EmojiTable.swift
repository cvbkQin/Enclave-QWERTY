import Foundation

/// 打字出 emoji 候选（0.95 A5）：第一屏前几个候选里第一个是词表里的词（开心、猫、生日）的，在它后面紧挨着放一个 emoji，
/// 整屏最多一个，不抢首选（同 iOS 原生拼音、rime-emoji）。
/// 词表 Keyboard/Emoji/zh_emoji.tsv 由 scripts/build-emoji.py 从 Unicode CLDR 的中文 emoji 注释生成。
/// 只在引擎队列上用（见 QueuedEngine）。
enum EmojiTable {
    /// 键盘弹出时从 EmojiSuggestions 读。
    static var enabled = true
    /// 看前几个候选找词表里的词。
    static let lookahead = 3

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
