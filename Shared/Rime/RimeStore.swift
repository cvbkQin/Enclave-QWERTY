import Foundation

/// 拼音词库放在 App Group 共享目录里：主 App 负责部署（编译词库），键盘只读取编译好的结果。
enum RimeStore {
    static let schemaID = "rime_ice"

    struct Paths {
        let shared: URL
        let user: URL
    }

    static var paths: Paths? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let root = container.appendingPathComponent("Rime", isDirectory: true)
        return Paths(shared: root.appendingPathComponent("shared", isDirectory: true),
                     user: root.appendingPathComponent("user", isDirectory: true))
    }

    private static let deployedVersionKey = "rime.deployedVersion"

    /// 已部署的词库版本；键盘发现它变了就重新加载。
    static var deployedVersion: String? {
        get { SharedStorage.defaults.string(forKey: deployedVersionKey) }
        set { SharedStorage.defaults.set(newValue, forKey: deployedVersionKey) }
    }

    /// 编译好的方案文件在不在。
    static var isDeployed: Bool {
        guard deployedVersion != nil, let paths else { return false }
        let schema = paths.user.appendingPathComponent("build/\(schemaID).schema.yaml")
        return FileManager.default.fileExists(atPath: schema.path)
    }
}
