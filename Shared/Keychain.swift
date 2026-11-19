import CryptoKit
import Foundation
import Security

/// API Key 存在钥匙串里，访问组是 App Group，键盘也能读。
///
/// iCloud 同步（specs/icloud-sync/iCloud同步方案.md 第 4 节）：每个账户名最多有两份。
/// - 本机版：AfterFirstUnlockThisDeviceOnly，不进 iCloud、不进整机备份（以前只有这一份）。
/// - 同步版：AfterFirstUnlock + kSecAttrSynchronizable，经 iCloud 钥匙串端到端加密同步到同一 Apple 账户的其他设备。
/// 读写时都写明是哪一份：不写的话系统只认本机版，「先删后加」会删不到同步版、再加时报重复，Key 就存不进去。
/// 别的设备开着同步时，同步版也会出现在关着同步的设备上；关着同步的设备只读本机版，不受影响。
///
/// 配对（04 审查 #75 第 2 条）：同步版的 Key 由 iCloud 钥匙串送到，接口地址由 CloudKit 送到，谁先到不一定。
/// 每台设备记着「本机的接口配置配的是哪个 Key」（Key 的指纹，存在共享设置里）。同步版的 Key 和记的指纹对不上
/// （别的设备换了 Key，新地址还没同步过来），就当没有 Key，不拿它去请求旧地址；同步把新地址写进本机时再更新指纹。
enum Keychain {
    private static let service = "Enclave"
    /// 「通过 iCloud 钥匙串同步 API Key」：每台设备自己的开关，存在共享设置里（键盘读 Key 时要知道读哪份），不跟着同步走。
    static let syncDefaultsKey = "sync.keychain"
    private static let bindingsKey = "sync.keyBindings"

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
        lookup(account, synced: synced).value
    }

    /// 读一份，连同结果码：「没有」（errSecItemNotFound）和「现在读不了」（开机后还没解锁过等）要分开，
    /// 开关同步时读不了就不动，不然会当成没有 Key。
    private static func lookup(_ account: String, synced: Bool) -> (value: String?, readable: Bool) {
        var query = baseQuery(account, synced: synced)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return (nil, status == errSecItemNotFound) }
        return (String(data: data, encoding: .utf8), true)
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

    /// 关着同步时只读本机版。开着时读和本机配的指纹对得上的那份（见上面「配对」）：先看同步版，再看本机版；
    /// 都对不上（别的设备换了 Key、新地址还没同步过来）就当没有。
    static func get(_ account: String) -> String? {
        guard syncsToICloud else { return read(account, synced: false) }
        let bound = binding(account)
        if let value = read(account, synced: true), fingerprint(value) == bound { return value }
        if let value = read(account, synced: false), fingerprint(value) == bound { return value }
        return nil
    }

    /// 存一个 Key；nil 或空字符串是删掉。开着同步时写同步版、删本机版（以后不用它了）；删除时两份都删，
    /// 同步版一删，其他设备上的也没了（删接口配置时就是要这样）。关着同步时只动本机版。
    /// 开着同步时同时记下本机配的是这个 Key。
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let synced = syncsToICloud
        guard let value, !value.isEmpty else {
            delete(account, synced: false)
            if synced {
                delete(account, synced: true)
                bind([account: fingerprint(nil)])
            }
            return true
        }
        guard write(value, account: account, synced: synced) else { return false }
        if synced {
            delete(account, synced: false)
            bind([account: fingerprint(value)])
        }
        return true
    }

    // MARK: 配对

    /// Key 的指纹：SHA-256 的前 16 位十六进制，只用来比对是不是同一个 Key，推不回 Key。没有 Key 是空字符串。
    static func fingerprint(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(("enclave.key." + value).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// 本机的接口配置配的 Key 的指纹；没记过是空字符串（当没有 Key）。
    static func binding(_ account: String) -> String {
        (SharedStorage.defaults.dictionary(forKey: bindingsKey) as? [String: String])?[account] ?? ""
    }

    /// 同步把别的设备的接口配置写进本机时调：本机从此配这些 Key。
    static func bind(_ fingerprints: [String: String]) {
        var all = (SharedStorage.defaults.dictionary(forKey: bindingsKey) as? [String: String]) ?? [:]
        all.merge(fingerprints) { _, new in new }
        SharedStorage.defaults.set(all, forKey: bindingsKey)
    }

    /// 钥匙串里现在实际是哪个 Key（不看配对）：同步时判断别的设备的配置能不能用到本机。
    static func currentFingerprint(_ account: String) -> String {
        if syncsToICloud, let value = read(account, synced: true) { return fingerprint(value) }
        return fingerprint(read(account, synced: false))
    }

    /// 设置页「N 个 Key 通过 iCloud 钥匙串同步」：本机在用的 Key 里，有几个是同步版。
    static func syncedCount(accounts: [String]) -> Int {
        guard syncsToICloud else { return 0 }
        return accounts.filter { account in
            guard let value = read(account, synced: true) else { return false }
            return fingerprint(value) == binding(account)
        }.count
    }

    /// 打开同步：本机有、同步版还没有的 Key 写一份同步版，读回来对得上再删本机版。
    /// 同步版已经有了（别的设备先开的）：本机版留着不动、本机继续用它，等同步把那台的接口配置写进本机时改用同步版。
    /// 有一个没写成就返回 false，开关不打开。
    static func enableSync(accounts: [String]) -> Bool {
        guard !BuiltinAPI.available else { return false }
        var bindings: [String: String] = [:]
        for account in accounts {
            let synced = lookup(account, synced: true)
            guard synced.readable, lookup(account, synced: false).readable else { return false }
            if synced.value != nil {
                // 别的设备先开了，同步版是那台的 Key：本机现在的地址还配本机原来的 Key（可能没有），
                // 所以同步版先不能用，等同步把那台的地址写进本机时再配上，免得拿那台的 Key 请求本机的地址。
                bindings[account] = fingerprint(read(account, synced: false))
                continue
            }
            guard let local = read(account, synced: false) else {
                bindings[account] = ""
                continue
            }
            guard write(local, account: account, synced: true), read(account, synced: true) == local else { return false }
            delete(account, synced: false)
            bindings[account] = fingerprint(local)
        }
        bind(bindings)
        SharedStorage.defaults.set(true, forKey: syncDefaultsKey)
        return true
    }

    /// 关闭同步：本机配的那份同步版复制回本机版，以后只读本机版。和本机配的对不上的同步版（别的设备的 Key）不复制，
    /// 本机版保持原样。removeFromICloud 时再删掉复制过的同步版，其他设备上的也会一起没了。
    /// 有一个没复制成就返回 false，开关保持打开（不然那个 Key 就读不到了）。
    @discardableResult
    static func disableSync(accounts: [String], removeFromICloud: Bool) -> Bool {
        var copied: [String] = []
        for account in accounts {
            let synced = lookup(account, synced: true)
            guard synced.readable else { return false }
            guard let value = synced.value, fingerprint(value) == binding(account) else { continue }
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
