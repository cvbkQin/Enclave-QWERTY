import Foundation
import SwiftUI

/// 下载、删除整句模型。下载完校验文件头，放进 Rime 用户目录后重新部署词库。
/// 380 MB 在大陆网络下容易断：断了自动重试 3 次（2、4、8 秒后），能续传就从断的地方接着下；
/// 点「取消」也留着进度，再点「继续下载」接着下。续传数据存在 Caches，App 退出后也还在。
@MainActor
final class GrammarDownloader: NSObject, ObservableObject {
    static let shared = GrammarDownloader()

    enum State: Equatable {
        case idle
        /// received / expected 字节，expected 未知时为 0。
        case downloading(received: Int64, expected: Int64)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var installed = GrammarModel.isInstalled
    @Published private(set) var enabled = GrammarModel.isEnabled

    private var task: URLSessionDownloadTask?
    /// 这一轮自动重试了几次；人点下载或成功后清零。
    private var retries = 0
    private static let maxRetries = 3
    /// 有没有能续传的进度，界面上「下载」变成「继续下载」。
    @Published private(set) var canResume = FileManager.default.fileExists(atPath: GrammarDownloader.resumeFile.path)

    private static var resumeFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("grammar.resume")
    }

    private var resumeData: Data? {
        get { try? Data(contentsOf: Self.resumeFile) }
        set {
            if let newValue { try? newValue.write(to: Self.resumeFile) } else { try? FileManager.default.removeItem(at: Self.resumeFile) }
            canResume = newValue != nil
        }
    }
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

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

    func download() {
        if case .downloading = state { return }
        guard GrammarModel.fileURL != nil else {
            state = .failed(L("App Group 没有生效，放不了模型。", "The App Group isn't working, so the model can't be saved.", "App Group が有効でないため、モデルを保存できません。"))
            return
        }
        retries = 0
        start()
    }

    /// 有续传数据就接着下，没有（或续传数据坏了）就从头下。
    private func start() {
        if case .downloading = state {} else { state = .downloading(received: 0, expected: GrammarModel.approximateSize) }
        let task: URLSessionDownloadTask
        if let data = resumeData {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: GrammarModel.downloadURL)
        }
        self.task = task
        task.resume()
    }

    /// 取消时留着已经下的部分，下次接着下。
    func cancel() {
        let current = task
        task = nil
        state = .idle
        current?.cancel { [weak self] data in
            guard let data else { return }
            Task { @MainActor in self?.resumeData = data }
        }
    }

    /// 换了下载地址：旧地址的进度接不上，丢掉。
    func discardProgress() {
        resumeData = nil
    }

    func delete() {
        if let url = GrammarModel.fileURL { try? FileManager.default.removeItem(at: url) }
        installed = false
        RimeDeployer.shared.deploy()
    }

    /// 下载完成：在下载回调里同步把临时文件挪走（回调返回后系统就删了它）。
    private func finish(with location: URL) {
        guard let target = GrammarModel.fileURL else { return }
        let fm = FileManager.default
        do {
            guard GrammarModel.isValid(location) else {
                throw DownloadError(errorDescription: L("下载的文件不是整句模型。", "The downloaded file isn't a grammar model.", "ダウンロードしたファイルはモデルではありません。"))
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: location, to: target)
            // 能重新下载，不进 iCloud 备份。
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = target
            try? url.setResourceValues(values)
            state = .idle
            installed = true
            resumeData = nil
            retries = 0
            RimeDeployer.shared.deploy()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct DownloadError: LocalizedError {
        let errorDescription: String?
    }
}

extension GrammarDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard downloadTask === task else { return }
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : GrammarModel.approximateSize
            state = .downloading(received: totalBytesWritten, expected: expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            guard downloadTask === task else { return }
            task = nil
            if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
                resumeData = nil
                state = .failed(L("下载失败（HTTP \(response.statusCode)）。", "Download failed (HTTP \(response.statusCode)).", "ダウンロードに失敗しました（HTTP \(response.statusCode)）。"))
                return
            }
            finish(with: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let error, task === self.task else { return }
            self.task = nil
            if (error as? URLError)?.code == .cancelled { return }
            // 断网、超时：系统给了续传数据就记下，等一会儿自动接着下。
            let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            if let data { resumeData = data }
            if retries < Self.maxRetries, error is URLError {
                retries += 1
                let delay = pow(2, Double(retries))
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.task == nil, case .downloading = self.state else { return }
                    self.start()
                }
                return
            }
            state = .failed(L("下载中断了：\(error.localizedDescription)。点「继续下载」从断的地方接着下，或换个下载地址。",
                              "Download interrupted: \(error.localizedDescription). Tap Resume to continue, or try another download address.",
                              "ダウンロードが中断しました：\(error.localizedDescription)。「続きから」で再開するか、別のアドレスを試してください。"))
        }
    }
}
