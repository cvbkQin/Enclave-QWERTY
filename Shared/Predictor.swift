import Foundation

/// 联想：上屏一个词后，候选栏接着给出常跟在它后面的词。数据是词库目录里的 predict.tsv
/// （scripts/build-dict.py 从万象基础词库拆出来的「词 → 后面常跟的几个词」）。
/// 键盘弹出时在后台读一次，没读完之前不联想。
enum Predictor {
    private static let enabledKey = "prediction.enabled"
    private static var table: [String: [String]] = [:]
    private static var loadedFrom: URL?
    private static let queue = DispatchQueue(label: "enclave.predictor", qos: .utility)
    private static let lock = NSLock()

    /// 有联想时按空格上屏第一个联想词（一直按空格就一直往下接）；关掉时空格收起联想、打一个空格。
    static var spaceChains: Bool {
        get { SharedStorage.defaults.object(forKey: spaceChainKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: spaceChainKey) }
    }
    private static let spaceChainKey = "prediction.spaceChain"

    /// 英文单词补全和下一个词联想（数据随键盘内置，不用下载）。
    static var englishEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: englishKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: englishKey) }
    }
    private static let englishKey = "prediction.english"

    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: enabledKey) }
    }

    /// 键盘弹出时：找到现在用的那份词库里的 predict.tsv，换了才重新读。
    static func prepare() {
        guard isEnabled, let url = fileURL() else { return }
        lock.lock()
        let same = loadedFrom == url
        lock.unlock()
        if same { return }
        queue.async {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
            let result = parseTable(data, capacity: 20000)
            lock.lock()
            table = result
            loadedFrom = url
            lock.unlock()
        }
    }

    /// 收到内存警告、又在打英文用不上联想时放掉表，下次弹出键盘再读。
    static func unload() {
        lock.lock()
        table = [:]
        loadedFrom = nil
        lock.unlock()
    }

    /// 读「词 \t 后面的词（空格隔开）」一行一条的表。按字节切，不按 Character：
    /// String.split 按字符切要逐个判断字形边界，几万行的表在键盘冷启动时要多花好几倍的时间。
    static func parseTable(_ data: Data, capacity: Int) -> [String: [String]] {
        var result = [String: [String]](minimumCapacity: capacity)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for line in raw.split(separator: 0x0A) {
                guard let tab = line.firstIndex(of: 0x09) else { continue }
                let words = line[line.index(after: tab)...].split(separator: 0x20).map { String(decoding: $0, as: UTF8.self) }
                result[String(decoding: line[..<tab], as: UTF8.self)] = words
            }
        }
        return result
    }

    /// 刚上屏的字后面常跟什么。整段对不上就看它最后几个字（「我们今天」按「今天」联想）。
    static func next(after text: String) -> [String] {
        guard isEnabled else { return [] }
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        for length in stride(from: min(chars.count, 6), through: 2, by: -1) {
            if let words = table[String(chars.suffix(length))] { return words }
        }
        return []
    }

    /// 键盘读到的是哪份词库就用哪份里的联想数据。
    private static func fileURL() -> URL? {
        let fm = FileManager.default
        if RimeStore.isDeployed, let shared = RimeStore.paths?.shared.appendingPathComponent("predict.tsv"),
           fm.fileExists(atPath: shared.path) {
            return shared
        }
        if let bundled = RimeStore.bundled?.paths.shared.appendingPathComponent("predict.tsv"),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        return nil
    }
}
