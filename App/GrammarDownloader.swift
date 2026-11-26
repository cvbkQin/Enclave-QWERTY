import Combine
import CryptoKit
import Foundation
import StoreKit
import SwiftUI
import UIKit

/// 下载、删除整句模型。下载完校验文件头（中国大陆线路再校验 sha256），放进 Rime 用户目录后重新部署词库。
/// 11-26 对齐清单第 99 条（design/dict-update DU1，specs/整句模型下载与热门词库自动更新-方案.md 第二节）：
/// - 七种状态：未下载、下载中、已暂停、重试中、下载失败、安装中、已下载。已下 / 总共和线路记下来，App 重开后照样显示「45% · 已暂停」。
/// - 两条预置线路（GrammarLine），不能再手填地址；下载中、暂停、重试、失败时换线路，旧进度丢掉从头下，不弹确认。
/// - 用系统的后台下载：切到别的 App、App 被系统收回也接着下，下完叫醒 App 收尾（EnclaveAppDelegate 接回调）。
/// - 断了自动重试 3 次（2、4、8 秒后），能续传就从断的地方接着下；三次都不行算下载失败，进度留着。
/// - 服务器清单（dicts/catalog.json 的 grammar 段）有新版本时只提示，不自动下（391 MB 太大）。
@MainActor
final class GrammarDownloader: NSObject, ObservableObject {
    static let shared = GrammarDownloader()

    /// 后台下载会话的编号：App 被系统叫醒收尾时按它找回会话。
    nonisolated static var sessionID: String { (Bundle.main.bundleIdentifier ?? "enclave") + ".grammar" }

    enum State: Equatable {
        /// 没在下：有进度就是「已暂停」，装了就是「已下载」，不然「未下载」（见 Phase）。
        case idle
        case downloading
        /// 网断了，at 那一刻自动再试；attempt 是第几次（共 maxRetries 次）。
        case retrying(attempt: Int, at: Date)
        case failed(String)
        /// 下完了，正在校验、放进 Rime 用户目录（之后部署进词库时 phase 也是 installing，见 awaitingDeploy）。
        case installing
    }

    /// 卡片上显示哪一种（DU1 ①–⑦）。
    enum Phase: Equatable {
        case notDownloaded, downloading, paused, retrying(attempt: Int, at: Date), failed(String), installing, installed
    }

    /// 已下 / 总共和用的哪条线路：跨 App 重启保留。
    struct Progress: Codable, Equatable {
        var received: Int64
        var expected: Int64
        var line: GrammarLine

        var fraction: Double { Double(received) / Double(max(expected, 1)) }
        var percent: Int { min(100, Int(fraction * 100)) }
    }

    @Published private(set) var state: State = .idle
    /// 界面每个包都更新；UserDefaults 只在开始、换线路、清掉和每多 2 MB 时写（见 setProgress）。
    @Published private(set) var progress: Progress?
    @Published private(set) var installed = GrammarModel.isInstalled
    @Published private(set) var enabled = GrammarModel.isEnabled
    /// 装进词库失败：回到「已下载」，下面一行红字。
    @Published private(set) var installError: String?
    /// 用户点过的线路；没点过按 App Store 地区（Storefront 启动后才读到，所以不在这里定死）。
    @Published private var chosenLine = UserDefaults.standard.string(forKey: GrammarDownloader.lineKey).flatMap(GrammarLine.init(rawValue:))

    static let maxRetries = 3
    nonisolated private static let lineKey = "grammar.line"
    nonisolated private static let progressKey = "grammar.progress"

    private var task: URLSessionDownloadTask?
    /// 这一轮自动重试了几次；人点下载、继续、重试或成功后清零。
    private var retries = 0
    /// 上次存进度时的字节数：每多 2 MB 存一次，不每个包都写。
    private var savedReceived: Int64 = 0
    /// 后台下载收尾时系统给的回调：事件都处理完后调一次。
    var backgroundCompletion: (() -> Void)?
    private var deployWatch: AnyCancellable?
    /// 模型放好了、等部署进词库（DU1 ⑥ 安装中的后半段）。
    @Published private var awaitingDeploy = false

