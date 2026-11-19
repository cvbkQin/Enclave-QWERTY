import UIKit

/// 测试 iCloud 同步用的开关（界面等 02 的稿子，做好后删掉这个文件和 EnclaveApp 里的 enclave://icloud-sync）。
/// 只在开发者版、测试包里能用（BuiltinAPI.showsTesterTools），正式版不认这个链接。
/// - enclave://icloud-sync/on：打开同步并马上同步一次
/// - enclave://icloud-sync/off：关闭同步（iCloud 里的数据不动）
/// - enclave://icloud-sync/now：立即同步
/// - enclave://icloud-sync/keys-on、/keys-off：打开、关闭 API Key 的 iCloud 钥匙串同步（关闭时同步版留在 iCloud 里）
enum ICloudSyncDebug {
    static func handle(_ path: String) {
        guard ICloudSync.isAvailable else { return }
        switch path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "on":
            ICloudSync.isEnabled = true
            UIApplication.shared.registerForRemoteNotifications()
            ICloudSyncScheduler.schedule()
            Task { await ICloudSync.syncNow() }
        case "off":
            ICloudSync.isEnabled = false
            ICloudSyncScheduler.schedule()
        case "now":
            Task { await ICloudSync.syncNow() }
        case "keys-on":
            // Key 要配上同步过来的接口配置才有用（方案 4.2）：词库同步没开时不开。
            guard ICloudSync.isEnabled else { return }
            _ = Keychain.enableSync(accounts: BackupService.keyAccounts())
        case "keys-off":
            Keychain.disableSync(accounts: BackupService.keyAccounts(), removeFromICloud: false)
        default:
            break
        }
    }
}
