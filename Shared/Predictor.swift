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
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            var result: [String: [String]] = [:]
            result.reserveCapacity(20000)
            for line in text.split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t") else { continue }
                result[String(line[..<tab])] = line[line.index(after: tab)...].split(separator: " ").map(String.init)
            }
            lock.lock()
            table = result
            loadedFrom = url
            lock.unlock()
        }
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
