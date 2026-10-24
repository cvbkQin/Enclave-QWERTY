import Foundation

/// 拼音词库放在 App Group 共享目录里：主 App 负责部署（编译词库），键盘只读取编译好的结果。
enum RimeStore {
    static let schemaID = "enclave"
    static let nineKeySchemaID = "enclave_t9"

    static func schema(for layout: KeyboardLayout) -> String {
        layout == .nineKey ? nineKeySchemaID : schemaID
    }

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

    /// 键盘自带的编译好的词库（RimeBuild/build 是 librime 的预编译目录），配上扩展自己容器里的用户目录。
    /// 没开完全访问、读不到共享目录时用这一份，打字照常能用，学到的词频先存在扩展自己这边。
    static var bundled: (paths: Paths, version: String)? {
        guard let root = Bundle.main.url(forResource: "RimeBuild", withExtension: nil),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let user = support.appendingPathComponent("Rime", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let version = (try? String(contentsOf: root.appendingPathComponent("data_version.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "bundled"
        return (Paths(shared: root, user: user), version)
    }

    /// 编译好的方案文件在不在。
    static var isDeployed: Bool {
        guard deployedVersion != nil, let paths else { return false }
        let schema = paths.user.appendingPathComponent("build/\(schemaID).schema.yaml")
        return FileManager.default.fileExists(atPath: schema.path)
    }
}
