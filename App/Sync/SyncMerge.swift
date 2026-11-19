import CryptoKit
import Foundation

/// iCloud 同步的合并规则（specs/icloud-sync/iCloud同步方案.md 1.5–1.8、3.1）：纯逻辑，不碰存储、不联网，单元测试直接编这个文件。
///
/// 常用词、常用语用「每条以最后一次改动为准」的表：每台设备上传自己知道的全部条目（在或删了，带时间），
/// 合并时每条取时间最新的。本机的改动不在保存时记（键盘里的保存不用改），而是同步时和上次同步完的样子比出来。
/// AI 接口和风格整份以最后修改的为准，不逐条合并（默认风格每台设备的 id 不一样，逐条合并会出两个「正式」）。
enum SyncMerge {
    /// 一条在某个时间的状态。value 为 nil：删了。
    struct Entry<Value: Codable & Equatable>: Codable, Equatable {
        var value: Value?
        var time: Date
    }

    typealias Table<Value: Codable & Equatable> = [String: Entry<Value>]

    /// 第一次同步前就有的条目记成这个时间：别的设备后来删过的照样删掉，新设备上的默认值也不会盖过旧设备改好的（1.8）。
    static let initialTime = Date(timeIntervalSince1970: 0)

    /// 删除记录留多久：超过的不再上传，免得表越长越大。
    static let keepDeleted: TimeInterval = 180 * 86400

    // MARK: - 逐条合并的表（常用词、常用语）

    /// 本机现在的列表和上次同步完的表比：新出现的、内容变了的记成 now 时「在」，不见了的记成 now 时「删了」。
    /// previous 为 nil（这台设备第一次同步）时，现有的都记成 initialTime。列表里同一个 key 出现两次时只认第一个。
    static func observe<V: Codable & Equatable>(current: [(key: String, value: V)], previous: Table<V>?, now: Date) -> Table<V> {
        var result = previous ?? [:]
        let stamp = previous == nil ? initialTime : now
        var seen = Set<String>()
        for item in current where seen.insert(item.key).inserted {
            if let old = result[item.key], old.value == item.value { continue }
            result[item.key] = Entry(value: item.value, time: stamp)
        }
        let removed = Array(result.filter { $0.value.value != nil && !seen.contains($0.key) }.keys)
        for key in removed { result[key] = Entry(value: nil, time: now) }
        return result
    }

    /// 几台设备的表合成一份：每条取时间最新的；时间一样时「在」比「删了」优先（宁可多留不丢）。
    /// 两边都「在」、时间一样、内容不同时取先传进来的那张表的：调用方按设备编号排好序，每台设备算出来的一样。
    static func merge<V: Codable & Equatable>(_ tables: [Table<V>]) -> Table<V> {
        var result: Table<V> = [:]
        for table in tables {
            for (key, entry) in table {
                guard let old = result[key] else {
                    result[key] = entry
                    continue
                }
                if entry.time > old.time || (entry.time == old.time && old.value == nil && entry.value != nil) {
                    result[key] = entry
                }
            }
        }
        return result
    }

    /// 按合并结果改本机列表：本机原有的保持原来的顺序，合并后删了的去掉、内容换成合并后的；
    /// 本机没有的接在后面（按时间先后）。合并结果里查不到的条目原样留着，不会因为表不全就删本机的东西。
    static func apply<V: Codable & Equatable>(_ merged: Table<V>, to current: [(key: String, value: V)]) -> [(key: String, value: V)] {
        var result: [(key: String, value: V)] = []
        var used = Set<String>()
        for item in current where used.insert(item.key).inserted {
            if let entry = merged[item.key] {
                if let value = entry.value { result.append((key: item.key, value: value)) }
            } else {
                result.append(item)
            }
        }
        let incoming = merged.filter { !used.contains($0.key) && $0.value.value != nil }
            .sorted { ($0.value.time, $0.key) < ($1.value.time, $1.key) }
        for (key, entry) in incoming {
            if let value = entry.value { result.append((key: key, value: value)) }
        }
        return result
    }

