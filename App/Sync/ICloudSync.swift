import CloudKit
import Foundation
import UIKit

// iCloud 同步（specs/icloud-sync/iCloud同步方案.md 第 2 版）。
//
// - 只在主 App 里跑，键盘不碰 iCloud、不联网。
// - 全部内容放在 CloudKit 私有库的加密字段里（端到端加密，Apple 和我们都读不到）；
//   不加密的只有记录编号（随机生成的设备编号）和 CloudKit 自带的元数据（记录类型、时间、大小）。没有退回不加密上传的路。
// - 每台设备只写自己的记录：一条 Device（DevicePayload），加上拼音快照的几块 SnapshotChunk。
// - 拼音词库用 LearnedWords 的副本做法（#74）合并，App 永远不直接打开键盘在用的那份。
// - 界面还没做（等 02 的稿子）：开关默认关，关着时这里什么都不做。

extension Notification.Name {
    /// 同步把别的设备的改动写进了本机（设置、接口配置、常用词、常用语）。开着的页面要重新读，不然下次保存会把它们冲掉，
    /// 冲掉的部分在下次同步时会被当成本机删了，删到所有设备上。
    static let enclaveSyncDidApply = Notification.Name("EnclaveSyncDidApply")
}

/// 上一次同步的结果，给以后的界面用（同步时间、键盘正在用、没登录 iCloud……）。
struct ICloudSyncStatus: Codable, Equatable {
    enum Result: String, Codable {
        case ok
        /// 设置、常用词同步了，拼音词库这次没合并（键盘正在用），下次再来。
        case keyboardBusy
        case noAccount
        /// 换了 Apple ID：同步已经关掉，要用户重新打开（1.12）。
        case accountChanged
        /// iCloud 里有更新版本 App 写的数据，这台看不懂，跳过了那台设备。
        case newerFormat
        case failed
    }

    var result: Result
    var at: Date
    var detail: String?
}

enum ICloudSync {
    /// 这个包有没有 iCloud 能力。免费 Apple ID 签名拿不到 iCloud，Local.xcconfig 里写 ICLOUD_SYNC = NO，这时是 false。
    /// 没有能力时不能碰 CKContainer（会闪退），也不显示同步的入口。
    static var isAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "EnclaveICloudSync") as? String) == "YES" && containerID != nil
    }

    static var containerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "EnclaveCloudContainer") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    private static let enabledKey = "sync.enabled"
    private static let statusKey = "sync.status"

    /// 同步开关（每台设备自己的，不跟着同步走）。默认关。
    static var isEnabled: Bool {
        get { isAvailable && SharedStorage.defaults.bool(forKey: enabledKey) }
        set { SharedStorage.defaults.set(newValue, forKey: enabledKey) }
    }

    static var lastStatus: ICloudSyncStatus? {
        get {
            guard let data = UserDefaults.standard.data(forKey: statusKey) else { return nil }
            return try? JSONDecoder().decode(ICloudSyncStatus.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: statusKey)
            } else {
                UserDefaults.standard.removeObject(forKey: statusKey)
            }
        }
    }

    /// 同步一次。打开 App、回到前台、后台任务、收到变化推送、点「立即同步」时调。同时只跑一次，后来的等前面那次的结果。
    /// minimumInterval：离上次成功同步不到这么久就不跑（回到前台很频繁）；「立即同步」传 0。
    @discardableResult
    static func syncNow(minimumInterval: TimeInterval = 0) async -> ICloudSyncStatus? {
        guard isEnabled else { return nil }
        if minimumInterval > 0, let last = lastStatus, last.result == .ok,
           Date().timeIntervalSince(last.at) < minimumInterval {
            return last
        }
        return await ICloudSyncEngine.shared.run()
    }

    /// 隐私页「清除学习记录」之后调（1.5）：开着同步时就是所有设备一起清。清除代数加一，本机的旧快照不再上传，
    /// 下一次同步时删掉 iCloud 里本机的快照，别的设备看到更大的代数也清掉自己的。
    static func noteLearningCleared() {
        guard isEnabled else { return }
        ICloudSyncEngine.bumpGeneration()
        Task { await syncNow() }
    }
}

