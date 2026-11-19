import Foundation

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

    // MARK: 状态怎么变（纯逻辑，单元测试直接测）

    /// 重新打开同步（1.8）：当这台第一次加入，风格和接口按设置页选的用哪份；设备编号、清除代数、已传的快照、令牌不变
    /// （iCloud 里那条设备记录接着用）。关着的这段时间本机改的、删的，不会被当成比别的设备新的改动盖过去。
    func rejoined() -> ICloudSyncState {
        var state = self
        state.exchangedAt = nil
        state.words = nil
        state.phrases = nil
        state.styles = nil
        state.endpoint = nil
        state.apis = nil
        state.uploadedDigest = nil
        return state
    }

    /// iCloud 里的区没了（用户在系统设置里删了飞地的数据）或令牌过期：从头拉一次，本机这份全部重传，
    /// 别的设备的快照重新合并（04 复审 A3）。
    func resetForMissingZone() -> ICloudSyncState {
        var state = self
        state.changeToken = nil
        state.zoneReady = false
        state.snapshotHash = ""
        state.snapshotChunks = 0
        state.uploadedDigest = nil
        state.mergedSnapshots = nil
        return state
    }

    /// 拉改动时看到一条记录被删了：这台自己的设备记录被别处删了（别的设备在设备页删了这台），下次照样传上去，
    /// 开着同步就自己加回来；自己的快照块被删了也重传。自己删的多余的块不算（序号不小于现在的块数）。
    func noticingDeletion(of recordName: String) -> ICloudSyncState {
        var state = self
        let chunkPrefix = "snapshot-\(deviceID)-"
        if recordName == "device-\(deviceID)" {
            state.uploadedDigest = nil
        } else if recordName.hasPrefix(chunkPrefix), let index = Int(recordName.dropFirst(chunkPrefix.count)), index < snapshotChunks {
            state.snapshotHash = ""
        }
        return state
    }
}
