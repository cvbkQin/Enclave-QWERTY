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
// - 界面在 ICloudSyncViews.swift（设计 design/icloud-sync/）：开关默认关，关着时这里什么都不做。

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
        /// 换了 Apple ID：同步暂停，要用户确认「在这个账户继续同步」（1.12）。
        case accountChanged
        /// iCloud 空间不够，没能上传。
        case quotaExceeded
        /// iCloud 里有更新版本 App 写的数据，这台看不懂，跳过了那台设备。
        case newerFormat
        case failed
    }

    var result: Result
    var at: Date
    var detail: String?
}

enum ICloudSync {
    /// 这个包有没有 iCloud 能力：ICLOUD_SYNC = YES（默认 NO，见 Configs/Base.xcconfig）的包才是 true，这时 Info.plist 里也才有后台模式。
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
    private static let pausedKey = "sync.paused"
    private static let statusKey = "sync.status"
    private static let syncedAtKey = "sync.lastSyncedAt"
    private static let pendingClearKey = "sync.pendingClear"
    private static let preferLocalKey = "sync.preferLocal"
    private static let deviceNameKey = "sync.deviceName"

    /// 现在同步不同步：开关开着、没有暂停。
    static var isEnabled: Bool { isSwitchOn && !isPaused }

    /// 设置页上的开关（每台设备自己的，不跟着同步走）。默认关。开关只走 enable() / disable()。暂停时也是开着的。
    static var isSwitchOn: Bool {
        isAvailable && SharedStorage.defaults.bool(forKey: enabledKey)
    }

    /// 换了 Apple ID（1.12）：开关还开着，但不同步，等用户在设置页点「在这个账户继续同步」。
    static var isPaused: Bool { SharedStorage.defaults.bool(forKey: pausedKey) }

    /// 打开同步（设置页、测试链接调）。Key 的同步另开（Keychain.enableSync），要先开这个。
    /// preferLocal：iCloud 里已经有别的设备的数据时，风格和接口第一次同步用这台的（设置页「用这台 iPhone 的」）；
    /// 不然用 iCloud 里已有的（1.8）。
    static func enable(preferLocal: Bool = false) {
        guard isAvailable else { return }
        ICloudSyncEngine.prepareRejoin()
        prefersLocalOnJoin = preferLocal
        SharedStorage.defaults.set(false, forKey: pausedKey)
        SharedStorage.defaults.set(true, forKey: enabledKey)
    }

    /// 关掉同步：Key 的同步一起关（同步版复制回本机版，iCloud 里的不删），免得以后存的 Key 还往 iCloud 钥匙串里写
    /// （04 审查 #75 第 6 条）。iCloud 里的其他数据不动（要删走 ICloudSyncEngine.deleteAll）。
    static func disable() {
        SharedStorage.defaults.set(false, forKey: enabledKey)
        SharedStorage.defaults.set(false, forKey: pausedKey)
        prefersLocalOnJoin = false
        lastStatus = nil
        stopKeySync()
    }

    /// 换了 Apple ID：暂停，Key 的同步一起关，新账户里不写任何东西。
    static func pause() {
        SharedStorage.defaults.set(true, forKey: pausedKey)
        stopKeySync()
    }

    /// 「在这个账户继续同步」：本机的同步状态在暂停时已经清掉，下一次同步当这台第一次加入这个账户。
    static func resume() {
        SharedStorage.defaults.set(false, forKey: pausedKey)
    }

    /// 第一次同步时风格和接口用这台的（见 enable）。第一次同步做完就清掉。
    static var prefersLocalOnJoin: Bool {
        get { UserDefaults.standard.bool(forKey: preferLocalKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferLocalKey) }
    }

    /// 这台设备在设备列表里的名字（设备页可以改，跟着设备记录传上去）。没改过用系统的设备名。
    @MainActor static var deviceName: String {
        get {
            let name = UserDefaults.standard.string(forKey: deviceNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? UIDevice.current.name : name
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: deviceNameKey) }
    }

