import Foundation
import SwiftUI

/// 下载、删除整句模型。下载完校验文件头，放进 Rime 用户目录后重新部署词库。
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

    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func refresh() {
        installed = GrammarModel.isInstalled
    }

    func download() {
        if case .downloading = state { return }
        guard GrammarModel.fileURL != nil else {
            state = .failed(L("App Group 没有生效，放不了模型。", "The App Group isn't working, so the model can't be saved.", "App Group が有効でないため、モデルを保存できません。"))
            return
        }
        state = .downloading(received: 0, expected: GrammarModel.approximateSize)
        let task = session.downloadTask(with: GrammarModel.downloadURL)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
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
            state = .failed(error.localizedDescription)
        }
    }
}
