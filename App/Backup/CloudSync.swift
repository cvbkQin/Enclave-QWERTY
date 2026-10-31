import CloudKit
import Foundation
import UIKit

// 备份与恢复第二步：iCloud 自动同步（B3，设计 design/backup/v2/BV1、BV5、BV6）。
// 用 CloudKit 私有数据库（用户自己的 iCloud，开发者看不到），区域「Enclave」里每项一条记录（recordName = 项目名），
// 内容放在 payload 附件里，格式和备份文件里那一项一样。同步只在 App 里做（打开 App、回到前台、开着时每 2 分钟），
// 键盘只读写 App Group。同步哪几项按「备份内容」的开关；接口 Key、剪贴板记录、购买和试用永远不同步。
//
// 合并：本机留一份上次同步完两边一致的内容（base），三方合并：
// 常用词、键盘常用语、AI 历史、风格按条合并（两边加的都留、一边删的就删、两边都有时谁改过用谁的）；
// 设置整块，只有一边改过就用那边，两边都改了用本机的；学到的词交给拼音引擎合并（两边都有的词取权重大的）。
// 只在 Info.plist 的 EnclaveICloud 有值（构建时开了 iCloud 能力）时才碰 CloudKit：没有 iCloud 权限时一调就崩。

@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    enum Status: Equatable {
        case off, syncing, synced(Date), noAccount, failed(String)
    }

    /// 第一次打开同步时 iCloud 里已经有数据（BV5）。
    struct RemoteSummary: Identifiable {
        let id = UUID()
        var device: String
        var date: Date
        var commonWords: Int?
        var learnedWords: Int?
    }

    enum FirstChoice { case merge, useCloud, useLocal }

    @Published private(set) var status: Status = .off
    @Published var firstSync: RemoteSummary?
    /// 同步改了本机的设置或风格：App 里内存中的设置要重新读（EnclaveApp 盯着它）。
    @Published private(set) var settingsRevision = 0

    private static let enabledKey = "icloud.enabled"
    private static let lastSyncedKey = "icloud.lastSynced"
    private var running = false
    private var timer: Timer?

    /// 构建时开了 iCloud（ENCLAVE_ICLOUD）才有：iCloud.<Bundle ID>。
    nonisolated static var containerID: String? {
        guard let flag = Bundle.main.object(forInfoDictionaryKey: "EnclaveICloud") as? String, !flag.isEmpty,
              let bundle = Bundle.main.bundleIdentifier else { return nil }
        return "iCloud." + bundle
    }

    nonisolated static var isAvailable: Bool { containerID != nil }

    var isEnabled: Bool {
        get { Self.isAvailable && SharedStorage.defaults.bool(forKey: Self.enabledKey) }
        set {
            SharedStorage.defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
        }
    }

    static var lastSynced: Date? {
        get { SharedStorage.defaults.object(forKey: lastSyncedKey) as? Date }
        set { SharedStorage.defaults.set(newValue, forKey: lastSyncedKey) }
    }

    private init() {
        if let date = Self.lastSynced, isEnabled { status = .synced(date) }
    }

    // MARK: - 开关和时机

    func setEnabled(_ on: Bool) {
        isEnabled = on
        if on {
            Task { await sync() }
            startTimer()
        } else {
            timer?.invalidate()
            status = .off
        }
    }

    /// App 回到前台：同步一次，之后开着时每 2 分钟一次。
    func appBecameActive() {
        guard isEnabled else { return }
        Task { await sync() }
        startTimer()
    }

    func appResignedActive() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in await CloudSync.shared.sync() }
        }
    }

    // MARK: - 同步

    /// 同步一次。choice 是第一次同步时用户在 BV5 里选的。
    func sync(choice: FirstChoice? = nil) async {
        guard isEnabled, !running, let id = Self.containerID else { return }
        running = true
        defer { running = false }
        status = .syncing
        let container = CKContainer(identifier: id)
        do {
            guard try await container.accountStatus() == .available else {
                status = .noAccount
                return
            }
            let engine = CloudSyncEngine(db: container.privateCloudDatabase, device: UIDevice.current.name,
                                         app: AboutView.devLabel ?? AboutView.version)
            try await engine.ensureZone()
            let items = BackupItem.allCases.filter { BackupPrefs.items.contains($0) }
            // 第一次（本机没有任何 base）而 iCloud 里已经有东西：先问用户（BV5）。
            if choice == nil, !SyncBase.hasAny {
                let records = try await engine.fetch(BackupItem.allCases)
                if !records.isEmpty {
                    firstSync = Self.summary(records)
                    status = .off
                    return
                }
            }
            for item in items {
                try await syncItem(item, engine: engine, choice: choice)
            }
            let now = Date()
            Self.lastSynced = now
            status = .synced(now)
        } catch {
            status = Self.status(for: error)
        }
    }

    /// 用户在 BV5 里选了：取消就关掉同步。
    func resolveFirstSync(_ choice: FirstChoice?) {
        firstSync = nil
        guard let choice else {
            setEnabled(false)
            return
        }
        Task { await sync(choice: choice) }
    }

    /// 「设置 › 隐私 › 删除 iCloud 里的数据」：删掉整个区域，关掉同步。
    func deleteCloudData() async throws {
        guard let id = Self.containerID else { return }
        setEnabled(false)
        let db = CKContainer(identifier: id).privateCloudDatabase
        do {
            _ = try await db.deleteRecordZone(withID: CloudSyncEngine.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 本来就没有。
        }
        SyncBase.clearAll()
        Self.lastSynced = nil
    }

    private static func status(for error: Error) -> Status {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return .noAccount
            case .networkUnavailable, .networkFailure:
                return .failed(L("没有网络，连上后会自动同步", "No connection. Syncs again when you're online.", "オフラインです。接続すると自動で同期します"))
            case .quotaExceeded:
                return .failed(L("iCloud 空间不够了", "iCloud storage is full", "iCloud の容量が足りません"))
            default: break
            }
        }
        return .failed(L("同步出错：", "Sync error: ", "同期エラー：") + error.localizedDescription)
    }

    /// 给弹窗用的一句话（删除 iCloud 数据失败时）。
    static func message(for error: Error) -> String {
        switch status(for: error) {
        case .noAccount: return L("这台 iPhone 没有登录 iCloud", "This iPhone isn't signed in to iCloud", "この iPhone は iCloud にサインインしていません")
        case .failed(let text): return text
        default: return error.localizedDescription
        }
    }

    private static func summary(_ records: [BackupItem: CKRecord]) -> RemoteSummary {
        let newest = records.values.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        return RemoteSummary(device: newest?["device"] as? String ?? "iCloud",
                             date: newest?.modificationDate ?? Date(),
                             commonWords: (records[.commonWords]?["count"] as? NSNumber)?.intValue,
                             learnedWords: (records[.learnedWords]?["count"] as? NSNumber)?.intValue)
    }

    /// 一项：取 iCloud 里的 → 和本机的三方合并 → 改本机 → 有变化再传上去 → 记下 base。别的设备同时改了（记录版本对不上）就重来，最多三次。
    private func syncItem(_ item: BackupItem, engine: CloudSyncEngine, choice: FirstChoice?) async throws {
        for attempt in 0..<3 {
            let record = try await engine.fetch([item])[item]
            do {
                switch item {
                case .learnedWords: try await syncLearned(record: record, engine: engine, choice: choice)
                default: try await syncValue(item, record: record, engine: engine, choice: choice)
                }
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                continue
            }
        }
    }

    // MARK: - 每一项怎么合并

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// 设置、风格、常用词、AI 历史：本机算出合并结果、写回本机，和 iCloud 不一样时传上去，最后记下 base。
    private func syncValue(_ item: BackupItem, record: CKRecord?, engine: CloudSyncEngine, choice: FirstChoice?) async throws {
        let remote = record.flatMap(CloudSyncEngine.payload)
        let base = SyncBase.get(item)
        let merged: Data
        let count: Int
        switch item {
        case .settings:
            let local = try BackupService.settingsPayload()
            var result: Data
            if let remote {
                switch choice {
                case .useCloud?: result = remote
                case .useLocal?: result = local
                default: result = BackupMerge.threeWayValue(base: base, local: local, remote: remote, both: { mine, _ in mine })
                }
            } else {
                result = local
            }
            if result != local, let object = try JSONSerialization.jsonObject(with: result) as? [String: Any] {
                try BackupService.applySettingsPayload(object)
                settingsRevision += 1
                result = try BackupService.settingsPayload()
            }
            merged = result
            count = 1
        case .styles:
            let settings = SettingsStore.load()
            let local = BackupService.StylesFile(polish: .init(list: settings.styles, selectedID: settings.selectedStyleID),
                                                 answer: .init(list: settings.answerStyles, selectedID: settings.selectedAnswerStyleID))
            let theirs = try remote.map { try Self.decoder.decode(BackupService.StylesFile.self, from: $0) }
            let old = base.flatMap { try? Self.decoder.decode(BackupService.StylesFile.self, from: $0) }
            var result = local
            if let theirs {
                switch choice {
                case .useCloud?: result = theirs
                case .useLocal?: result = local
                default:
                    result = BackupService.StylesFile(polish: Self.mergeStyles(base: old?.polish, local: local.polish, remote: theirs.polish),
                                                      answer: Self.mergeStyles(base: old?.answer, local: local.answer, remote: theirs.answer))
                }
            }
            if result != local {
                var settings = SettingsStore.load()
                settings.styles = result.polish.list
                settings.selectedStyleID = result.polish.selectedID
                settings.answerStyles = result.answer.list
                settings.selectedAnswerStyleID = result.answer.selectedID
                SettingsStore.save(settings)
                settingsRevision += 1
            }
            merged = try Self.encoder.encode(result)
            count = result.polish.list.count + result.answer.list.count
        case .commonWords:
            let local = BackupService.CommonWordsFile(words: CommonWordStore.load().filter { !$0.isReadOnly }, keyboardTexts: CommonWordStore.keyboardTexts)
            let theirs = try remote.map { try Self.decoder.decode(BackupService.CommonWordsFile.self, from: $0) }
            let old = base.flatMap { try? Self.decoder.decode(BackupService.CommonWordsFile.self, from: $0) }
            var result = local
            if let theirs {
                switch choice {
                case .useCloud?: result = theirs
                case .useLocal?: result = local
                default:
                    result = BackupService.CommonWordsFile(
                        words: BackupMerge.threeWay(base: old?.words, local: local.words, remote: theirs.words, key: \.text),
                        keyboardTexts: BackupMerge.threeWay(base: old?.keyboardTexts, local: local.keyboardTexts, remote: theirs.keyboardTexts, key: { $0 }))
                }
            }
            if result.words != local.words { CommonWordStore.save(result.words) }
            if result.keyboardTexts != local.keyboardTexts { CommonWordStore.keyboardTexts = result.keyboardTexts }
            merged = try Self.encoder.encode(result)
            count = result.words.count
        case .history:
            let local = AIHistory.load()
            let theirs = try remote.map { try Self.decoder.decode([AIHistoryEntry].self, from: $0) }
            let old = base.flatMap { try? Self.decoder.decode([AIHistoryEntry].self, from: $0) }
            var result = local
            if let theirs {
                switch choice {
                case .useCloud?: result = theirs
                case .useLocal?: result = local
                default: result = BackupMerge.threeWay(base: old, local: local, remote: theirs, key: \.id)
                }
            }
            result = Array(result.sorted { $0.date > $1.date }.prefix(AIHistory.maxEntries))
            if result != local { AIHistory.replaceAll(result) }
            merged = try Self.encoder.encode(result)
            count = result.count
        case .learnedWords:
            return
        }
        if merged != remote {
            try await engine.save(item, data: merged, count: count, over: record)
        }
        SyncBase.set(item, merged)
    }

    /// 风格按名字合并；默认那条也按名字认（两台设备上同名的风格 id 不一样）。
    private static func mergeStyles(base: BackupMerge.Styles?, local: BackupMerge.Styles, remote: BackupMerge.Styles) -> BackupMerge.Styles {
        let list = BackupMerge.threeWay(base: base?.list, local: local.list, remote: remote.list, key: \.name)
        func name(_ styles: BackupMerge.Styles?) -> String? {
            guard let styles, let id = styles.selectedID else { return nil }
            return styles.list.first { $0.id == id }?.name
        }
        let selectedName = BackupMerge.threeWayValue(base: name(base), local: name(local), remote: name(remote), both: { mine, _ in mine })
        return BackupMerge.Styles(list: list, selectedID: list.first { $0.name == selectedName }?.id ?? (list.contains { $0.id == local.selectedID } ? local.selectedID : nil))
    }

    /// 学到的词：iCloud 那份变过（记录版本和上次不同）就合并进来，再把本机的导出、内容变了才传。键盘正占着词库时这次先跳过。
    private func syncLearned(record: CKRecord?, engine: CloudSyncEngine, choice: FirstChoice?) async throws {
        let lastTag = SyncBase.learnedTag
        let remote = record.flatMap(CloudSyncEngine.payload).map { String(decoding: $0, as: UTF8.self) }
        let importRemote = remote != nil && choice != .useLocal && record?.recordChangeTag != lastTag
        let replace = choice == .useCloud
        let snapshot: String? = await Task.detached { () -> String? in
            guard !LearnedWords.isBusy else { return nil }
            if importRemote, let remote { _ = LearnedWords.importSnapshot(remote, replace: replace) }
            return LearnedWords.snapshot()
        }.value
        guard let snapshot else { return }
        let hash = SyncBase.contentHash(snapshot)
        if record == nil || hash != SyncBase.learnedHash || (remote.map(SyncBase.contentHash) != hash) {
            let saved = try await engine.save(.learnedWords, data: Data(snapshot.utf8), count: BackupMerge.learnedCount(snapshot), over: record)
            SyncBase.learnedTag = saved.recordChangeTag
        } else {
            SyncBase.learnedTag = record?.recordChangeTag
        }
        SyncBase.learnedHash = hash
        SyncBase.set(.learnedWords, Data(hash.utf8))
    }
}

