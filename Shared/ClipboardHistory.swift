import Foundation

/// 剪贴板记录（B1，CB1–CB4，对齐清单第 56 条；T97 点开就存，design/clipboard-autosave）：键盘「常用 › 剪贴板」里你复制过的文字。
/// 点开剪贴板一栏时才读系统剪贴板：有新复制的文字就存成第一条，不粘贴；判断有没有新内容只看 changeCount 和 hasStrings，不读内容。
/// 密码管理器复制的密码（条目带隐藏标记）、纯数字（detectPatterns）不读不存。
/// 存在 App Group 的文件里，只在本机：最多 N 条（10 / 20 / 50 / 100，默认 20），超过 24 小时自动删除。不备份、不同步、不上传。
struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

enum ClipboardHistory {
    /// 「最多保存条数」能选的几档（cvbk 11-25），默认 20（同以前）。
    static let limitOptions = [10, 20, 50, 100]
    static let defaultLimit = 20
    static let lifetime: TimeInterval = 24 * 3600
    private static let enabledKey = "clipboard.history.enabled"
    private static let changeCountKey = "clipboard.lastChangeCount"
    private static let limitKey = "clipboard.maxCount"
    private static let leftPanelKey = "clipboard.panelLeftAt"
    private static let autoSaveKey = "clipboard.autoSave"
    private static let consentKey = "clipboard.autoSave.consentAt"
    /// App 和键盘都会写这个文件，按顺序来。
    private static let queue = DispatchQueue(label: "enclave.clipboard")