    /// 去掉太久以前的删除记录。
    static func pruned<V: Codable & Equatable>(_ table: Table<V>, now: Date) -> Table<V> {
        table.filter { $0.value.value != nil || now.timeIntervalSince($0.value.time) < keepDeleted }
    }

    // MARK: - 整份以最后修改为准的一项（AI 接口和风格）

    /// 和上次同步完的比：没变就还是原来那条（时间不动），变了记成 now。第一次同步记成 initialTime。
    static func observeValue<V: Codable & Equatable>(_ current: V, previous: Entry<V>?, now: Date) -> Entry<V> {
        guard let previous else { return Entry(value: current, time: initialTime) }
        return previous.value == current ? previous : Entry(value: current, time: now)
    }

    /// 取时间最新的一条；时间一样取先传进来的（调用方把本机的放在最前面）。
    static func latest<V: Codable & Equatable>(_ entries: [Entry<V>]) -> Entry<V>? {
        var best: Entry<V>?
        for entry in entries where entry.value != nil {
            if let current = best, entry.time <= current.time { continue }
            best = entry
        }
        return best
    }

    // MARK: - 拼音快照

    /// 清除学到的词的代数（1.5）：取所有设备里最大的；只有代数等于它的设备的快照参与合并。
    static func generation(local: Int, peers: [Int]) -> Int {
        max(local, peers.max() ?? 0)
    }

    /// 快照压缩、分块（CloudKit 一条记录最多 1 MB），校验是压缩后整份的 SHA-256。空快照是 0 块、空校验。
    static func packSnapshot(_ snapshot: String, chunkSize: Int) throws -> (chunks: [Data], hash: String) {
        guard !snapshot.isEmpty else { return ([], "") }
        let compressed = try (Data(snapshot.utf8) as NSData).compressed(using: .zlib) as Data
        var chunks: [Data] = []
        var start = 0
        while start < compressed.count {
            let end = min(start + chunkSize, compressed.count)
            chunks.append(compressed.subdata(in: start..<end))
            start = end
        }
        return (chunks, hex(SHA256.hash(data: compressed)))
    }

