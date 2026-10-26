import Foundation

/// 英文打字时的单词补全和下一个词联想。数据在 Keyboard/English/ 里，随键盘打包
/// （scripts/build-english.py 从万象英文词库和 Tatoeba 例句生成）：
/// - en_words.tsv：「去掉撇号的小写拼写 \t 写法 \t 词频」，按拼写排序，按前缀二分查找；
/// - en_next.tsv：「词 \t 后面常跟的几个词」。
/// 用户自己选过、打过的词记在本机，下次排得更前；词表里没有的词（人名、网络用语）打过两次也会出现。
enum EnglishPredictor {
    private struct Entry {
        let key: String
        let word: String
        let weight: Int32
    }

    private static var entries: [Entry] = []
    private static var next: [String: [String]] = [:]
    private static var learned: [String: Int] = [:]
    private static var learnedDirty = false
    private static var loaded = false
    private static let queue = DispatchQueue(label: "enclave.english", qos: .utility)
    private static let lock = NSLock()
    private static let learnedKey = "english.learned"
    private static let maxLearned = 3000

    /// 键盘弹出时在后台读一次；没读完之前不补全。
    static func prepare() {
        lock.lock()
        let done = loaded
        lock.unlock()
        guard !done else { return }
        queue.async {
            let words = load("en_words").map(parseWords) ?? []
            let table = load("en_next").map(parseNext) ?? [:]
            let saved = SharedStorage.defaults.dictionary(forKey: learnedKey) as? [String: Int] ?? [:]
            lock.lock()
            entries = words
            next = table
            learned = saved
            loaded = true
            lock.unlock()
        }
    }

    /// 以 prefix 开头的词，最多 limit 个，常用的在前；不含和 prefix 一样的词。写法跟着 prefix 的大小写走。
    static func complete(_ prefix: String, limit: Int = 6) -> [String] {
        let key = prefix.lowercased().filter { $0 != "'" }
        guard !key.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var scored: [(word: String, score: Double)] = []
        var seen = Set<String>()
        let range = matches(key)
        for index in range {
            let entry = entries[index]
            let lower = entry.word.lowercased()
            guard lower != prefix.lowercased(), seen.insert(lower).inserted else { continue }
            scored.append((entry.word, score(Double(entry.weight), learned[lower] ?? 0)))
        }
        // 词表里没有、但自己打过至少两次的词。
        for (word, count) in learned where count >= 2 && !seen.contains(word) {
            let wordKey = word.filter { $0 != "'" }
            guard wordKey.hasPrefix(key), word != prefix.lowercased() else { continue }
            scored.append((word, score(0, count)))
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map { cased($0.word, like: prefix) }
    }

    /// 刚打完的词后面常跟什么。
    static func next(after word: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return next[word.lowercased()] ?? []
    }

    /// 打完一个词（后面跟了空格或标点）、或者点了补全：记一次。
    static func learn(_ word: String) {
        let lower = word.lowercased()
        guard lower.count >= 2, lower.count <= 30, lower.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'") }) else { return }
        lock.lock()
        defer { lock.unlock() }
        learned[lower, default: 0] += 1
        learnedDirty = true
        if learned.count > maxLearned {
            // 太多了先丢只打过一次的。
            learned = learned.filter { $0.value > 1 }
        }
    }

    /// 键盘收起时写回共享存储。
    static func flush() {
        lock.lock()
        guard learnedDirty else { lock.unlock(); return }
        let snapshot = learned
        learnedDirty = false
        lock.unlock()
        SharedStorage.defaults.set(snapshot, forKey: learnedKey)
    }

    // MARK: - 内部

    /// 词频差好几个数量级，取对数；自己用过的词每次加一截。
    private static func score(_ weight: Double, _ count: Int) -> Double {
        log(weight + 1) + Double(min(count, 20)) * 1.5
    }

    /// 二分找出 key 开头的那一段。
    private static func matches(_ key: String) -> Range<Int> {
        var low = 0, high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].key < key { low = mid + 1 } else { high = mid }
        }
        var end = low
        while end < entries.count, entries[end].key.hasPrefix(key) { end += 1 }
        return low..<end
    }

    /// 首字母大写打的就首字母大写，两个字母以上全大写就全大写；词表里本来就大写的（I、人名）不动。
    private static func cased(_ word: String, like prefix: String) -> String {
        guard let first = prefix.first, first.isUppercase else { return word }
        if prefix.count >= 2, prefix.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return word.uppercased() }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    private static func load(_ name: String) -> String? {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "tsv") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func parseWords(_ text: String) -> [Entry] {
        var result: [Entry] = []
        result.reserveCapacity(62000)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 3, let weight = Int32(parts[2]) else { continue }
            result.append(Entry(key: String(parts[0]), word: String(parts[1]), weight: weight))
        }
        return result
    }

    private static func parseNext(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        result.reserveCapacity(15000)
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            result[String(line[..<tab])] = line[line.index(after: tab)...].split(separator: " ").map(String.init)
        }
        return result
    }

    private final class BundleToken {}
}
