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

    /// 本机改动记的时间：一般是 now；上次那条的时间比 now 还晚（别的设备时钟快）时取它加 1 毫秒，本机的改动才不会输给它。
    static func stamp(now: Date, after old: Date?) -> Date {
        guard let old else { return now }
        return max(now, old.addingTimeInterval(0.001))
    }

    /// 本机现在的列表和上次同步完的表比：新出现的、内容变了的记成 now 时「在」，不见了的记成 now 时「删了」。
    /// previous 为 nil（这台设备第一次同步）时，现有的都记成 initialTime。列表里同一个 key 出现两次时只认第一个。
    static func observe<V: Codable & Equatable>(current: [(key: String, value: V)], previous: Table<V>?, now: Date) -> Table<V> {
        var result = previous ?? [:]
        var seen = Set<String>()
        for item in current where seen.insert(item.key).inserted {
            let old = result[item.key]
            if let old, old.value == item.value { continue }
            result[item.key] = Entry(value: item.value, time: previous == nil ? initialTime : stamp(now: now, after: old?.time))
        }
        let removed = Array(result.filter { $0.value.value != nil && !seen.contains($0.key) }.keys)
        for key in removed { result[key] = Entry(value: nil, time: stamp(now: now, after: result[key]?.time)) }
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
    /// 本机列表里同一个 key 出现两次（手动加了两条同字的常用词）：第一条按合并结果改，后面的原样留着，只有合并后删了才一起去掉。
    static func apply<V: Codable & Equatable>(_ merged: Table<V>, to current: [(key: String, value: V)]) -> [(key: String, value: V)] {
        var result: [(key: String, value: V)] = []
        var used = Set<String>()
        for item in current {
            guard let entry = merged[item.key] else {
                result.append(item)
                used.insert(item.key)
                continue
            }
            guard let value = entry.value else { continue }
            result.append(used.insert(item.key).inserted ? (key: item.key, value: value) : item)
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
        return previous.value == current ? previous : Entry(value: current, time: stamp(now: now, after: previous.time))
    }

    /// 合并结果里有些条目这次还不能用到本机（接口配置配的 Key 还没同步过来）：这些条目记成本机原来的样子，
    /// 下次同步再试。不能直接记合并结果：那样本机还是旧的，下次就会被当成本机改回去了。
    static func accepting<V: Codable & Equatable>(_ merged: Table<V>, mine: Table<V>, where accept: (Entry<V>) -> Bool) -> Table<V> {
        var result = merged
        for (key, entry) in merged where entry != mine[key] && !accept(entry) {
            result[key] = mine[key]
        }
        return result
    }

    /// 整份以最后修改为准的一项，这次该怎么办。
    /// - record：记进本机同步状态、上传的那条；nil 是这次不参加。
    /// - apply：要写进本机的值；nil 是本机不用改。
    /// 按设备编号排好序取最新的（时间一样取编号小的，每台设备算出来一样）。第一次同步（previous 为 nil）时别的设备已经有了，
    /// 本机的不参加，直接用已经在用的那份（新设备上的默认值不盖过别的设备设好的，1.8）；
    /// prefersLocal（打开同步时选了「用这台的」）时反过来，本机的记成比别的设备都晚，所有设备换成这台的。
    /// accept 不通过（接口配的 Key 还没同步过来）时本机先不改、记本机原来的，下次同步再试。
    /// 第一次加入就不通过：本机的照样记下、上传，时间记成比那台早一点（04 复审 A2）。这样下次不再算第一次加入
    /// （本机之后的改动照常算数），又不会盖过那台；那台的 Key 到了，下次同步就换成那台的。
    static func resolve<V: Codable & Equatable>(local: V, previous: Entry<V>?, peers: [String: Entry<V>], myID: String, now: Date,
                                                prefersLocal: Bool = false,
                                                accept: (V) -> Bool = { _ in true }) -> (record: Entry<V>?, apply: V?) {
        let joining = previous == nil && !prefersLocal && peers.values.contains { $0.value != nil }
        var all = peers
        if joining {
            all[myID] = nil
        } else if previous == nil && prefersLocal {
            all[myID] = Entry(value: local, time: stamp(now: now, after: peers.values.map(\.time).max()))
        } else {
            all[myID] = observeValue(local, previous: previous, now: now)
        }
        let ordered = all.sorted { $0.key < $1.key }.map { $0.value }
        guard let winner = latest(ordered), let value = winner.value else { return (all[myID], nil) }
        if value == local { return (winner, nil) }
        guard accept(value) else {
            return (all[myID] ?? Entry(value: local, time: winner.time.addingTimeInterval(-0.001)), nil)
        }
        return (winner, value)
    }

    /// 取时间最新的一条；时间一样取先传进来的（调用方按设备编号排好序）。
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

    /// 这一轮对拼音词库要做什么（1.5，04 审查 #75 第 1、4 条）。
    enum ClearAction: Equatable {
        /// 什么都不做。
        case keep
        /// 只跟上代数，不清本机：第一次同步时，那是这台加入以前别的设备清的。
        case follow(Int)
        /// 清掉本机，代数换成这个：本机刚清过（比所有设备大一），或者别的设备清过（跟上它）。
        case clear(Int)
    }

    /// pendingClear：本机清除了学习记录、还没告诉别的设备。关同步、暂停、重新加入时这个标记会清掉（04 复审 B2），
    /// 所以这里为 true 一定是开着同步时清的，第一次同步也照清。
    static func clearAction(pendingClear: Bool, firstSync: Bool, local: Int, peers: [Int]) -> ClearAction {
        let top = generation(local: local, peers: peers)
        if pendingClear { return .clear(top + 1) }
        guard top > local else { return .keep }
        return firstSync ? .follow(top) : .clear(top)
    }

    /// 这次要合并哪些设备的快照：代数和本机一样、校验和上次合并的不一样的（04 审查 #75 第 3 条）。
    /// unchanged 是没变、不用再合并的（设备编号 → 校验），合并完要原样记下。
    static func snapshotsToMerge(peers: [String: (generation: Int, hash: String)], generation: Int,
                                 merged: [String: String]?) -> (fetch: [String], unchanged: [String: String]) {
        var fetch: [String] = []
        var unchanged: [String: String] = [:]
        for (id, peer) in peers where peer.generation == generation {
            if merged?[id] == peer.hash { unchanged[id] = peer.hash } else { fetch.append(id) }
        }
        return (fetch.sorted(), unchanged)
    }

    /// 设备记录要不要传：内容（除上传时间）变了，或者离上次传过了 heartbeat（别的设备的设备页看「上次同步」）。
    static func shouldUpload(digest: String, uploadedDigest: String?, uploadedAt: Date?, now: Date, heartbeat: TimeInterval) -> Bool {
        guard digest == uploadedDigest, let uploadedAt else { return true }
        return now.timeIntervalSince(uploadedAt) > heartbeat
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

    /// 合并后的词换回常用词列表（保留本机原有的 id；同字的几条按先后各用各的 id）。
    static func words(_ items: [(key: String, value: Word)], current: [CommonWord]) -> [CommonWord] {
        var ids: [String: [UUID]] = [:]
        for word in current where !word.isReadOnly { ids[word.text, default: []].append(word.id) }
        return items.map { item in
            var id: UUID?
            if var list = ids[item.key], !list.isEmpty {
                id = list.removeFirst()
                ids[item.key] = list
            }
            return item.value.commonWord(keeping: id)
        }
    }

    /// 键盘常用语：内容是这一条的身份（KeyboardPhrase.id 就是内容）。
    static func phraseItems(_ phrases: [KeyboardPhrase]) -> [(key: String, value: KeyboardPhrase)] {
        phrases.filter { !$0.text.isEmpty }.map { (key: $0.text, value: $0) }
    }

    /// 润色、问答风格（3.1）：开着同步就同步。模糊音、双拼、键盘布局、声音振动、外观、联网方式都不同步（1.6）。
    struct StyleProfile: Codable, Equatable {
        var polishEnabled: Bool
        var answerEnabled: Bool
        var styles: [StylePreset]
        var selectedStyleID: UUID?
        var answerStyles: [StylePreset]
        var selectedAnswerStyleID: UUID?
        var searchTendency: Int?
        var pinnedStyleIDs: [UUID]
        var helpPinned: Bool
        /// 帮回「自动判断」（帮回开关方案第 5 节）：没有这个开关的版本传上来的记录里没有这一项，解出来是 nil，
        /// 写回时不改本机的值。参加合并前先用 fillingHelpAuto 补上，见那里。
        var helpAuto: Bool?

        init(settings: EnclaveSettings) {
            polishEnabled = settings.polishEnabled
            answerEnabled = settings.answerEnabled
            styles = settings.styles
            selectedStyleID = settings.selectedStyleID
            answerStyles = settings.answerStyles
            selectedAnswerStyleID = settings.selectedAnswerStyleID
            searchTendency = settings.searchTendency
            pinnedStyleIDs = settings.pinnedStyleIDs
            helpPinned = settings.helpPinned
            helpAuto = settings.helpAuto
        }

        /// 写回设置：只改上面这些，别的不动。
        func apply(to settings: inout EnclaveSettings) {
            settings.polishEnabled = polishEnabled
            settings.answerEnabled = answerEnabled
            settings.styles = styles
            settings.selectedStyleID = selectedStyleID
            settings.answerStyles = answerStyles
            settings.selectedAnswerStyleID = selectedAnswerStyleID
            settings.searchTendency = searchTendency
            settings.pinnedStyleIDs = pinnedStyleIDs
            settings.helpPinned = helpPinned
            if let helpAuto { settings.helpAuto = helpAuto }
        }
    }

    /// 风格参加合并（resolve）前补上 helpAuto（04 审查 #80 第 1 条）：
    /// - 别的设备传来的 nil 填成本机的值：那台没有这个开关，不该改这台的；不填的话，采用它那份以后记下的是 nil，
    ///   下一轮和本机的值对不上，会被当成本机改过、按现在的时间重传，盖掉那台后来改的风格。
    /// - 本机同步状态里旧的 nil（升级前存的）当开：那些版本就是开着，升级后不算本机改过；升级后关掉了照常算改过。
    static func fillingHelpAuto(local: StyleProfile, previous: Entry<StyleProfile>?, peers: [String: Entry<StyleProfile>])
        -> (previous: Entry<StyleProfile>?, peers: [String: Entry<StyleProfile>]) {
        func filled(_ entry: Entry<StyleProfile>, with value: Bool?) -> Entry<StyleProfile> {
            guard var profile = entry.value, profile.helpAuto == nil else { return entry }
            profile.helpAuto = value
            return Entry(value: profile, time: entry.time)
        }
        return (previous.map { filled($0, with: true) }, peers.mapValues { filled($0, with: local.helpAuto) })
    }

    /// 润色、问答正在用的接口（地址、模型、参数，不含 Key）。只在两台设备都开着「Key 也同步」时同步：
    /// 地址和 Key 要一起到，不然一台会拿自己的 Key 去请求另一台设的地址，Key 就发给了别家（04 审查 #75 第 2 条）。
    struct EndpointProfile: Codable, Equatable {
        /// 这份设置真正用到的 Key（04 复审 A2）：润色总要；问答只在单独设了问答接口时要。
        /// 没用到的不放进 keys，不然一台没设问答 Key、另一台设了，接口就永远对不上、永远不同步。
        static func accounts(for settings: EnclaveSettings) -> [String] {
            settings.usesAnswerEndpoint ? Keychain.endpointAccounts : [Keychain.endpointAccounts[0]]
        }

        var baseURL: String
        var model: String
        var temperature: Double
        var maxTokens: Int
        var separateAnswer: Bool
        var answerBaseURL: String
        var answerModel: String
        var answerTemperature: Double?
        var answerMaxTokens: Int?
        /// 这份配置配的 Key：账户名 → Key 的指纹（Keychain.fingerprint，没有 Key 是空字符串）。
        var keys: [String: String]

        init(settings: EnclaveSettings, keys: [String: String]) {
            baseURL = settings.baseURL
            model = settings.model
            temperature = settings.temperature
            maxTokens = settings.maxTokens
            // 没单独走问答接口时，问答那几项不算进来（04 三审第 1 条）：本机留着没用的问答地址配的是本机的问答 Key，
            // 传过去会让另一台以后打开「单独设问答接口」时拿它自己的问答 Key 去请求这个地址。
            let usesAnswer = settings.usesAnswerEndpoint
            separateAnswer = usesAnswer
            answerBaseURL = usesAnswer ? settings.answerBaseURL : ""
            answerModel = usesAnswer ? settings.answerModel : ""
            answerTemperature = usesAnswer ? settings.answerTemperature : nil
            answerMaxTokens = usesAnswer ? settings.answerMaxTokens : nil
            self.keys = keys
        }

        /// 这份配置的问答走不走另一个接口（和 EnclaveSettings.usesAnswerEndpoint 一样判断；旧版传上来的没整理过，也按这个看）。
        var usesAnswerEndpoint: Bool {
            separateAnswer && !answerBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
                && !answerModel.trimmingCharacters(in: .whitespaces).isEmpty
        }

        func apply(to settings: inout EnclaveSettings) {
            settings.baseURL = baseURL
            settings.model = model
            settings.temperature = temperature
            settings.maxTokens = maxTokens
            if usesAnswerEndpoint {
                settings.separateAnswer = true
                settings.answerBaseURL = answerBaseURL
                settings.answerModel = answerModel
                settings.answerTemperature = answerTemperature
                settings.answerMaxTokens = answerMaxTokens
            } else if settings.usesAnswerEndpoint {
                // 那台问答和润色走同一个接口：这台也不再单独走问答接口。本机的问答地址和参数留着不改，
                // 它们配的还是本机的问答 Key（这份配置的 keys 里没有问答 Key，配对表也不动）。
                settings.separateAnswer = false
            }
        }
    }

    /// 一条接口配置（「我的预设」）和它配的 Key 的指纹。逐条合并（按 id），和接口一样只在 Key 也同步时同步。
    struct SyncedAPI: Codable, Equatable {
        var api: SavedAPI
        var key: String

        static func account(_ id: String) -> String { "apiKey.saved.\(id)" }
    }

    static func apiItems(_ apis: [SavedAPI], keys: (String) -> String) -> [(key: String, value: SyncedAPI)] {
        apis.map { api in
            let id = api.id.uuidString
            return (key: id, value: SyncedAPI(api: api, key: keys(SyncedAPI.account(id))))
        }
    }

    /// 别的设备的配置能不能用到本机：它配的每个 Key，本机钥匙串里现在的那个都要对得上。
    /// iCloud 钥匙串和 CloudKit 各自同步，谁先到不一定：地址先到、Key 还没到时先不用，等下次同步。
    /// 那台没配 Key（自建服务）的不用等：本机配上「没有」，也不会拿本机的 Key 去请求那个地址。
    static func keysMatch(_ keys: [String: String], current: (String) -> String) -> Bool {
        keys.allSatisfy { keyMatches($0.value, current: current($0.key)) }
    }

    static func keyMatches(_ expected: String, current: String) -> Bool {
        expected.isEmpty || current == expected
    }

    /// 一台设备在 iCloud 里的全部内容（除了拼音快照的分块），整份放在 CloudKit 的加密字段里。
    struct DevicePayload: Codable, Equatable {
        /// 格式版本：看到比自己新的就跳过这台设备，不报错（1.12）。2：风格、接口、接口配置分开。
        static let currentFormat = 2

        var format: Int
        /// 设备页上的名字（用户可以改）和型号（UIDevice.model：iPhone、iPad），型号决定图标。旧记录没有型号。
        var deviceName: String
        var deviceModel: String?
        var appVersion: String
        /// 上传时间：别的设备的设备页当「上次同步」。内容没变时不重传（04 审查 #75 第 3 条），但至少一天传一次。
        var updatedAt: Date
        /// 清除学到的词的代数（1.5）。
        var generation: Int
        var words: Table<Word>
        var phrases: Table<KeyboardPhrase>
        /// 带内置 Key 的包不同步这三项，是 nil；接口和接口配置只在这台开着「Key 也同步」时才有。
        var styles: Entry<StyleProfile>?
        var endpoint: Entry<EndpointProfile>?
        var apis: Table<SyncedAPI>?
        /// 拼音快照：压缩后分几块、压缩后整份的 SHA-256。没有学到的词时 0 块。
        var snapshotChunks: Int
        var snapshotHash: String

        /// 除了上传时间以外的内容：和上次传的一样就不传。
        var contentDigest: String {
            var copy = self
            copy.updatedAt = initialTime
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard let data = try? encoder.encode(copy) else { return UUID().uuidString }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}