/// 和 CloudKit 打交道的那几步。
struct CloudSyncEngine {
    static let zoneID = CKRecordZone.ID(zoneName: "Enclave", ownerName: CKCurrentUserDefaultName)
    static let recordType = "Item"

    let db: CKDatabase
    let device: String
    let app: String

    func recordID(_ item: BackupItem) -> CKRecord.ID {
        CKRecord.ID(recordName: item.rawValue, zoneID: Self.zoneID)
    }

    func ensureZone() async throws {
        _ = try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
    }

    /// 取这几项的记录；iCloud 里没有的不在结果里。
    func fetch(_ items: [BackupItem]) async throws -> [BackupItem: CKRecord] {
        let results = try await db.records(for: items.map(recordID))
        var records: [BackupItem: CKRecord] = [:]
        for item in items {
            switch results[recordID(item)] {
            case .success(let record)?: records[item] = record
            case .failure(let error)?:
                if let error = error as? CKError, error.code == .unknownItem { continue }
                throw error
            case nil: continue
            }
        }
        return records
    }

    static func payload(_ record: CKRecord) -> Data? {
        (record["payload"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
    }

    /// 存一项。over 是刚取到的那条（带着版本号）：别的设备在这之间改过，CloudKit 会拒绝（serverRecordChanged），调用方重来。
    @discardableResult
    func save(_ item: BackupItem, data: Data, count: Int, over existing: CKRecord?) async throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: recordID(item))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-upload", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString)
        try data.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        record["device"] = device as NSString
        record["app"] = app as NSString
        record["count"] = NSNumber(value: count)
        record["format"] = NSNumber(value: BackupManifest.currentFormat)
        let (results, _) = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        switch results[record.recordID] {
        case .success(let saved)?: return saved
        case .failure(let error)?: throw error
        case nil: return record
        }
    }
}