    /// 拼回快照；块不齐、校验对不上（那台设备正传到一半）时为 nil。
    static func unpackSnapshot(_ chunks: [Data], hash: String) -> String? {
        guard !chunks.isEmpty else { return hash.isEmpty ? "" : nil }
        var compressed = Data()
        for chunk in chunks { compressed.append(chunk) }
        guard hex(SHA256.hash(data: compressed)) == hash,
              let data = try? (compressed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 同步的内容

extension SyncMerge {
    /// 常用词里同步的部分：只同步自己加的和导入的（系统「文本替换」、通讯录不带），按字认同一个词，和备份恢复一样（BackupMerge）。
    struct Word: Codable, Equatable {
        var text: String
        var pinyin: String
        var shortcut: String
        var source: CommonWord.Source

        init(_ word: CommonWord) {
            text = word.text
            pinyin = word.pinyin
            shortcut = word.shortcut
            source = word.source
        }

        /// 换回常用词；本机已有这个词时沿用它的 id（键盘、统计跟着 id）。
        func commonWord(keeping id: UUID?) -> CommonWord {
            var word = CommonWord(text: text, pinyin: pinyin, shortcut: shortcut, source: source)
            if let id { word.id = id }
            return word
        }
    }

    static func wordItems(_ words: [CommonWord]) -> [(key: String, value: Word)] {
        words.filter { !$0.isReadOnly && !$0.text.isEmpty }.map { (key: $0.text, value: Word($0)) }
    }

    /// 合并后的词换回常用词列表（保留本机原有的 id）。
    static func words(_ items: [(key: String, value: Word)], current: [CommonWord]) -> [CommonWord] {
        let ids = Dictionary(current.map { ($0.text, $0.id) }, uniquingKeysWith: { first, _ in first })
        return items.map { $0.value.commonWord(keeping: ids[$0.key]) }
    }

    /// 键盘常用语：内容是这一条的身份（KeyboardPhrase.id 就是内容）。
    static func phraseItems(_ phrases: [KeyboardPhrase]) -> [(key: String, value: KeyboardPhrase)] {
        phrases.filter { !$0.text.isEmpty }.map { (key: $0.text, value: $0) }
    }

    /// AI 接口（不含 Key）和润色、问答风格（3.1）。模糊音、双拼、键盘布局、声音振动、外观、联网方式都不在这里（1.6）。
    struct AIProfile: Codable, Equatable {
        var baseURL: String
        var model: String
        var temperature: Double
        var maxTokens: Int
        var separateAnswer: Bool
        var answerBaseURL: String
        var answerModel: String
        var answerTemperature: Double?
        var answerMaxTokens: Int?
        var polishEnabled: Bool
        var answerEnabled: Bool
        var styles: [StylePreset]
        var selectedStyleID: UUID?
        var answerStyles: [StylePreset]
        var selectedAnswerStyleID: UUID?
        var searchTendency: Int?
        var pinnedStyleIDs: [UUID]
        var helpPinned: Bool
        var savedAPIs: [SavedAPI]

        init(settings: EnclaveSettings, savedAPIs: [SavedAPI]) {
            baseURL = settings.baseURL
            model = settings.model
            temperature = settings.temperature
            maxTokens = settings.maxTokens
            separateAnswer = settings.separateAnswer
            answerBaseURL = settings.answerBaseURL
            answerModel = settings.answerModel
            answerTemperature = settings.answerTemperature
            answerMaxTokens = settings.answerMaxTokens
            polishEnabled = settings.polishEnabled
            answerEnabled = settings.answerEnabled
            styles = settings.styles
            selectedStyleID = settings.selectedStyleID
            answerStyles = settings.answerStyles
            selectedAnswerStyleID = settings.selectedAnswerStyleID
            searchTendency = settings.searchTendency
            pinnedStyleIDs = settings.pinnedStyleIDs
            helpPinned = settings.helpPinned
            self.savedAPIs = savedAPIs
        }

        /// 写回设置：只改上面这些，别的（键盘、词库部署相关的）不动。接口配置列表由调用方另存。
        func apply(to settings: inout EnclaveSettings) {
            settings.baseURL = baseURL
            settings.model = model
            settings.temperature = temperature
            settings.maxTokens = maxTokens
            settings.separateAnswer = separateAnswer
            settings.answerBaseURL = answerBaseURL
            settings.answerModel = answerModel
            settings.answerTemperature = answerTemperature
            settings.answerMaxTokens = answerMaxTokens
            settings.polishEnabled = polishEnabled
            settings.answerEnabled = answerEnabled
            settings.styles = styles
            settings.selectedStyleID = selectedStyleID
            settings.answerStyles = answerStyles
            settings.selectedAnswerStyleID = selectedAnswerStyleID
            settings.searchTendency = searchTendency
            settings.pinnedStyleIDs = pinnedStyleIDs
            settings.helpPinned = helpPinned
        }
    }

    /// 一台设备在 iCloud 里的全部内容（除了拼音快照的分块），整份放在 CloudKit 的加密字段里。
    struct DevicePayload: Codable, Equatable {
        /// 格式版本：看到比自己新的就跳过这台设备，不报错（1.12）。
        static let currentFormat = 1

        var format: Int
        var deviceName: String
        var appVersion: String
        var updatedAt: Date
        /// 清除学到的词的代数（1.5）。
        var generation: Int
        var words: Table<Word>
        var phrases: Table<KeyboardPhrase>
        /// 带内置 Key 的包不同步 AI 接口，是 nil。
        var ai: Entry<AIProfile>?
        /// 拼音快照：压缩后分几块、压缩后整份的 SHA-256。没有学到的词时 0 块。
        var snapshotChunks: Int
        var snapshotHash: String
    }
}