    private static var resumeFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("grammar.resume")
    }

    private var resumeData: Data? {
        get { try? Data(contentsOf: Self.resumeFile) }
        set {
            if let newValue { try? newValue.write(to: Self.resumeFile) } else { try? FileManager.default.removeItem(at: Self.resumeFile) }
        }
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    override init() {
        super.init()
        // 以前手填过地址的：升级后回到默认线路（用户 11-26 定）。
        SharedStorage.defaults.removeObject(forKey: GrammarModel.legacyDownloadURLKey)
        progress = Self.loadProgress()  // 读出来的不用再写回
        savedReceived = progress?.received ?? 0
        // 上次 App 被收回时还在下：找回那个任务接着显示进度。
        session.getAllTasks { tasks in
            Task { @MainActor in
                guard self.task == nil, let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running }) else { return }
                self.task = running
                self.state = .downloading
            }
        }
        // 下完还没部署进词库（在后台下完、App 被收回后重开）：接着显示「安装中」，回到前台 deployIfNeeded 会部署。
        awaitingDeploy = installed && GrammarModel.isActive && !GrammarModel.isBundled
            && !(RimeStore.deployedVersion ?? "").contains(GrammarModel.versionTag(installed: true))
        // 安装中：部署完变「已下载」；部署失败也回到「已下载」，显示红字。部署的进度变了也刷新卡片。
        deployWatch = RimeDeployer.shared.$state.sink { [weak self] deploy in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.objectWillChange.send()
                guard self.awaitingDeploy else { return }
                switch deploy {
                case .done where !RimeDeployer.shared.needsDeploy:
                    self.awaitingDeploy = false
                case .failed(let message):
                    self.installError = message
                    self.awaitingDeploy = false
                default:
                    break
                }
            }
        }
    }

    // MARK: 线路

    var line: GrammarLine { chosenLine ?? GrammarLine.defaultLine(mainland: Storefront.isMainlandChina) }

    /// 点另一条线路：记住；正在下、暂停、重试、失败时丢掉旧进度，马上从新线路从头下（两边的续传数据不通用）。
    func switchLine(to newLine: GrammarLine) {
        guard newLine != line else { return }
        chosenLine = newLine
        UserDefaults.standard.set(newLine.rawValue, forKey: Self.lineKey)
        let busy: Bool
        switch state {
        case .downloading, .retrying, .failed: busy = true
        case .idle: busy = progress != nil
        case .installing: busy = false
        }
        guard busy else { return }
        let old = task
        task = nil
        old?.cancel()
        resumeData = nil
        setProgress(nil)
        retries = 0
        start()
    }

    /// 服务器清单里的地址（以后换 CDN 不用发新版），拉不到清单时用 App 里带的。
    private func url(for line: GrammarLine) -> URL {
        if let text = ExtDictStore.shared.catalog.grammar?.urls?[line.catalogKey], let url = URL(string: text) { return url }
        return line.defaultURL
    }

    /// 清单里的大小，没有时 391 MB。
    var expectedSize: Int64 { ExtDictStore.shared.catalog.grammar?.size ?? GrammarModel.approximateSize }

    // MARK: 状态

    var phase: Phase {
        switch state {
        case .installing: return .installing
        case .downloading: return .downloading
        case .retrying(let attempt, let at): return .retrying(attempt: attempt, at: at)
        case .failed(let message): return .failed(message)
        case .idle:
            if progress != nil { return .paused }
            if installed && awaitingDeploy { return .installing }
            return installed ? .installed : .notDownloaded
        }
    }

    /// 服务器上的模型换了版本（DU1 ⑧）：只提示，点「更新」才下。返回新版本号。
    var updateVersion: String? {
        guard installed, !GrammarModel.isBundled, let grammar = ExtDictStore.shared.catalog.grammar, !grammar.version.isEmpty else { return nil }
        if let local = GrammarModel.downloadedVersion {
            return DictUpdatePolicy.compare(grammar.version, local) == .orderedDescending ? grammar.version : nil
        }
        // 更早下的没记版本：按大小比。
        guard let size = grammar.size, let local = GrammarModel.installedSize else { return nil }
        return size != local ? grammar.version : nil
    }

    func refresh() {
        installed = GrammarModel.isInstalled
        enabled = GrammarModel.isEnabled
    }

    /// 开关整句模型：文件不动，重新部署一次词库。
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        GrammarModel.isEnabled = value
        enabled = value
        RimeDeployer.shared.deploy()
    }

    // MARK: 下载

    /// 下载、继续下载、重试、更新：人点的，重试次数清零。
    func download() {
        switch state {
        case .downloading, .installing: return
        default: break
        }
        guard GrammarModel.fileURL != nil else {
            state = .failed(L("App Group 没有生效，放不了模型。", "The App Group isn't working, so the model can't be saved.", "App Group が有効でないため、モデルを保存できません。"))
            return
        }
        installError = nil
        retries = 0
        start()
    }

    /// 有续传数据就接着下，没有（或续传数据坏了）就从头下。
    private func start() {
        state = .downloading
        let line = progress?.line ?? self.line
        let task: URLSessionDownloadTask
        if let data = resumeData, progress != nil {
            task = session.downloadTask(withResumeData: data)
        } else {
            resumeData = nil
            task = session.downloadTask(with: url(for: line))
            setProgress(Progress(received: 0, expected: expectedSize, line: line))
        }
        task.taskDescription = line.rawValue
        self.task = task
        task.resume()
    }

    /// 暂停：留着已经下的部分，下次接着下。重试等着的时候点暂停，就不再自动试。
    func pause() {
        let current = task
        task = nil
        state = .idle
        if let progress { setProgress(progress) }
        guard let current else { return }
        current.cancel { [weak self] data in
            guard let data else { return }
            Task { @MainActor in self?.resumeData = data }
        }
    }

    func delete() {
        // 内测包自带的删不掉。
        guard !GrammarModel.isBundled else { return }
        if let url = GrammarModel.fileURL { try? FileManager.default.removeItem(at: url) }
        installed = false
        installError = nil
        awaitingDeploy = false
        GrammarModel.downloadedLine = nil
        GrammarModel.downloadedAt = nil
        GrammarModel.downloadedVersion = nil
        RimeDeployer.shared.deploy()
    }

    /// 下载完成：在下载回调里同步把临时文件挪到旁边（回调返回后系统就删了它），再到后台校验。
    private func finish(with location: URL, line: GrammarLine) {
        guard let target = GrammarModel.fileURL else { return }
        let staging = target.appendingPathExtension("download")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
            try fm.moveItem(at: location, to: staging)
        } catch {
            fail(error.localizedDescription)
            return
        }
        let grammar = ExtDictStore.shared.catalog.grammar
        let expectedSHA = line.verifiesSHA ? grammar?.sha256 : nil
        state = .installing
        Task.detached(priority: .userInitiated) {
            let valid = GrammarModel.isValid(staging)
            let shaOK = expectedSHA.map { Self.sha256(of: staging) == $0.lowercased() } ?? true
            await MainActor.run { self.install(staging: staging, target: target, valid: valid, shaOK: shaOK, line: line, version: grammar?.version) }
        }
    }

    private func install(staging: URL, target: URL, valid: Bool, shaOK: Bool, line: GrammarLine, version: String?) {
        let fm = FileManager.default
        guard valid, shaOK else {
            try? fm.removeItem(at: staging)
            resumeData = nil
            setProgress(nil)
            fail(valid
                 ? L("下载的文件不完整，请重试。", "The downloaded file is incomplete. Please try again.", "ダウンロードしたファイルが不完全です。もう一度お試しください。")
                 : L("下载的文件不是整句模型。", "The downloaded file isn't a sentence model.", "ダウンロードしたファイルは文章モデルではありません。"))
            return
        }
        do {
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: staging, to: target)
        } catch {
            fail(error.localizedDescription)
            return
        }
        // 能重新下载，不进 iCloud 备份。
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = target
        try? url.setResourceValues(values)
        GrammarModel.downloadedLine = line
        GrammarModel.downloadedAt = Date()
        GrammarModel.downloadedVersion = version
        installed = true
        installError = nil
        resumeData = nil
        setProgress(nil)
        retries = 0
        state = .idle
        // 开关关着：放好就算装完，不用部署。
        guard GrammarModel.isEnabled else { return }
        awaitingDeploy = true
        // 在后台收尾的：不在后台部署（要 40 秒以上），回到前台时 EnclaveApp 调 deployIfNeeded，部署完卡片变「已下载」。
        if UIApplication.shared.applicationState == .active {
            RimeDeployer.shared.deploy()
        }
    }

    private func fail(_ message: String) {
        task = nil
        state = .failed(message)
    }

    /// 线路名（小字、失败原因里用）。
    static func lineName(_ line: GrammarLine) -> String {
        switch line {
        case .global: return L("非中国大陆线路", "Outside Mainland China", "中国本土以外")
        case .cn: return L("中国大陆线路", "Mainland China", "中国本土")
        }
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 进度存取（UserDefaults，跨重启）

    nonisolated private static func loadProgress() -> Progress? {
        guard let data = UserDefaults.standard.data(forKey: progressKey) else { return nil }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }

    nonisolated private static func saveProgress(_ progress: Progress?) {
        if let progress, let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: progressKey)
        } else {
            UserDefaults.standard.removeObject(forKey: progressKey)
        }
    }
}