/// 上次同步完两边一致的那份（三方合并的 base），存在 App 自己的 Application Support 里（键盘用不到）。
enum SyncBase {
    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CloudSync", isDirectory: true)
    }

    static func get(_ item: BackupItem) -> Data? {
        folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent(item.rawValue + ".base")) }
    }

    static func set(_ item: BackupItem, _ data: Data?) {
        guard let folder else { return }
        let url = folder.appendingPathComponent(item.rawValue + ".base")
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static var hasAny: Bool { BackupItem.allCases.contains { get($0) != nil } }

    static func clearAll() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        learnedTag = nil
        learnedHash = nil
    }

    static var learnedTag: String? {
        get { SharedStorage.defaults.string(forKey: "icloud.learnedTag") }
        set { SharedStorage.defaults.set(newValue, forKey: "icloud.learnedTag") }
    }

    static var learnedHash: String? {
        get { SharedStorage.defaults.string(forKey: "icloud.learnedHash") }
        set { SharedStorage.defaults.set(newValue, forKey: "icloud.learnedHash") }
    }

    /// 学到的词快照去掉 # 开头的元数据（里面有导出时间）再排序，内容一样就一样。
    static func contentHash(_ snapshot: String) -> String {
        let lines = snapshot.split(separator: "\n").filter { !$0.hasPrefix("#") }.sorted()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for line in lines {
            for byte in line.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            hash ^= 0x0A
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