    /// 「剪贴板记录」开关，默认开。关掉时已有的一起删掉。
    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set {
            SharedStorage.defaults.set(newValue, forKey: enabledKey)
            if !newValue {
                clear()
                // 记录关了，自动保存也跟着关；再打开记录，自动保存还是关，要用户自己再开（CA3 ④）。
                autoSave = false
            }
        }
    }

    /// 「自动保存复制的内容」（T97 方案 B，CA2、CA3）：键盘显示时一发现新复制的文字就读出来存。默认关，新装、升级都是关。
    static var autoSave: Bool {
        get { SharedStorage.defaults.bool(forKey: autoSaveKey) }
        set { SharedStorage.defaults.set(newValue, forKey: autoSaveKey) }
    }

    /// 自动保存真的在运行：开关开着，剪贴板记录也开着。
    static var autoSaveActive: Bool { isEnabled && autoSave }

    /// 最近一次在确认卡上点「开启」的时间（本机），作为同意的记录；每次从关拨到开都弹卡，点「开启」就更新成这一次（对齐清单第 97 条）。
    static var autoSaveConsentAt: Date? {
        get { (SharedStorage.defaults.object(forKey: consentKey) as? Double).map { Date(timeIntervalSince1970: $0) } }
        set {
            if let newValue {
                SharedStorage.defaults.set(newValue.timeIntervalSince1970, forKey: consentKey)
            } else {
                SharedStorage.defaults.removeObject(forKey: consentKey)
            }
        }
    }

    /// 拨自动保存开关时要不要先弹确认卡（cvbk 11-26 08:26，对齐清单第 97 条）：每次从关拨到开都弹，不看以前同意过没有；从开拨到关不弹。
    static func needsAutoSaveConsent(wasOn: Bool, turningOn: Bool) -> Bool { turningOn && !wasOn }

    /// 最多保存条数：App 设、键盘读同一个值；只在本机，不同步、不备份。存的值不在几档里时按 20。
    static var maxItems: Int {
        let stored = SharedStorage.defaults.integer(forKey: limitKey)
        return limitOptions.contains(stored) ? stored : defaultLimit
    }

    /// 改最多保存条数：改小时顺手删掉最早的几条（App 里先确认过）。
    static func setMaxItems(_ value: Int) {
        guard limitOptions.contains(value) else { return }
        SharedStorage.defaults.set(value, forKey: limitKey)
        queue.sync {
            let items = read()
            let kept = trimmed(items, limit: value)
            if kept.count != items.count { write(kept) }
        }
    }

    /// 改成 limit 条会删掉几条（App 的确认框用）。
    static func removedCount(current: Int, limit: Int) -> Int { max(0, current - limit) }

    /// 上次离开「常用 / 剪贴板」面板的时间：之后存进来的记录在键盘里标「新」。各个 App 里的键盘共用。
    static var panelLeftAt: Date? {
        get {
            let value = SharedStorage.defaults.double(forKey: leftPanelKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue {
                SharedStorage.defaults.set(newValue.timeIntervalSince1970, forKey: leftPanelKey)
            } else {
                SharedStorage.defaults.removeObject(forKey: leftPanelKey)
            }
        }
    }

    /// 上次看过（存过、粘贴过、或者自己写进剪贴板）时系统剪贴板的 changeCount；没有记录时为 nil。
    static var lastChangeCount: Int? {
        get { SharedStorage.defaults.object(forKey: changeCountKey) as? Int }
        set { SharedStorage.defaults.set(newValue, forKey: changeCountKey) }
    }

    /// 有没有新复制的内容：changeCount 变了，而且里面有文字。不读内容，系统不弹提示。
    static func hasNew(changeCount: Int, hasStrings: Bool) -> Bool {
        hasStrings && changeCount != lastChangeCount
    }

    /// 点开剪贴板时读不读：记录开着、剪贴板一栏露出来（没收起成竖条）、有新复制的文字，三条都满足才读。
    static func shouldCapture(enabled: Bool, columnVisible: Bool, changeCount: Int, hasStrings: Bool, last: Int?) -> Bool {
        enabled && columnVisible && hasStrings && changeCount != last
    }

    /// 密码管理器复制的密码等：条目类型带这些标记时不读不存（只看类型，不读内容，系统不弹提示）。
    static let concealedTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]

    static func isConcealed(types: [String]) -> Bool {
        types.contains { concealedTypes.contains($0) }
    }

    /// 键盘里标「新」：上次离开面板以后存进来的。
    static func isNew(_ item: ClipItem, since: Date) -> Bool {
        item.date > since
    }

    static var fileURL: URL? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return container.appendingPathComponent("Clipboard/history.json")
    }

    /// 新的在前，读的时候顺手删掉过期的。
    static func load(now: Date = Date()) -> [ClipItem] {
        queue.sync {
            let items = read()
            let kept = pruned(items, now: now)
            if kept.count != items.count { write(kept) }
            return kept
        }
    }

    static var count: Int { load().count }

    /// 存一条放在最前；和已有的一条相同时不重复存，把那条挪到最前（时间换成现在）。关着开关时不存。
    @discardableResult
    static func add(_ text: String, now: Date = Date()) -> [ClipItem] {
        // 「复制配置」那段带 API Key，不进记录（点开就存、自动保存都会读到它）。
        guard isEnabled, !text.isEmpty, !SettingsStore.isExportString(text) else { return load(now: now) }
        return queue.sync {
            let items = inserting(text, into: read(), now: now)
            write(items)
            return items
        }
    }

    static func remove(_ id: UUID) {
        queue.sync { write(read().filter { $0.id != id }) }
    }

    static func clear() {
        queue.sync {
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - 纯逻辑（单元测试用）

    static func inserting(_ text: String, into items: [ClipItem], now: Date, limit: Int? = nil) -> [ClipItem] {
        let cap = limit ?? maxItems
        var list = pruned(items, now: now, limit: cap)
        if let index = list.firstIndex(where: { $0.text == text }) {
            var item = list.remove(at: index)
            item.date = now
            list.insert(item, at: 0)
        } else {
            list.insert(ClipItem(text: text, date: now), at: 0)
        }
        return Array(list.prefix(cap))
    }

    static func pruned(_ items: [ClipItem], now: Date, limit: Int? = nil) -> [ClipItem] {
        let cutoff = now.addingTimeInterval(-lifetime)
        return trimmed(items.filter { $0.date > cutoff }, limit: limit ?? maxItems)
    }

    /// 新的在前，只留 limit 条：超过就删掉最早的。
    static func trimmed(_ items: [ClipItem], limit: Int) -> [ClipItem] {
        Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// 列表右上角的时间：刚刚 / N 分钟前 / N 小时前。
    static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return L("刚刚", "Just now", "たった今") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("\(minutes) 分钟前", "\(minutes) min ago", "\(minutes) 分前") }
        let hours = minutes / 60
        return L("\(hours) 小时前", "\(hours) hr ago", "\(hours) 時間前")
    }

    private static func read() -> [ClipItem] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }

    private static func write(_ items: [ClipItem]) {
        guard let url = fileURL else { return }
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 锁屏下也可能用键盘：文件保护放宽到第一次解锁后。
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