extension GrammarDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard downloadTask === task else { return }
            let line = downloadTask.taskDescription.flatMap(GrammarLine.init(rawValue:)) ?? self.line
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
            if case .downloading = state {} else { state = .downloading }
            // 每多 2 MB 才写一次 UserDefaults；界面上的进度每次都更新。
            let next = Progress(received: totalBytesWritten, expected: expected, line: line)
            if totalBytesWritten - savedReceived >= 2_000_000 || progress?.line != line {
                setProgress(next)
            } else {
                progress = next
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            // App 被系统收回后在后台下完：task 是 nil，也收下。
            guard downloadTask === task || task == nil else { return }
            task = nil
            let line = downloadTask.taskDescription.flatMap(GrammarLine.init(rawValue:)) ?? self.line
            if let response = downloadTask.response as? HTTPURLResponse, ![200, 206].contains(response.statusCode) {
                resumeData = nil
                setProgress(nil)
                fail(L("下载失败（HTTP \(response.statusCode)）。可以重试，或者换一条线路。",
                       "Download failed (HTTP \(response.statusCode)). Retry or switch to the other source.",
                       "ダウンロードに失敗しました（HTTP \(response.statusCode)）。再試行するか、別のダウンロード元に切り替えてください。"))
                return
            }
            finish(with: location, line: line)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let error else { return }
            let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            // 不是正在跟的任务：App 被划掉后系统取消的那次（重开时报上来），留下续传数据，显示「已暂停」。
            guard task === self.task else {
                if self.task == nil, state == .idle, progress != nil, let data { resumeData = data }
                return
            }
            self.task = nil
            if let progress { setProgress(progress) }
            if (error as? URLError)?.code == .cancelled { return }
            // 断网、超时：系统给了续传数据就记下，等一会儿自动接着下。
            resumeData = data
            let line = progress?.line ?? self.line
            if retries < Self.maxRetries, error is URLError {
                retries += 1
                let delay = pow(2, Double(retries))
                let attempt = retries
                let at = Date().addingTimeInterval(delay)
                state = .retrying(attempt: attempt, at: at)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    // 等的时候点了暂停、换了线路：不再自动试。
                    guard let self, self.task == nil, self.state == .retrying(attempt: attempt, at: at) else { return }
                    self.start()
                }
                return
            }
            let name = line == .global ? L("非中国大陆线路（GitHub）", "the outside-Mainland source (GitHub)", "中国本土以外のダウンロード元（GitHub）")
                                       : L("中国大陆线路（飞地服务器）", "the Mainland China source (Enclave server)", "中国本土のダウンロード元（Enclave サーバー）")
            fail(L("试了 \(Self.maxRetries) 次还是连不上\(name)。检查网络后重试，或者换一条线路。",
                   "Couldn't reach \(name) after \(Self.maxRetries) tries. Check your connection and retry, or switch sources.",
                   "\(Self.maxRetries) 回試しましたが\(name)に接続できませんでした。ネットワークを確認して再試行するか、別のダウンロード元に切り替えてください。"))
        }
    }

    /// 后台下载的事件都处理完了：告诉系统可以再挂起 App。
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletion?()
            backgroundCompletion = nil
        }
    }
}

private extension GrammarDownloader {
    /// 改进度并写进 UserDefaults。
    func setProgress(_ value: Progress?) {
        progress = value
        savedReceived = value?.received ?? 0
        Self.saveProgress(value)
    }
}