/// 本机的同步状态：设备编号、上次同步完的表、上传过的快照、CloudKit 的变化令牌。
/// 存在 Application Support/ICloudSync/，不进整机备份：从备份恢复的新手机从头来，不会和旧手机用同一个设备编号（1.2）。
struct ICloudSyncState: Codable {
    var deviceID: String
    /// identifierForVendor：不跟着备份走；和存的对不上就是换了设备（「快速开始」迁移等），重新生成设备编号。
    var vendorID: String?
    /// iCloud 账户（CloudKit 的用户记录名）：变了就是换了 Apple ID。
    var userRecordName: String?
    var generation = 0
    var words: SyncMerge.Table<SyncMerge.Word>?
    var phrases: SyncMerge.Table<KeyboardPhrase>?
    var ai: SyncMerge.Entry<SyncMerge.AIProfile>?
    /// 已经上传的拼音快照：块数、校验、属于哪个清除代数。代数对不上的快照不再出现在设备记录里。
    var snapshotChunks = 0
    var snapshotHash = ""
    var snapshotGeneration = 0
    var changeToken: Data?
    var zoneReady = false
    var subscribed = false

    init(vendorID: String?) {
        deviceID = UUID().uuidString
        self.vendorID = vendorID
    }
}

actor ICloudSyncEngine {
    static let shared = ICloudSyncEngine()

    private static let zoneID = CKRecordZone.ID(zoneName: "EnclaveSync", ownerName: CKCurrentUserDefaultName)
    private static let deviceType = "Device"
    private static let chunkType = "SnapshotChunk"
    /// 一块的大小：CloudKit 一条记录最多 1 MB，加密字段还有额外开销，留足余量。
    private static let chunkSize = 700_000

    private var running: Task<ICloudSyncStatus, Never>?

    func run() async -> ICloudSyncStatus {
        if let running { return await running.value }
        let task = Task { await self.perform() }
        running = task
        let status = await task.value
        running = nil
        ICloudSync.lastStatus = status
        return status
    }

    // MARK: 本机状态的文件

    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ICloudSync", isDirectory: true)
    }

    private static var stateURL: URL? { folder?.appendingPathComponent("state.json") }
    private static var peersFolder: URL? { folder?.appendingPathComponent("peers", isDirectory: true) }

    private static let stateLock = NSLock()

    static func loadState() -> ICloudSyncState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ICloudSyncState.self, from: data)
    }

    static func saveState(_ state: ICloudSyncState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard var dir = Self.folder, let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        try? data.write(to: url, options: .atomic)
    }

    /// 清除学习记录时：代数取见过的最大值加一（别的设备的代数在下次同步时还会再比一次）。
    static func bumpGeneration() {
        guard var state = loadState() else { return }
        let peers = PeerCache.payloads(excluding: state.deviceID).values.map(\.generation)
        state.generation = SyncMerge.generation(local: state.generation, peers: peers) + 1
        saveState(state)
    }

    // MARK: 一次同步

    private func perform() async -> ICloudSyncStatus {
        guard ICloudSync.isEnabled, let containerID = ICloudSync.containerID else {
            return ICloudSyncStatus(result: .failed, at: Date(), detail: "off")
        }
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        do {
            guard try await container.accountStatus() == .available else {
                return ICloudSyncStatus(result: .noAccount, at: Date(), detail: nil)
            }
            guard let prepared = try await prepareState(container) else {
                return ICloudSyncStatus(result: .accountChanged, at: Date(), detail: nil)
            }
            var working = prepared
            do {
                try await ensureZone(database, &working)
                try await fetchChanges(database, &working)
            } catch let error as CKError where error.code == .changeTokenExpired || error.code == .zoneNotFound || error.code == .userDeletedZone {
                // 令牌过期、或者用户在系统设置里删过 iCloud 里的数据：从头再拉一次。
                working.changeToken = nil
                working.zoneReady = false
                working.snapshotHash = ""
                working.snapshotChunks = 0
                PeerCache.clear()
                try await ensureZone(database, &working)
                try await fetchChanges(database, &working)
            }
            Self.saveState(working)
            return try await exchange(database, &working)
        } catch {
            return ICloudSyncStatus(result: .failed, at: Date(), detail: String(describing: error))
        }
    }

    /// 读本机状态，核对设备和账户。换了 Apple ID 时关掉同步、清掉本机状态，返回 nil。
    private func prepareState(_ container: CKContainer) async throws -> ICloudSyncState? {
        let vendor = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        var state = Self.loadState() ?? ICloudSyncState(vendorID: vendor)
        if state.vendorID != vendor {
            state = ICloudSyncState(vendorID: vendor)
            PeerCache.clear()
        }
        let user = try await container.userRecordID().recordName
        if let old = state.userRecordName, old != user {
            ICloudSync.isEnabled = false
            PeerCache.clear()
            if let url = Self.stateURL { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        state.userRecordName = user
        Self.saveState(state)
        return state
    }

    private func ensureZone(_ database: CKDatabase, _ state: inout ICloudSyncState) async throws {
        if !state.zoneReady {
            let (saved, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
            if case .failure(let error) = saved[Self.zoneID] { throw error }
            state.zoneReady = true
        }
        if !state.subscribed {
            // 别的设备改了东西时发静默推送，App 在后台被唤醒同步一次（系统会限流，关了后台 App 刷新时不唤醒）。
            let subscription = CKDatabaseSubscription(subscriptionID: "enclave-sync")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
            state.subscribed = true
        }
    }

    /// 拉别的设备的改动，存进本机缓存。
    private func fetchChanges(_ database: CKDatabase, _ state: inout ICloudSyncState) async throws {
        var token = state.changeToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                PeerCache.store(modification.record, own: state.deviceID)
            }
            for deletion in changes.deletions {
                PeerCache.remove(deletion.recordID, own: state.deviceID)
            }
            token = changes.changeToken
            more = changes.moreComing
        }
        if let token {
            state.changeToken = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        }
    }

    /// 合并、写回本机、上传本机这份。
    private func exchange(_ database: CKDatabase, _ state: inout ICloudSyncState) async throws -> ICloudSyncStatus {
        let now = Date()
        var peers = PeerCache.payloads(excluding: state.deviceID)
        var skippedNewer = false
        for (id, payload) in peers where payload.format > SyncMerge.DevicePayload.currentFormat {
            peers[id] = nil
            skippedNewer = true
        }

        // 1. 拼音词库：先看要不要跟着别的设备清除，再合并。
        var keyboardBusy = false
        var snapshot: String?
        let maxGeneration = SyncMerge.generation(local: state.generation, peers: peers.values.map(\.generation))
        if maxGeneration > state.generation {
            if await Self.blocking({ LearnedWords.clearForSync() }) {
                state.generation = maxGeneration
            } else {
                keyboardBusy = true
            }
            Self.saveState(state)
        }
        if !keyboardBusy {
            var texts: [String: String] = [:]
            for (id, payload) in peers where payload.generation == state.generation {
                if let text = PeerCache.snapshot(id: id, payload: payload) { texts[id] = text }
            }
            let peerTexts = texts
            switch await Self.blocking({ LearnedWords.sync(peers: peerTexts) }) {
            case .merged(let text): snapshot = text
            case .busy: keyboardBusy = true
            case .failed: break
            }
        }

        // 2. 常用词、常用语、AI 接口和风格。
        let syncsAI = !BuiltinAPI.available
        let local = await MainActor.run { LocalData.read() }
        let sortedPeers = peers.sorted { $0.key < $1.key }

        // 合并时按设备编号排好序（本机也在里面），每台设备算出来的结果一样。
        let order = ([state.deviceID] + sortedPeers.map { $0.key }).sorted()

        let wordItems = SyncMerge.wordItems(local.words)
        let myWords = SyncMerge.observe(current: wordItems, previous: state.words, now: now)
        var wordTables: [SyncMerge.Table<SyncMerge.Word>] = []
        for id in order { wordTables.append(id == state.deviceID ? myWords : peers[id]?.words ?? [:]) }
        let mergedWords = SyncMerge.pruned(SyncMerge.merge(wordTables), now: now)
        let mergedWordItems = SyncMerge.apply(mergedWords, to: wordItems)
        let newWords = SyncMerge.words(mergedWordItems, current: local.words) + local.words.filter { $0.isReadOnly }

        let phraseItems = SyncMerge.phraseItems(local.phrases)
        let myPhrases = SyncMerge.observe(current: phraseItems, previous: state.phrases, now: now)
        var phraseTables: [SyncMerge.Table<KeyboardPhrase>] = []
        for id in order { phraseTables.append(id == state.deviceID ? myPhrases : peers[id]?.phrases ?? [:]) }
        let mergedPhrases = SyncMerge.pruned(SyncMerge.merge(phraseTables), now: now)
        let newPhrases = SyncMerge.apply(mergedPhrases, to: phraseItems).map { $0.value }

        var aiEntry: SyncMerge.Entry<SyncMerge.AIProfile>?
        var newAI: SyncMerge.AIProfile?
        if syncsAI {
            let profile = SyncMerge.AIProfile(settings: local.settings, savedAPIs: local.savedAPIs)
            let mine = SyncMerge.observeValue(profile, previous: state.ai, now: now)
            let winner = SyncMerge.latest([mine] + sortedPeers.compactMap { $0.value.ai }) ?? mine
            aiEntry = winner
            if let value = winner.value, value != profile { newAI = value }
        }

        let wordsChanged = newWords != local.words
        let phrasesChanged = newPhrases != local.phrases
        let aiToApply = newAI
        if wordsChanged || phrasesChanged || aiToApply != nil {
            await MainActor.run {
                if wordsChanged { CommonWordStore.save(newWords) }
                if phrasesChanged { CommonWordStore.keyboardPhrases = newPhrases }
                if let aiToApply {
                    var settings = SettingsStore.load()
                    aiToApply.apply(to: &settings)
                    SettingsStore.save(settings)
                    SavedAPIStore.replaceAll(aiToApply.savedAPIs)
                }
                NotificationCenter.default.post(name: .enclaveSyncDidApply, object: nil)
            }
        }
        // 写回本机后马上记下来：上传失败时，下次也不会把刚合并进来的当成本机的新改动。
        state.words = mergedWords
        state.phrases = mergedPhrases
        state.ai = aiEntry
        Self.saveState(state)

        // 3. 上传本机这份：先传快照的块，再传设备记录，最后删掉多出来的旧块。
        let oldChunks = state.snapshotChunks
        if let snapshot {
            let packed = try SyncMerge.packSnapshot(snapshot, chunkSize: Self.chunkSize)
            if packed.hash != state.snapshotHash || state.snapshotGeneration != state.generation {
                for (index, chunk) in packed.chunks.enumerated() {
                    let record = CKRecord(recordType: Self.chunkType, recordID: Self.chunkID(state.deviceID, index))
                    record.encryptedValues["data"] = chunk
                    try await Self.save([record], in: database)
                }
                state.snapshotChunks = packed.chunks.count
                state.snapshotHash = packed.hash
                state.snapshotGeneration = state.generation
            }
        }
        // 快照不是当前代数的（刚清除过、还没传新的）：设备记录里不带快照，别的设备就不会合并清除前的词。
        let currentSnapshot = state.snapshotGeneration == state.generation
        let deviceName = await MainActor.run { UIDevice.current.model }
        let payload = SyncMerge.DevicePayload(
            format: SyncMerge.DevicePayload.currentFormat,
            deviceName: deviceName,
            appVersion: Self.appVersion,
            updatedAt: now,
            generation: state.generation,
            words: mergedWords,
            phrases: mergedPhrases,
            ai: aiEntry,
            snapshotChunks: currentSnapshot ? state.snapshotChunks : 0,
            snapshotHash: currentSnapshot ? state.snapshotHash : "")
        let device = CKRecord(recordType: Self.deviceType, recordID: Self.deviceID(state.deviceID))
        device.encryptedValues["payload"] = try JSONEncoder().encode(payload)
        try await Self.save([device], in: database)
        let keep = currentSnapshot ? state.snapshotChunks : 0
        if oldChunks > keep {
            let stale = (keep..<oldChunks).map { Self.chunkID(state.deviceID, $0) }
            _ = try? await database.modifyRecords(saving: [], deleting: stale)
        }
        if !currentSnapshot {
            state.snapshotChunks = 0
            state.snapshotHash = ""
        }
        Self.saveState(state)

        if keyboardBusy { return ICloudSyncStatus(result: .keyboardBusy, at: now, detail: nil) }
        if skippedNewer { return ICloudSyncStatus(result: .newerFormat, at: now, detail: nil) }
        return ICloudSyncStatus(result: .ok, at: now, detail: nil)
    }

    // MARK: 工具

    private static func deviceID(_ id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "device-\(id)", zoneID: zoneID)
    }

    private static func chunkID(_ id: String, _ index: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "snapshot-\(id)-\(index)", zoneID: zoneID)
    }

    /// 只有本机写自己的记录，用 allKeys 直接覆盖，不用先取服务器上的版本。每条的结果都要看，出错就整次算失败。
    private static func save(_ records: [CKRecord], in database: CKDatabase) async throws {
        let (saved, _) = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: true)
        for (_, result) in saved {
            if case .failure(let error) = result { throw error }
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let label = Bundle.main.object(forInfoDictionaryKey: "EnclaveDevLabel") as? String ?? ""
        return label.isEmpty || label.contains("$(") ? version : label
    }

    /// 拼音词库的合并会阻塞几百毫秒到几秒，放到别的线程，不占着 Swift 并发的线程。
    private static func blocking<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: body()) }
        }
    }
}

