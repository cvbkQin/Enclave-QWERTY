import Foundation

/// 主 App 和键盘扩展之间的共享存储。
/// App Group 可用时两边共用同一份数据；不可用时（比如免费签名没拿到 App Group）
/// 各自退回到自己的存储，需要用「复制配置 / 从剪贴板导入」同步。
enum SharedStorage {
    static let appGroupID: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "EnclaveAppGroup") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }()

    /// App Group 是否真的生效（有 entitlement 且系统分配了共享容器）。
    static let isShared: Bool = {
        guard let id = appGroupID else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
    }()

    static let defaults: UserDefaults = {
        if isShared, let id = appGroupID, let shared = UserDefaults(suiteName: id) {
            return shared
        }
        return .standard
    }()

    /// 钥匙串访问组：App Group 生效时用它让两个 target 共享 API key。
    static var keychainAccessGroup: String? { isShared ? appGroupID : nil }
}
