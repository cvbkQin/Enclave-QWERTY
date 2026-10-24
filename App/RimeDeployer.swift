import Foundation
import SwiftUI

/// 在主 App 里部署拼音词库：把 App 自带的词库复制到共享目录，再编译。
@MainActor
final class RimeDeployer: ObservableObject {
    static let shared = RimeDeployer()

    enum State: Equatable {
        case idle, deploying, done, failed(String)
    }

    @Published private(set) var state: State = .idle
    /// 这次部署开始的时间，用来画大概的进度。
    @Published private(set) var startedAt: Date?

    /// App 自带词库的版本（由 scripts/fetch-rime.sh 写入）。
    static var bundledVersion: String? {
        guard let url = bundledData?.appendingPathComponent("data_version.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var bundledData: URL? {
        Bundle.main.url(forResource: "RimeData", withExtension: nil)
    }

    /// 应该部署成的版本：自带词库版本 + 当前的模糊拼音。
    static var targetVersion: String? {
        bundledVersion.map { $0 + schemaPatchTag + FuzzyPinyin.versionTag(SettingsStore.load().fuzzyPinyin) }
    }

    /// 部署时对方案文件的固定改动；改了这里就换个编号，让已装的词库重新部署。
    private static let schemaPatchTag = "+t9delim"

    /// 九宫格方案没有设音节分隔符。选拼音栏会把「qin」写成字母再用 ' 隔开后面的数字，
    /// 没有分隔符时 ' 把输入切成两段，前一段「qin」上屏时原样变成英文。补上和全键盘一样的分隔符。
    nonisolated static func patchNineKeyDelimiter(_ text: String) -> String {
        guard let speller = text.range(of: "\nspeller:\n") else { return text }
        let rest = text[speller.upperBound...]
        let end = rest.range(of: "\n[a-z_]+:", options: .regularExpression)?.lowerBound ?? rest.endIndex
        if rest[..<end].contains("delimiter:") { return text }
        var patched = text
        patched.insert(contentsOf: "  delimiter: \" '\"\n", at: speller.upperBound)
        return patched
    }

    /// 还没部署过，或者 App 自带的词库、模糊拼音变了。
    var needsDeploy: Bool {
        RimeStore.deployedVersion != Self.targetVersion || !RimeStore.isDeployed
    }

    /// 上次部署完成的时间。
    static var deployedAt: Date? {
        get { SharedStorage.defaults.object(forKey: "rime.deployedAt") as? Date }
        set { SharedStorage.defaults.set(newValue, forKey: "rime.deployedAt") }
    }

    /// 词库占用的空间（共享数据 + 编译结果），字节。
    nonisolated static func diskSize() -> Int64? {
        guard let paths = RimeStore.paths else { return nil }
        var total: Int64 = 0
        for root in [paths.shared, paths.user] {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in walker {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    func deployIfNeeded() {
        if needsDeploy { deploy() }
    }

    func deploy() {
        guard state != .deploying else { return }
        guard let paths = RimeStore.paths else {
            state = .failed("App Group 没有生效，键盘读不到词库。请检查签名里的 App Group。")
            return
        }
        guard let source = Self.bundledData, let version = Self.targetVersion else {
            state = .failed("App 里没有词库。构建前需要运行 scripts/fetch-rime.sh。")
            return
        }
        let fuzzy = SettingsStore.load().fuzzyPinyin
        state = .deploying
        startedAt = Date()
        Task.detached(priority: .userInitiated) {
            let result = Self.run(source: source, paths: paths, fuzzy: fuzzy)
            await MainActor.run {
                self.startedAt = nil
                switch result {
                case .success:
                    RimeStore.deployedVersion = version
                    Self.deployedAt = Date()
                    self.state = .done
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private struct DeployError: LocalizedError {
        let errorDescription: String?
    }

    nonisolated private static func run(source: URL, paths: RimeStore.Paths, fuzzy: Set<FuzzyPinyin>) -> Result<Void, Error> {
        let fm = FileManager.default
        do {
            // 共享数据整份替换；用户目录保留（里面有学习到的词频），只删掉旧的编译结果。
            if fm.fileExists(atPath: paths.shared.path) {
                try fm.removeItem(at: paths.shared)
            }
            try fm.createDirectory(at: paths.shared.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: paths.shared)
            let nineKey = paths.shared.appendingPathComponent("\(RimeStore.nineKeySchemaID).schema.yaml")
            let nineKeyText = try String(contentsOf: nineKey, encoding: .utf8)
            try patchNineKeyDelimiter(nineKeyText).write(to: nineKey, atomically: true, encoding: .utf8)
            // 模糊拼音写进共享副本里的方案文件，App 自带的那份不动。
            for schema in [RimeStore.schemaID, RimeStore.nineKeySchemaID] where !fuzzy.isEmpty {
                let url = paths.shared.appendingPathComponent("\(schema).schema.yaml")
                let text = try String(contentsOf: url, encoding: .utf8)
                try FuzzyPinyin.patchSchema(text, groups: fuzzy).write(to: url, atomically: true, encoding: .utf8)
            }
            try fm.createDirectory(at: paths.user, withIntermediateDirectories: true)
            let build = paths.user.appendingPathComponent("build", isDirectory: true)
            if fm.fileExists(atPath: build.path) {
                try fm.removeItem(at: build)
            }
        } catch {
            return .failure(error)
        }
        let ok = enclave_rime_deploy(paths.shared.path, paths.user.path, nil)
        let schema = paths.user.appendingPathComponent("build/\(RimeStore.schemaID).schema.yaml")
        guard ok, fm.fileExists(atPath: schema.path) else {
            return .failure(DeployError(errorDescription: "词库编译失败。"))
        }
        return .success(())
    }
}