/// 本机这边要同步的数据（在主线程读）。
private struct LocalData {
    var words: [CommonWord]
    var phrases: [KeyboardPhrase]
    var settings: EnclaveSettings
    var savedAPIs: [SavedAPI]

    static func read() -> LocalData {
        LocalData(words: CommonWordStore.load(), phrases: CommonWordStore.keyboardPhrases,
                  settings: SettingsStore.load(), savedAPIs: SavedAPIStore.all)
    }
}

/// 别的设备的记录在本机的缓存（Application Support/ICloudSync/peers/，不进整机备份）：
/// 设备记录存成 <编号>.json，快照的块存成 <编号>.chunk.<序号>。拉改动时只拉变了的，所以要缓存。
enum PeerCache {
    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ICloudSync/peers", isDirectory: true)
    }

    private static func parse(_ recordName: String) -> (kind: String, device: String, index: Int?)? {
        if recordName.hasPrefix("device-") {
            return ("device", String(recordName.dropFirst("device-".count)), nil)
        }
        // snapshot-<设备编号>-<序号>：设备编号是 UUID，自己带横线，序号取最后一段。
        if recordName.hasPrefix("snapshot-"), let dash = recordName.lastIndex(of: "-"),
           let index = Int(recordName[recordName.index(after: dash)...]) {
            let device = String(recordName[recordName.index(recordName.startIndex, offsetBy: "snapshot-".count)..<dash])
            return ("snapshot", device, index)
        }
        return nil
    }

    private static func file(_ device: String, _ index: Int?) -> URL? {
        folder?.appendingPathComponent(index.map { "\(device).chunk.\($0)" } ?? "\(device).json")
    }

    static func store(_ record: CKRecord, own: String) {
        guard let parsed = parse(record.recordID.recordName), parsed.device != own,
              let url = file(parsed.device, parsed.index), let folder else { return }
        let key = parsed.kind == "device" ? "payload" : "data"
        guard let data = record.encryptedValues[key] as? Data else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func remove(_ id: CKRecord.ID, own: String) {
        guard let parsed = parse(id.recordName), parsed.device != own, let url = file(parsed.device, parsed.index) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clear() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// 别的设备的设备记录（设备编号 → 内容）。读不懂的跳过。
    static func payloads(excluding own: String) -> [String: SyncMerge.DevicePayload] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [:] }
        var result: [String: SyncMerge.DevicePayload] = [:]
        for name in names where name.hasSuffix(".json") {
            let device = String(name.dropLast(".json".count))
            guard device != own, let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let payload = try? JSONDecoder().decode(SyncMerge.DevicePayload.self, from: data) else { continue }
            result[device] = payload
        }
        return result
    }

    /// 拼出一台设备的快照；块还没收齐、或者和设备记录对不上（那台设备正传到一半）时为 nil，这次先不合并它。
    static func snapshot(id: String, payload: SyncMerge.DevicePayload) -> String? {
        var chunks: [Data] = []
        for index in 0..<payload.snapshotChunks {
            guard let url = file(id, index), let data = try? Data(contentsOf: url) else { return nil }
            chunks.append(data)
        }
        return SyncMerge.unpackSnapshot(chunks, hash: payload.snapshotHash)
    }
}
