import BackgroundTasks
import CloudKit
import UIKit

/// 什么时候同步（specs/icloud-sync/iCloud同步方案.md 1.9、3.4）：打开 App、回到前台由 EnclaveApp 调；
/// 这里管后台的三种：后台刷新（系统定频率）、充电时的后台任务（一般在夜里）、别的设备改了东西时的静默推送。
/// 关了「后台 App 刷新」或开了低电量模式时，系统这三种都不给，只在打开 App 时同步。
enum ICloudSyncScheduler {
    /// 和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 对应；不在那里面的注册会闪退。
    static var refreshID: String { (Bundle.main.bundleIdentifier ?? "enclave") + ".sync.refresh" }
    static var processingID: String { (Bundle.main.bundleIdentifier ?? "enclave") + ".sync.processing" }

    /// App 启动时（didFinishLaunching 返回前）注册。包里没有 iCloud 能力时什么都不做。
    static func register() {
        guard ICloudSync.isAvailable else { return }
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { handle($0) }
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: processingID, using: nil) { handle($0) }
    }

    /// 退到后台时、打开同步时排下一次。同步关着时取消已经排上的。
    static func schedule() {
        guard ICloudSync.isAvailable else { return }
        guard ICloudSync.isEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingID)
            return
        }
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(refresh)
        let processing = BGProcessingTaskRequest(identifier: processingID)
        processing.requiresExternalPower = true
        processing.requiresNetworkConnectivity = true
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(processing)
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let finish = Once { task.setTaskCompleted(success: $0) }
        let work = Task {
            let status = await ICloudSync.syncNow()
            finish(status?.result == .ok || status?.result == .keyboardBusy)
        }
        // 时间到了：系统要挂起 App。拼音词库是在 App 自己的目录里的副本上合并的，挂起不会因为 App Group 里的锁被杀，下次重来就行。
        task.expirationHandler = {
            work.cancel()
            finish(false)
        }
    }

    /// 别的设备改了东西（CloudKit 的静默推送）。
    static func handleRemoteNotification(_ userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard ICloudSync.isEnabled, CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completion(.noData)
            return
        }
        Task {
            let status = await ICloudSync.syncNow()
            completion(status?.result == .ok ? .newData : .failed)
        }
    }

    /// 后台任务的完成只能报一次（时间到和做完可能一前一后）。
    private final class Once {
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

/// 只为后台任务注册和静默推送加的 App 代理；别的都还在 SwiftUI 的 EnclaveApp 里。
final class EnclaveAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ICloudSyncScheduler.register()
        // 从 8118b83 升级上来、开着 Key 同步却没有配对表的测试机：配上现在的 Key（04 复审 A 可选 7）。
        if ICloudSync.isAvailable { Keychain.migrateBindingsIfNeeded(accounts: BackupService.keyAccounts()) }
        if ICloudSync.isEnabled {
            application.registerForRemoteNotifications()
        } else {
            // 总开关关着、Key 的同步还开着（上次关的时候钥匙串读写没成）：再关一次。
            ICloudSync.stopKeySync()
        }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        ICloudSyncScheduler.handleRemoteNotification(userInfo, completion: completionHandler)
    }
}
