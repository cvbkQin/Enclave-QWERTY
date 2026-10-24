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

    /// App 自带词库的版本（由 scripts/fetch-rime.sh 写入）。
    static var bundledVersion: String? {
        guard let url = bundledData?.appendingPathComponent("data_version.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var bundledData: URL? {
        Bundle.main.url(forResource: "RimeData", withExtension: nil)
    }

    /// 还没部署过，或者 App 自带的词库更新了。
    var needsDeploy: Bool {
        RimeStore.deployedVersion != Self.bundledVersion || !RimeStore.isDeployed
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
        guard let source = Self.bundledData, let version = Self.bundledVersion else {
            state = .failed("App 里没有词库。构建前需要运行 scripts/fetch-rime.sh。")
            return
        }
        state = .deploying
        Task.detached(priority: .userInitiated) {
            let result = Self.run(source: source, paths: paths)
            await MainActor.run {
                switch result {
                case .success:
                    RimeStore.deployedVersion = version
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

    nonisolated private static func run(source: URL, paths: RimeStore.Paths) -> Result<Void, Error> {
        let fm = FileManager.default
        do {
            // 共享数据整份替换；用户目录保留（里面有学习到的词频），只删掉旧的编译结果。
            if fm.fileExists(atPath: paths.shared.path) {
                try fm.removeItem(at: paths.shared)
            }
            try fm.createDirectory(at: paths.shared.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: paths.shared)
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


/// 设置页里的拼音词库状态。
struct PinyinSection: View {
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        Section {
            HStack {
                Text("万象拼音词库")
                Spacer()
                status
            }
            Button(deployer.state == .deploying ? "正在部署…" : "重新部署词库") { deployer.deploy() }
                .disabled(deployer.state == .deploying)
        } header: {
            Text("拼音词库")
        } footer: {
            Text("词库在本机编译，第一次打开 App 时自动部署，大约需要一分钟，期间不要退出 App。键盘需要打开「允许完全访问」才能读到词库。词库数据来自万象拼音（CC BY 4.0）。")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch deployer.state {
        case .deploying:
            ProgressView()
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.trailing)
        default:
            if deployer.needsDeploy {
                Text("未部署").foregroundStyle(.orange)
            } else {
                Text("已就绪").foregroundStyle(.green)
            }
        }
    }
}
