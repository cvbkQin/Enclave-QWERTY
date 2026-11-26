import BackgroundTasks
import Combine
import Foundation
import Network
import SwiftUI
import UIKit

/// 热门词库自动更新（对齐清单第 99 条，specs/整句模型下载与热门词库自动更新-方案.md 第三节，design/dict-update DU2）。
/// - 「自动更新词库」默认开：打开 App、回到前台时距上次成功检查满 7 天就查一次；系统后台刷新也会查（DictUpdateScheduler）。
///   检查失败不算一次检查，过 1 天再试。关掉后不自动查、不排后台任务，热门词库页照旧拉清单、能手动「检查更新」。
/// - 以服务器 dicts/catalog.json 为清单，按 sha256 判断有没有更新：下载过的（关着的也更新文件，保持关着）和内置的都更新；
///   服务器新加的不自动装（「可以下载」里标「新」），撤掉的不删。
/// - 低数据模式下不自动下载（手动「检查更新」照常）。请求里没有设备、用户编号（05 合规条件 4）。
/// - 在前台下完合并成一次部署；在后台只换文件，回到前台时 EnclaveApp 调 deployIfNeeded 部署。不发系统通知。
@MainActor
final class DictAutoUpdate: ObservableObject {
    static let shared = DictAutoUpdate()

    /// 「上次检查」一行的样子（DU2 ⑤）。
    enum Status: Equatable {
        case idle
        case checking
        /// 刚查过、没有新版：绿勾「刚刚 · 已是最新」，3 秒后回到 idle。
        case upToDate
        /// 「发现 N 个更新，正在下载」，done 是下完了几个。
        case downloading(count: Int, done: Int)
        /// 「没连上服务器 / 明天再自动试」+「重试」。
        case failed
    }

    /// 页面最上面的「11 月 26 日自动更新了 …」（DU2 ①②）：离开热门词库页后清掉。跨 App 重启保留，直到看过。
    struct Recent: Codable, Equatable {
        struct Item: Codable, Equatable, Identifiable {
            var id: String
            var name: String
            var version: String
            /// 多了多少词（新的减旧的，可能是负数）。
            var added: Int
            var builtin: Bool
        }

        var date: Date
        var items: [Item]
    }

    @Published var enabled = UserDefaults.standard.object(forKey: DictAutoUpdate.enabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            DictUpdateScheduler.schedule()
            if enabled { checkIfDue() }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheck = UserDefaults.standard.object(forKey: DictAutoUpdate.lastCheckKey) as? Date {
        didSet { UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey) }
    }
    private var lastFailure = UserDefaults.standard.object(forKey: DictAutoUpdate.lastFailureKey) as? Date {
        didSet { UserDefaults.standard.set(lastFailure, forKey: Self.lastFailureKey) }
    }
    @Published private(set) var recent = DictAutoUpdate.loadRecent() {
        didSet { Self.saveRecent(recent) }
    }
    /// 看过的在线词库：「可以下载」里没看过的标「新」。nil 表示还没看过这页（第一次不标）。
    @Published private(set) var seenIDs = UserDefaults.standard.stringArray(forKey: DictAutoUpdate.seenKey).map { Set($0) }
    /// 低数据模式开着：不自动下载，第二行换成橙字。
    @Published private(set) var isConstrained = false

    nonisolated private static let enabledKey = "dicts.autoUpdate"
    nonisolated private static let lastCheckKey = "dicts.lastCheck"
    nonisolated private static let lastFailureKey = "dicts.lastFailure"
    nonisolated private static let recentKey = "dicts.recentUpdate"
    nonisolated private static let seenKey = "dicts.seenCatalog"

