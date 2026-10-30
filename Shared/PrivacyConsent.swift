import Foundation

/// 隐私政策同意情况（大陆上架合规，CP1–CP7）：存在 App Group 里，键盘读它决定能不能用 AI。
/// 和 ConsentStore（按接口地址的发送确认）是两层：这里先同意隐私政策，发送前再确认地址。
enum PrivacyConsent {
    /// 隐私政策有实质更新时加 1，所有人重新看一次说明页。
    static let currentVersion = 4

    private static let agreedVersionKey = "privacy.agreedVersion"
    private static let agreedDateKey = "privacy.agreedAt"
    /// 看过哪一版的说明页（同意或选了「仅使用基础功能」都算），比 currentVersion 小就再弹。
    private static let seenVersionKey = "privacy.seenVersion"

    static var agreedVersion: Int { SharedStorage.defaults.integer(forKey: agreedVersionKey) }
    static var agreedDate: Date? { SharedStorage.defaults.object(forKey: agreedDateKey) as? Date }

    /// 同意了当前这一版。App Group 不可用时键盘读不到 App 里的选择，只能放行（免费签名的开发版才会这样）。
    static var isAgreed: Bool {
        if !SharedStorage.isShared && Bundle.main.bundlePath.hasSuffix(".appex") { return true }
        return agreedVersion >= currentVersion
    }

    /// 打开 App 时要不要整页显示隐私说明。
    static var needsPrompt: Bool {
        SharedStorage.defaults.integer(forKey: seenVersionKey) < currentVersion
    }

    /// 以前看过（同意或选了基础功能）旧版说明，这次是因为政策更新才再弹：说明页顶上显示更新了什么。首次安装为 false。
    static var isUpdate: Bool {
        let seen = SharedStorage.defaults.integer(forKey: seenVersionKey)
        return seen > 0 && seen < currentVersion
    }

    static func agree() {
        let defaults = SharedStorage.defaults
        defaults.set(currentVersion, forKey: agreedVersionKey)
        defaults.set(Date(), forKey: agreedDateKey)
        defaults.set(currentVersion, forKey: seenVersionKey)
    }

    /// 「仅使用基础功能」：记下看过，不再每次弹；AI 关着。
    static func useBasicOnly() {
        revoke()
        SharedStorage.defaults.set(currentVersion, forKey: seenVersionKey)
    }

    /// 撤回同意：回到基础功能，设置、常用词和接口都留着。
    static func revoke() {
        SharedStorage.defaults.removeObject(forKey: agreedVersionKey)
        SharedStorage.defaults.removeObject(forKey: agreedDateKey)
    }

    #if DEBUG
    static func resetForTesting() {
        revoke()
        SharedStorage.defaults.removeObject(forKey: seenVersionKey)
    }
    #endif
}
