import Foundation
import Security

/// API Key 存在钥匙串里，访问组是 App Group，键盘也能读。
///
/// iCloud 同步（specs/icloud-sync/iCloud同步方案.md 第 4 节）：每个账户名最多有两份。
/// - 本机版：AfterFirstUnlockThisDeviceOnly，不进 iCloud、不进整机备份（以前只有这一份）。
/// - 同步版：AfterFirstUnlock + kSecAttrSynchronizable，经 iCloud 钥匙串端到端加密同步到同一 Apple 账户的其他设备。
/// 读写时都写明是哪一份：不写的话系统只认本机版，「先删后加」会删不到同步版、再加时报重复，Key 就存不进去。
/// 别的设备开着同步时，同步版也会出现在关着同步的设备上；关着同步的设备只读本机版，不受影响。
enum Keychain {
    private static let service = "Enclave"
    /// 「通过 iCloud 钥匙串同步 API Key」：每台设备自己的开关，存在共享设置里（键盘读 Key 时要知道读哪份），不跟着同步走。
    static let syncDefaultsKey = "sync.keychain"

    /// 开着同步：读写同步版。带内置 Key 的包永远只用本机版，免得内置 Key 同步到别的设备上。
    static var syncsToICloud: Bool {
        !BuiltinAPI.available && SharedStorage.defaults.bool(forKey: syncDefaultsKey)
    }

    private static func baseQuery(_ account: String, synced: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synced ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]
        if let group = SharedStorage.keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func read(_ account: String, synced: Bool) -> String? {
        var query = baseQuery(account, synced: synced)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 有就改、没有就加：不先删，改的时候出错也不会把原来的 Key 弄丢。
    private static func write(_ value: String, account: String, synced: Bool) -> Bool {
        let query = baseQuery(account, synced: synced)
        // 键盘在锁屏后首次解锁前也可能被调起，用 AfterFirstUnlock；同步版不能带 ThisDeviceOnly。
        let accessible = synced ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let changes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: accessible,
        ]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes.merge(changes) { _, new in new }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(_ account: String, synced: Bool) {
        SecItemDelete(baseQuery(account, synced: synced) as CFDictionary)
    }

    /// 开着同步时先读同步版，没有（比如刚打开、还没同步过来）再读本机版；关着时只读本机版。
    static func get(_ account: String) -> String? {
        if syncsToICloud, let value = read(account, synced: true) { return value }
        return read(account, synced: false)
    }

    /// 存一个 Key；nil 或空字符串是删掉。开着同步时写同步版、删本机版（以后不用它了）；删除时两份都删，
    /// 同步版一删，其他设备上的也没了（删接口配置时就是要这样）。关着同步时只动本机版。
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let synced = syncsToICloud
        guard let value, !value.isEmpty else {
            delete(account, synced: false)
            if synced { delete(account, synced: true) }
            return true
        }
        guard write(value, account: account, synced: synced) else { return false }
        if synced { delete(account, synced: false) }
        return true
    }

    /// 打开同步：本机有、同步版还没有的 Key 写一份同步版，读回来对得上再删本机版。
    /// 同步版已经有了（别的设备先开的）就用同步版，本机版留着不动（关同步时会被同步版盖掉）。
    /// 有一个没写成就返回 false，开关不打开。
    static func enableSync(accounts: [String]) -> Bool {
        guard !BuiltinAPI.available else { return false }
        for account in accounts {
            guard let local = read(account, synced: false) else { continue }
            if read(account, synced: true) != nil { continue }
            guard write(local, account: account, synced: true), read(account, synced: true) == local else { return false }
            delete(account, synced: false)
        }
        SharedStorage.defaults.set(true, forKey: syncDefaultsKey)
        return true
    }

    /// 关闭同步：同步版复制回本机版，以后只读本机版。removeFromICloud 时再删掉同步版，其他设备上的也会一起没了。
    /// 有一个没复制成就返回 false，开关保持打开（不然那个 Key 就读不到了）。
    @discardableResult
    static func disableSync(accounts: [String], removeFromICloud: Bool) -> Bool {
        var copied: [String] = []
        for account in accounts {
            guard let value = read(account, synced: true) else { continue }
            guard write(value, account: account, synced: false), read(account, synced: false) == value else { return false }
            copied.append(account)
        }
        SharedStorage.defaults.set(false, forKey: syncDefaultsKey)
        if removeFromICloud {
            for account in copied { delete(account, synced: true) }
        }
        return true
    }
}