    private let monitor = NWPathMonitor()
    private var running: Task<Bool, Never>?
    private var resetStatus: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let constrained = path.isConstrained
            Task { @MainActor in
                if self?.isConstrained != constrained { self?.isConstrained = constrained }
            }
        }
        monitor.start(queue: DispatchQueue(label: "enclave.dicts.path"))
    }

    /// 打开 App、回到前台时调：开着、到期了才查。
    func checkIfDue() {
        guard DictUpdatePolicy.isDue(now: Date(), lastCheck: lastCheck, lastFailure: lastFailure, enabled: enabled) else { return }
        Task { await run(manual: false) }
    }

    /// 「检查更新」「重试」：随时能点，开关关着也能点，低数据模式下也照常下载。
    func checkNow() {
        Task { await run(manual: true) }
    }

    /// 查一次、有新版就下。返回 true 表示拉到了清单并且要下的都下好了。同时只跑一次。
    @discardableResult
    func run(manual: Bool, background: Bool = false) async -> Bool {
        if let running { return await running.value }
        let task = Task { await perform(manual: manual, background: background) }
        running = task
        let result = await task.value
        running = nil
        return result
    }

    private func perform(manual: Bool, background: Bool) async -> Bool {
        resetStatus?.cancel()
        status = .checking
        let store = ExtDictStore.shared
        guard let fresh = await ExtDictCatalog.fetch() else {
            fail()
            return false
        }
        store.setCatalog(fresh)
        let pending = store.pendingUpdates
        let count = pending.dicts.count + pending.builtins.count
        guard count > 0 else {
            lastCheck = Date()
            lastFailure = nil
            showUpToDate()
            return true
        }
        // 低数据模式：自动的不下，那几行标「有更新」，等用户手动点。
        if !manual && isConstrained {
            lastCheck = Date()
            status = .idle
            return true
        }
        status = .downloading(count: count, done: 0)
        var items: [Recent.Item] = []
        var failed = false
        for item in pending.dicts {
            guard !Task.isCancelled else { failed = true; break }
            guard let url = ExtDictCatalog.downloadURL(item), let data = await Self.fetch(url, constrained: manual) else { failed = true; continue }
            do {
                let result = try store.install(item, data: data, keepOff: true)
                let name = store.installed.first { $0.id == item.id }.map(store.displayName) ?? item.displayName
                items.append(Recent.Item(id: item.id, name: name, version: item.version, added: result.new - (result.old ?? result.new), builtin: false))
            } catch {
                failed = true
            }
            status = .downloading(count: count, done: items.count)
        }
        for update in pending.builtins {
            guard !Task.isCancelled else { failed = true; break }
            guard let url = ExtDictCatalog.resolve(update.url), let data = await Self.fetch(url, constrained: manual) else { failed = true; continue }
            do {
                let result = try store.installBuiltin(update, data: data)
                let name = ExtDict.builtins.first { $0.id == update.id }?.name ?? update.id
                items.append(Recent.Item(id: update.id, name: name, version: update.version, added: result.new - (result.old ?? result.new), builtin: true))
            } catch {
                failed = true
            }
            status = .downloading(count: count, done: items.count)
        }
        if !items.isEmpty {
            // 同一天又更新了几个：并进同一条提示。
            var merged = recent.flatMap { Calendar.current.isDateInToday($0.date) ? $0.items : nil } ?? []
            for item in items {
                if let index = merged.firstIndex(where: { $0.id == item.id }) {
                    merged[index].version = item.version
                    merged[index].added += item.added
                } else {
                    merged.append(item)
                }
            }
            recent = Recent(date: Date(), items: merged)
            // 前台：合并成一次部署。后台：只换文件，回到前台时 deployIfNeeded 部署（后台刷新只给 30 秒左右）。
            if !background && UIApplication.shared.applicationState == .active {
                store.deploySoon()
            }
        }
        if failed {
            fail()
            return false
        }
        lastCheck = Date()
        lastFailure = nil
        status = .idle
        return true
    }

    private func fail() {
        lastFailure = Date()
        status = .failed
    }

    private func showUpToDate() {
        status = .upToDate
        resetStatus = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, status == .upToDate else { return }
            status = .idle
        }
    }

    /// 下一个词库文件。constrained：低数据模式下能不能下（手动的能）。
    private static func fetch(_ url: URL, constrained: Bool) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.allowsConstrainedNetworkAccess = constrained
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// 后台刷新时间到了：停下（下了一半的不换，下次再来）。
    func cancel() {
        running?.cancel()
    }

    // MARK: 热门词库页

    /// 刚更新的词库（「刚更新」绿标）。
    var recentIDs: Set<String> { Set(recent?.items.map(\.id) ?? []) }

    /// 离开热门词库页：去掉提示和「刚更新」，记下看过的在线词库（「新」去掉）。
    func pageLeft(catalog: [String]) {
        recent = nil
        seenIDs = (seenIDs ?? []).union(catalog)
        UserDefaults.standard.set(seenIDs?.sorted(), forKey: Self.seenKey)
    }

    /// 下次自动检查的时间：失败后 1 天，平时上次成功检查后 7 天。
    var nextDue: Date {
        if let lastFailure, lastCheck.map({ lastFailure.isAfter($0) }) ?? true {
            return lastFailure.addingTimeInterval(DictUpdatePolicy.retryAfterFailure)
        }
        return (lastCheck ?? Date()).addingTimeInterval(DictUpdatePolicy.interval)
    }

    nonisolated private static func loadRecent() -> Recent? {
        guard let data = UserDefaults.standard.data(forKey: recentKey) else { return nil }
        return try? JSONDecoder().decode(Recent.self, from: data)
    }

    nonisolated private static func saveRecent(_ recent: Recent?) {
        if let recent, let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: recentKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recentKey)
        }
    }
}

/// 后台刷新（BGAppRefreshTask）：用户很久不打开 App 也能更新词库。系统什么时候真跑由它定；
/// 关了「后台 App 刷新」或开了低电量模式时不跑，只靠打开 App 时检查。照 ICloudSyncScheduler 的写法。
enum DictUpdateScheduler {
    /// 和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 对应（scripts/icloud-background-modes.py 每个包都加上）。
    static var refreshID: String { (Bundle.main.bundleIdentifier ?? "enclave") + ".dicts.refresh" }

    /// App 启动时（didFinishLaunching 返回前）注册。
    static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { handle($0) }
    }

    /// 退到后台、开关改了时排下一次；关着时取消已经排上的。
    @MainActor
    static func schedule() {
        guard DictAutoUpdate.shared.enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date.later(DictAutoUpdate.shared.nextDue, Date(timeIntervalSinceNow: 15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        let finish = Once { task.setTaskCompleted(success: $0) }
        let work = Task { @MainActor in
            let auto = DictAutoUpdate.shared
            let ok = DictUpdatePolicy.isDue(now: Date(), lastCheck: auto.lastCheck, lastFailure: nil, enabled: auto.enabled)
                ? await auto.run(manual: false, background: true) : true
            schedule()
            finish(ok)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in DictAutoUpdate.shared.cancel() }
            finish(false)
        }
    }

    /// 后台任务的完成只能报一次（时间到和做完可能一前一后）。
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let body: (Bool) -> Void

        init(_ body: @escaping (Bool) -> Void) { self.body = body }

        func callAsFunction(_ success: Bool) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { body(success) }
        }
    }
}