    /// 上次同步成功（包括键盘正在用、跳过了更新版本的设备）的时间：设备页「这台」的时间。
    static var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: syncedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: syncedAtKey) }
    }

    /// 设备页、清除学习记录的弹窗用的一台设备。
    struct Device: Identifiable, Equatable {
        var id: String
        var name: String
        var isPad: Bool
        var syncedAt: Date?
        var appVersion: String
        var isThis: Bool
    }

    /// 参与同步的设备：这台在最前，别的按上次同步从近到远（上次同步拉下来的缓存，不联网）。
    @MainActor static func devices() -> [Device] {
        let own = (try? ICloudSyncEngine.loadState())?.deviceID
        let this = Device(id: own ?? "", name: deviceName, isPad: UIDevice.current.userInterfaceIdiom == .pad,
                          syncedAt: lastSyncedAt, appVersion: ICloudSyncEngine.appVersion, isThis: true)
        guard let own else { return [this] }
        let peers = PeerCache.payloads(excluding: own).map { id, payload in
            Device(id: id, name: payload.deviceName, isPad: payload.deviceModel == "iPad", syncedAt: payload.updatedAt,
                   appVersion: payload.appVersion, isThis: false)
        }
        return [this] + peers.sorted { ($0.syncedAt ?? .distantPast) > ($1.syncedAt ?? .distantPast) }
    }

    /// 这台的 iCloud 账户能不能用（设置页「没有登录 iCloud」）。查不出来（没联网等）时当能用，不挡着。
    static func accountAvailable() async -> Bool {
        guard let containerID else { return false }
        switch try? await CKContainer(identifier: containerID).accountStatus() {
        case .noAccount, .restricted: return false
        default: return true
        }
    }

    /// Key 的同步跟着总开关：总开关关着、Key 的同步还开着（上次关的时候钥匙串没写成），App 启动时再关一次。
    static func stopKeySync() {
        guard SharedStorage.defaults.bool(forKey: Keychain.syncDefaultsKey) else { return }
        Keychain.disableSync(accounts: BackupService.keyAccounts(), removeFromICloud: false)
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

    /// 本机清除了学习记录、还没告诉别的设备（下一次同步先清、再把代数加一）。存在 App 自己的设置里，App 被杀了也不丢。
    static var pendingClear: Bool {
        get { UserDefaults.standard.bool(forKey: pendingClearKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingClearKey) }
    }

    /// 同步一次。打开 App、回到前台、后台任务、收到变化推送、点「立即同步」时调。同时只跑一次，后来的等前面那次的结果。
    /// minimumInterval：离上次同步完（成功或键盘正在用）不到这么久就不跑（回到前台很频繁）；「立即同步」传 0。
    @discardableResult
    static func syncNow(minimumInterval: TimeInterval = 0) async -> ICloudSyncStatus? {
        guard isEnabled else { return nil }
        if minimumInterval > 0, let last = lastStatus, last.result == .ok || last.result == .keyboardBusy,
           Date().timeIntervalSince(last.at) < minimumInterval {
            return last
        }
        return await ICloudSyncEngine.shared.run()
    }

    /// 隐私页「清除学习记录」之后调（1.5）：开着同步时就是所有设备一起清。先记下来，再同步：
    /// 同步引擎在锁里换上空词库、清除代数加一，别的设备看到更大的代数也清掉自己的。正在同步时，等它跑完再跑一次。
    static func noteLearningCleared() {
        guard isEnabled else { return }
        pendingClear = true
        Task { await ICloudSyncEngine.shared.run(again: true) }
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
    var styles: SyncMerge.Entry<SyncMerge.StyleProfile>?
    /// 接口、接口配置：只在开着 Key 同步时有；关了就清掉，再打开时当第一次。
    var endpoint: SyncMerge.Entry<SyncMerge.EndpointProfile>?
    var apis: SyncMerge.Table<SyncMerge.SyncedAPI>?
    /// 已经上传的拼音快照：块数、校验、属于哪个清除代数。代数对不上的快照不再出现在设备记录里。
    var snapshotChunks = 0
    var snapshotHash = ""
    var snapshotGeneration = 0
    var changeToken: Data?
    var zoneReady = false
    var subscribed = false
    /// 上次做完一整轮的时间；nil 是还没同步过（第一次同步时不跟着别的设备以前的清除清空本机，04 审查 #75 第 1 条）。
    var exchangedAt: Date?
    /// 已经合并进本机词库的别的设备的快照（设备编号 → 校验）：没变就不再合并、不再换正式词库（第 3 条）。
    var mergedSnapshots: [String: String]?
    /// 上次上传的设备记录（除上传时间）的校验：没变就不传，免得两台设备互相推送停不下来（第 3 条）。
    var uploadedDigest: String?
    /// 上次上传设备记录的时间：内容没变也隔一天传一次，别的设备的设备页才知道这台还在同步。
    var uploadedAt: Date?

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
    /// 内容没变时多久重传一次设备记录（别的设备的设备页看「上次同步」，超过 30 天的标灰）。一天一次推送，不会互相推起来。
    private static let heartbeat: TimeInterval = 20 * 3600

    private var running: Task<ICloudSyncStatus, Never>?
    private var runAgain = false
    private var runCount = 0

    /// 跑一次同步。正在跑时等它的结果；again 时（清除学习记录）等它跑完再跑一次，免得用的还是清除前的状态。
    /// 调用方的任务被取消（后台任务时间到）时取消这次同步：CloudKit 的请求会停下，本机状态停在上一步存好的地方。
    func run(again: Bool = false) async -> ICloudSyncStatus {
        if let running {
            if again { runAgain = true }
            return await running.value
        }
        let task = Task { () -> ICloudSyncStatus in
            var status = await self.perform()
            var rounds = 0
            while await self.takeRunAgain(), rounds < 2, !Task.isCancelled {
                status = await self.perform()
                rounds += 1
            }
            return status
        }
        running = task
        runCount += 1
        let number = runCount
        await MainActor.run { ICloudSyncMonitor.shared.begin(number) }
        let status = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        running = nil
        ICloudSync.lastStatus = status
        if [.ok, .keyboardBusy, .newerFormat].contains(status.result) { ICloudSync.lastSyncedAt = status.at }
        await MainActor.run { ICloudSyncMonitor.shared.end(number, status) }
        return status
    }

    private func takeRunAgain() -> Bool {
        defer { runAgain = false }
        return runAgain
    }

    // MARK: 本机状态的文件

    private static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ICloudSync", isDirectory: true)
    }

    private static var stateURL: URL? { folder?.appendingPathComponent("state.json") }
    private static var peersFolder: URL? { folder?.appendingPathComponent("peers", isDirectory: true) }

    private static let stateLock = NSLock()

    /// 状态文件在、却读不出来（开机后还没解锁过，文件被数据保护锁着）：这次不同步，不然会当成新设备重新开始。
    struct StateUnavailable: Error {}

    static func loadState() throws -> ICloudSyncState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let url = stateURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw StateUnavailable() }
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

    /// 重新打开同步：当这台第一次加入（1.8，风格和接口按设置页选的用哪份），设备编号不变（iCloud 里那条设备记录接着用）。
    /// 关着的这段时间本机改的、删的，不会被当成比别的设备新的改动盖过去。
    static func prepareRejoin() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let url = stateURL, let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(ICloudSyncState.self, from: data) else { return }
        state.exchangedAt = nil
        state.words = nil
        state.phrases = nil
        state.styles = nil
        state.endpoint = nil
        state.apis = nil
        state.uploadedDigest = nil
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    static func removeState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let url = stateURL { try? FileManager.default.removeItem(at: url) }
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
                working.uploadedDigest = nil
                PeerCache.clear()
                try await ensureZone(database, &working)
                try await fetchChanges(database, &working)
            }
            Self.saveState(working)
            return try await exchange(database, &working)
        } catch is StateUnavailable {
            return ICloudSyncStatus(result: .failed, at: Date(), detail: "locked")
        } catch let error as CKError where error.code == .quotaExceeded {
            return ICloudSyncStatus(result: .quotaExceeded, at: Date(), detail: nil)
        } catch let error as CKError where error.code == .notAuthenticated {
            return ICloudSyncStatus(result: .noAccount, at: Date(), detail: nil)
        } catch {
            return ICloudSyncStatus(result: .failed, at: Date(), detail: String(describing: error))
        }
    }

    /// 读本机状态，核对设备和账户。换了 Apple ID 时关掉同步、清掉本机状态，返回 nil。
    private func prepareState(_ container: CKContainer) async throws -> ICloudSyncState? {
        let vendor = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        var state = try Self.loadState() ?? ICloudSyncState(vendorID: vendor)
        if state.vendorID != vendor {
            state = ICloudSyncState(vendorID: vendor)
            PeerCache.clear()
        }
        let user = try await container.userRecordID().recordName
        if let old = state.userRecordName, old != user {
            // 换了 Apple ID：同步暂停、Key 的同步关掉，新账户里不写任何东西，要用户确认后再继续（1.12）。
            await MainActor.run { ICloudSync.pause() }
            PeerCache.clear()
            Self.removeState()
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
                // 这台自己的记录被别处删了（别的设备在设备页删了这台）：下次照样传上去，开着同步就自己加回来。
                // 自己删的多余的块不算（序号不小于现在的块数）。
                let name = deletion.recordID.recordName
                let chunkPrefix = "snapshot-\(state.deviceID)-"
                if name == "device-\(state.deviceID)" {
                    state.uploadedDigest = nil
                } else if name.hasPrefix(chunkPrefix), let index = Int(name.dropFirst(chunkPrefix.count)), index < state.snapshotChunks {
                    state.snapshotHash = ""
                }
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
        let firstSync = state.exchangedAt == nil
        let prefersLocal = firstSync && ICloudSync.prefersLocalOnJoin

        // 1. 拼音词库：先看要不要清除，再合并。
        var keyboardBusy = false
        var snapshot: String?
        let maxGeneration = SyncMerge.generation(local: state.generation, peers: peers.values.map(\.generation))
        if ICloudSync.pendingClear {
            // 本机在隐私页清除了学习记录：在锁里换上空词库（文件已经删了，这里确认一下），代数加一，所有设备一起清。
            if await Self.blocking({ LearnedWords.clearForSync() }) {
                state.generation = maxGeneration + 1
                state.mergedSnapshots = [:]
                ICloudSync.pendingClear = false
            } else {
                keyboardBusy = true
            }
            Self.saveState(state)
        } else if maxGeneration > state.generation {
            if firstSync {
                // 第一次同步（新设备，或本机同步状态重置过）：那是这台加入以前别的设备清的，本机的词不清，直接跟上代数
                // （04 审查 #75 第 1 条）。
                state.generation = maxGeneration
                state.mergedSnapshots = [:]
            } else if await Self.blocking({ LearnedWords.clearForSync() }) {
                state.generation = maxGeneration
                state.mergedSnapshots = [:]
            } else {
                keyboardBusy = true
            }
            Self.saveState(state)
        }
        if !keyboardBusy {
            // 只合并上次以后变了的快照：合并会原子换一次正式词库，都没变就只导出本机的（第 3 条）。
            var texts: [String: String] = [:]
            var merged: [String: String] = [:]
            for (id, payload) in peers where payload.generation == state.generation {
                if state.mergedSnapshots?[id] == payload.snapshotHash {
                    merged[id] = payload.snapshotHash
                } else if let text = PeerCache.snapshot(id: id, payload: payload) {
                    texts[id] = text
                    merged[id] = payload.snapshotHash
                } else if let old = state.mergedSnapshots?[id] {
                    // 块还没收齐（那台正传到一半）：下次再合并。
                    merged[id] = old
                }
            }
            let peerTexts = texts
            switch await Self.blocking({ LearnedWords.sync(peers: peerTexts) }) {
            case .merged(let text):
                snapshot = text
                state.mergedSnapshots = merged
            case .busy: keyboardBusy = true
            case .failed: break
            }
            // 合并途中用户清除了学习记录：这份快照可能带着清掉的词，不传；清除已经排在下一轮。
            if ICloudSync.pendingClear { snapshot = nil }
        }

        // 2. 常用词、常用语、风格；开着 Key 同步时还有接口和接口配置。
        let syncsAI = !BuiltinAPI.available
        let syncsEndpoints = syncsAI && Keychain.syncsToICloud
        let local = await MainActor.run { LocalData.read() }
        // 合并时按设备编号排好序（本机也在里面），每台设备算出来的结果一样。
        let order = ([state.deviceID] + peers.keys).sorted()

        let wordItems = SyncMerge.wordItems(local.words)
        let myWords = SyncMerge.observe(current: wordItems, previous: state.words, now: now)
        var wordTables: [SyncMerge.Table<SyncMerge.Word>] = []
        for id in order { wordTables.append(id == state.deviceID ? myWords : peers[id]?.words ?? [:]) }
        let mergedWords = SyncMerge.pruned(SyncMerge.merge(wordTables), now: now)
        let newWords = SyncMerge.words(SyncMerge.apply(mergedWords, to: wordItems), current: local.words)
            + local.words.filter { $0.isReadOnly }

        let phraseItems = SyncMerge.phraseItems(local.phrases)
        let myPhrases = SyncMerge.observe(current: phraseItems, previous: state.phrases, now: now)
        var phraseTables: [SyncMerge.Table<KeyboardPhrase>] = []
        for id in order { phraseTables.append(id == state.deviceID ? myPhrases : peers[id]?.phrases ?? [:]) }
        let mergedPhrases = SyncMerge.pruned(SyncMerge.merge(phraseTables), now: now)
        let newPhrases = SyncMerge.apply(mergedPhrases, to: phraseItems).map { $0.value }

        var stylesRecord: SyncMerge.Entry<SyncMerge.StyleProfile>?
        var newStyles: SyncMerge.StyleProfile?
        if syncsAI {
            let resolved = SyncMerge.resolve(local: local.styles, previous: state.styles,
                                             peers: peers.compactMapValues { $0.styles }, myID: state.deviceID, now: now,
                                             prefersLocal: prefersLocal)
            stylesRecord = resolved.record
            newStyles = resolved.apply
        }

        // 接口和接口配置：别的设备的只在它配的 Key 已经同步到本机钥匙串时才用（第 2 条）。
        var endpointRecord: SyncMerge.Entry<SyncMerge.EndpointProfile>?
        var newEndpoint: SyncMerge.EndpointProfile?
        var apisRecord: SyncMerge.Table<SyncMerge.SyncedAPI>?
        var newAPIs: [SavedAPI]?
        var newBindings: [String: String] = [:]
        if syncsEndpoints {
            let resolved = SyncMerge.resolve(local: local.endpoint, previous: state.endpoint,
                                             peers: peers.compactMapValues { $0.endpoint }, myID: state.deviceID, now: now,
                                             prefersLocal: prefersLocal, accept: { SyncMerge.keysMatch($0.keys, current: Keychain.currentFingerprint) })
            endpointRecord = resolved.record
            if let value = resolved.apply {
                newEndpoint = value
                newBindings.merge(value.keys) { _, new in new }
            }

            let apiItems = SyncMerge.apiItems(local.savedAPIs, keys: Keychain.binding)
            let myAPIs = SyncMerge.observe(current: apiItems, previous: state.apis, now: now)
            var apiTables: [SyncMerge.Table<SyncMerge.SyncedAPI>] = []
            for id in order { apiTables.append(id == state.deviceID ? myAPIs : peers[id]?.apis ?? [:]) }
            let mergedAPIs = SyncMerge.accepting(SyncMerge.pruned(SyncMerge.merge(apiTables), now: now), mine: myAPIs) { entry in
                guard let value = entry.value else { return true }
                return Keychain.currentFingerprint(SyncMerge.SyncedAPI.account(value.api.id.uuidString)) == value.key
            }
            apisRecord = mergedAPIs
            let list = SyncMerge.apply(mergedAPIs, to: apiItems).map { $0.value }
            if list.map(\.api) != local.savedAPIs { newAPIs = list.map(\.api) }
            for item in list where Keychain.binding(SyncMerge.SyncedAPI.account(item.api.id.uuidString)) != item.key {
                newBindings[SyncMerge.SyncedAPI.account(item.api.id.uuidString)] = item.key
            }
        }

        let wordsChanged = newWords != local.words
        let phrasesChanged = newPhrases != local.phrases
        let stylesToApply = newStyles
        let endpointToApply = newEndpoint
        let apisToApply = newAPIs
        let bindings = newBindings
        if wordsChanged || phrasesChanged || stylesToApply != nil || endpointToApply != nil || apisToApply != nil || !bindings.isEmpty {
            let applied = await MainActor.run { () -> Bool in
                // 读本机和写回之间用户在 App 里改过：这次不写，下次同步再来（04 审查 #75 第 10 条）。
                guard LocalData.read() == local else { return false }
                if wordsChanged { CommonWordStore.save(newWords) }
                if phrasesChanged { CommonWordStore.keyboardPhrases = newPhrases }
                if stylesToApply != nil || endpointToApply != nil {
                    var settings = SettingsStore.load()
                    stylesToApply?.apply(to: &settings)
                    endpointToApply?.apply(to: &settings)
                    SettingsStore.save(settings)
                }
                if let apisToApply { SavedAPIStore.replaceAll(apisToApply) }
                // 先写地址、再配 Key：键盘在两步之间读到的是「新地址、旧配对」，Key 对不上就不用，不会拿新 Key 请求旧地址。
                if !bindings.isEmpty { Keychain.bind(bindings) }
                NotificationCenter.default.post(name: .enclaveSyncDidApply, object: nil)
                return true
            }
            guard applied else {
                // 马上再来一轮（run 里最多再跑两轮）：用户刚改的那一下这次就会被当成本机的改动。
                runAgain = true
                return ICloudSyncStatus(result: .failed, at: now, detail: "localChanged")
            }
        }
        // 写回本机后马上记下来：上传失败时，下次也不会把刚合并进来的当成本机的新改动。
        state.words = mergedWords
        state.phrases = mergedPhrases
        state.styles = stylesRecord
        state.endpoint = endpointRecord
        state.apis = apisRecord
        state.exchangedAt = now
        Self.saveState(state)
        ICloudSync.prefersLocalOnJoin = false

        // 3. 上传本机这份：先传快照的块，再传设备记录，最后删掉多出来的旧块。内容都没变就不传（第 3 条）。
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
                Self.saveState(state)
            }
        }
        // 快照不是当前代数的（刚清除过、还没传新的）：设备记录里不带快照，别的设备就不会合并清除前的词。
        let currentSnapshot = state.snapshotGeneration == state.generation
        let (deviceName, deviceModel) = await MainActor.run { (ICloudSync.deviceName, UIDevice.current.model) }
        let payload = SyncMerge.DevicePayload(
            format: SyncMerge.DevicePayload.currentFormat,
            deviceName: deviceName,
            deviceModel: deviceModel,
            appVersion: Self.appVersion,
            updatedAt: now,
            generation: state.generation,
            words: mergedWords,
            phrases: mergedPhrases,
            styles: stylesRecord,
            endpoint: endpointRecord,
            apis: apisRecord,
            snapshotChunks: currentSnapshot ? state.snapshotChunks : 0,
            snapshotHash: currentSnapshot ? state.snapshotHash : "")
        let digest = payload.contentDigest
        let heartbeatDue = state.uploadedAt.map { now.timeIntervalSince($0) > Self.heartbeat } ?? true
        if digest != state.uploadedDigest || heartbeatDue {
            let device = CKRecord(recordType: Self.deviceType, recordID: Self.deviceID(state.deviceID))
            device.encryptedValues["payload"] = try JSONEncoder().encode(payload)
            try await Self.save([device], in: database)
            state.uploadedDigest = digest
            state.uploadedAt = now
        }
        let keep = currentSnapshot ? state.snapshotChunks : 0
        if oldChunks > keep {
            let stale = (keep..<oldChunks).map { Self.chunkID(state.deviceID, $0) }
            _ = try? await database.modifyRecords(saving: [], deleting: stale, atomically: false)
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

    // MARK: 设置页用的

    /// 打开同步之前看 iCloud 里有没有别的设备的数据（设置页 ⑧）：有就问风格和接口用哪份。
    enum Probe: Equatable {
        case noAccount
        case empty
        case existing(name: String, date: Date)
    }

    /// 只拉设备记录（不拉快照的块）。区还没有、网络不通都当没有：照常打开，第一次同步默认用 iCloud 里的（1.8）。
    func probe() async -> Probe {
        guard let containerID = ICloudSync.containerID else { return .empty }
        let container = CKContainer(identifier: containerID)
        switch try? await container.accountStatus() {
        case .noAccount, .restricted: return .noAccount
        default: break
        }
        let ownID = (try? Self.loadState())?.deviceID
        let own = ownID.map { "device-\($0)" }
        var latest: (name: String, date: Date)?
        var token: CKServerChangeToken?
        do {
            var more = true
            while more {
                let changes = try await container.privateCloudDatabase.recordZoneChanges(
                    inZoneWith: Self.zoneID, since: token, desiredKeys: ["payload"])
                for (id, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result, id.recordName.hasPrefix("device-"), id.recordName != own else { continue }
                    let record = modification.record
                    let payload = (record.encryptedValues["payload"] as? Data)
                        .flatMap { try? JSONDecoder().decode(SyncMerge.DevicePayload.self, from: $0) }
                    let date = payload?.updatedAt ?? record.modificationDate ?? .distantPast
                    if let current = latest, current.date >= date { continue }
                    latest = (payload?.deviceName ?? L("另一台设备", "another device", "別のデバイス"), date)
                }
                token = changes.changeToken
                more = changes.moreComing
            }
        } catch {
            return .empty
        }
        guard let latest else { return .empty }
        return .existing(name: latest.name, date: latest.date)
    }

    /// 设备页删一台旧设备：删掉它在 iCloud 里的记录和本机的缓存。它要是还开着同步，下次同步会自己传回来。
    func removeDevice(_ id: String) async throws {
        guard let containerID = ICloudSync.containerID else { return }
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let chunks = max(PeerCache.payloads(excluding: "")[id]?.snapshotChunks ?? 0, PeerCache.chunkCount(id))
        let ids = [Self.deviceID(id)] + (0..<chunks).map { Self.chunkID(id, $0) }
        let (_, deleted) = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        for (_, result) in deleted {
            if case .failure(let error) = result, (error as? CKError)?.code != .unknownItem { throw error }
        }
        PeerCache.removeDevice(id)
    }

    /// 关闭并删除 iCloud 里的数据（设置页 ⑨⑩）：删掉整个区（所有设备的记录），清掉本机的同步状态和缓存。
    /// 调之前先关掉同步。别的设备还开着同步时，会发现区没了，重建后把自己那份传上去。
    func deleteAll() async throws {
        if let running { _ = await running.value }
        guard let containerID = ICloudSync.containerID else { return }
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        do {
            let (_, deleted) = try await database.modifyRecordZones(saving: [], deleting: [Self.zoneID])
            if case .failure(let error) = deleted[Self.zoneID] { throw error }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // 已经没有了。
        }
        PeerCache.clear()
        Self.removeState()
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
        let errors = saved.values.compactMap { result -> Error? in
            if case .failure(let error) = result { return error }
            return nil
        }
        // 整批失败时别的记录报 batchRequestFailed，真正的原因（比如空间不够）在其中一条上。
        if let error = errors.first(where: { ($0 as? CKError)?.code != .batchRequestFailed }) ?? errors.first { throw error }
    }

    static var appVersion: String {
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

/// 本机这边要同步的数据（在主线程读）。写回前再读一次比一比，中间被改过就不写。
private struct LocalData: Equatable {
    var words: [CommonWord]
    var phrases: [KeyboardPhrase]
    var styles: SyncMerge.StyleProfile
    /// 接口带着本机配的 Key 的指纹（Keychain.binding），不是钥匙串里现在的：别的设备换了 Key、地址还没到时，
    /// 本机的配置没变，不能当成本机改了。
    var endpoint: SyncMerge.EndpointProfile
    var savedAPIs: [SavedAPI]

    static func read() -> LocalData {
        let settings = SettingsStore.load()
        let keys = Dictionary(uniqueKeysWithValues: SyncMerge.EndpointProfile.accounts.map { ($0, Keychain.binding($0)) })
        return LocalData(words: CommonWordStore.load(), phrases: CommonWordStore.keyboardPhrases,
                         styles: SyncMerge.StyleProfile(settings: settings),
                         endpoint: SyncMerge.EndpointProfile(settings: settings, keys: keys),
                         savedAPIs: SavedAPIStore.all)
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

    /// 缓存里这台设备有几块快照（删设备时连多出来的旧块一起删）。
    static func chunkCount(_ device: String) -> Int {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return 0 }
        let prefix = "\(device).chunk."
        return names.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil }.map { $0 + 1 }.max() ?? 0
    }

    static func removeDevice(_ device: String) {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name == "\(device).json" || name.hasPrefix("\(device).chunk.") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
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

/// 设置页看的同步状态：正在同步、上次的结果。同步引擎每一轮开始、结束时更新（打开 App、后台推送触发的也算）。
@MainActor
final class ICloudSyncMonitor: ObservableObject {
    static let shared = ICloudSyncMonitor()

    @Published private(set) var running = false
    @Published private(set) var status = ICloudSync.lastStatus
    private var current = 0

    func begin(_ run: Int) {
        current = run
        running = true
    }

    /// 后面又开始了一轮时不把「正在同步」关掉。
    func end(_ run: Int, _ status: ICloudSyncStatus) {
        self.status = status
        if run == current { running = false }
    }

    /// 关掉同步、删掉 iCloud 数据后：不再显示上次的结果。
    func reset() {
        status = nil
    }
}
