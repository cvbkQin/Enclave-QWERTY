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
        /// log(词频 + 1)，读词表时算好：短前缀（打第一个字母）一次要排几千个词，每个键现算对数太慢。
        let logWeight: Double
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
            let table = load("en_next").map { Predictor.parseTable($0, capacity: 15000) } ?? [:]
            let saved = SharedStorage.defaults.dictionary(forKey: learnedKey) as? [String: Int] ?? [:]
            lock.lock()
            entries = words
            next = table
            learned = saved
            loaded = true
            lock.unlock()
        }
    }

    /// 收到内存警告、又在打中文用不上时放掉词表（自己打过的词留着），切回英文时再读。
    static func unload() {
        lock.lock()
        entries = []
        next = [:]
        loaded = false
        lock.unlock()
    }

    /// 以 prefix 开头的词，最多 limit 个，常用的在前；不含和 prefix 一样的词。写法跟着 prefix 的大小写走。
    static func complete(_ prefix: String, limit: Int = 6) -> [String] {
        let key = prefix.lowercased().filter { $0 != "'" }
        guard !key.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        // 只留分数最高的 limit 个：打第一个字母时前缀能对上好几千个词，不用全排一遍。
        var top: [(word: String, score: Double)] = []
        func offer(_ word: String, _ score: Double) {
            guard top.count < limit || score > top[top.count - 1].score else { return }
            // 同分的排在先来的后面，和原来整体排序的结果一样。
            let at = top.firstIndex { $0.score < score } ?? top.count
            top.insert((word, score), at: at)
            if top.count > limit { top.removeLast() }
        }
        var seen = Set<String>()
        let typed = prefix.lowercased()
        for index in matches(key) {
            let entry = entries[index]
            // 大多数词本来就是小写、没撇号，和 key 一样，不用再转一遍小写。
            let lower = entry.word == entry.key ? entry.key : entry.word.lowercased()
            guard lower != typed, seen.insert(lower).inserted else { continue }
            offer(entry.word, entry.logWeight + boost(learned[lower] ?? 0))
        }
        // 词表里没有、但自己打过至少两次的词。
        // 每个键都要扫一遍（最多 3000 个），首字母对不上的先跳过，不用逐个去撇号、建新字符串。
        let firstByte = key.utf8.first
        for (word, count) in learned where count >= 2 && word.utf8.first(where: { $0 != 0x27 }) == firstByte
            && !seen.contains(word) {
            let wordKey = word.filter { $0 != "'" }
            guard wordKey.hasPrefix(key), word != typed else { continue }
            offer(word, boost(count))
        }
        return top.map { cased($0.word, like: prefix) }
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

    /// 词频差好几个数量级，取对数（读词表时算好，见 Entry.logWeight）；自己用过的词每次加一截。
    private static func boost(_ count: Int) -> Double {
        Double(min(count, 20)) * 1.5
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

    private static func load(_ name: String) -> Data? {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "tsv") else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// 按字节切行、切列（见 Predictor.parseTable）；词频直接从数字字节算，不先建字符串。
    private static func parseWords(_ data: Data) -> [Entry] {
        var result: [Entry] = []
        result.reserveCapacity(62000)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for line in raw.split(separator: 0x0A) {
                let parts = line.split(separator: 0x09)
                guard parts.count == 3, !parts[2].isEmpty else { continue }
                var weight = 0
                for byte in parts[2] {
                    guard byte >= 0x30, byte <= 0x39 else { weight = -1; break }
                    weight = weight * 10 + Int(byte - 0x30)
                }
                guard weight >= 0 else { continue }
                result.append(Entry(key: String(decoding: parts[0], as: UTF8.self),
                                    word: String(decoding: parts[1], as: UTF8.self),
                                    logWeight: log(Double(weight) + 1)))
            }
        }
        return result
    }

    private final class BundleToken {}
}
