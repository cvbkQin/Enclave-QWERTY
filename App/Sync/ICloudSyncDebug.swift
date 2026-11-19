import UIKit

/// 测试 iCloud 同步用的开关（模拟器和两台真机来回测时比点界面快；正式发版前可以删掉这个文件和 EnclaveApp 里的 enclave://icloud-sync）。
/// 只在 Debug 和开发者版装机（DEV_BUILD=YES）里认：TestFlight、公测、正式包都不认，别的 App 打开这个链接也开不了同步
/// （04 审查 #75 第 5 条）。
/// - enclave://icloud-sync/on：打开同步并马上同步一次
/// - enclave://icloud-sync/off：关闭同步（Key 的同步一起关；iCloud 里的数据不动）
/// - enclave://icloud-sync/now：立即同步
/// - enclave://icloud-sync/keys-on、/keys-off：打开、关闭 API Key 的 iCloud 钥匙串同步（关闭时同步版留在 iCloud 里）
enum ICloudSyncDebug {
    static var isAllowed: Bool {
        #if DEBUG
        return true
        #else
        return BuiltinAPI.isDevBuild && !BuiltinAPI.isInternalBuild && !BuiltinAPI.isPublicBuild
        #endif
    }

    static func handle(_ path: String) {
        guard isAllowed, ICloudSync.isAvailable else { return }
        switch path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "on":
            ICloudSync.enable()
            UIApplication.shared.registerForRemoteNotifications()
            ICloudSyncScheduler.schedule()
            Task { await ICloudSync.syncNow() }
        case "off":
            ICloudSync.disable()
            ICloudSyncScheduler.schedule()
        case "now":
            Task { await ICloudSync.syncNow() }
        case "keys-on":
            // Key 要配上同步过来的接口配置才有用（方案 4.2）：词库同步没开时不开。
            guard ICloudSync.isEnabled else { return }
            if Keychain.enableSync(accounts: BackupService.keyAccounts(), iCloudWins: false) {
                ICloudSync.prefersLocalEndpoint = true
                Task { await ICloudSync.syncNow() }
            }
        case "keys-off":
            Keychain.disableSync(accounts: BackupService.keyAccounts(), removeFromICloud: false)
        default:
            break
        }
    }
}
