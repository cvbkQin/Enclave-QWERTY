import Foundation

/// 剪贴板记录（B1，CB1–CB4，对齐清单第 56 条）：九宫格「常用 › 剪贴板」里粘贴过的文字。
/// 只在用户点「有新复制的内容，点一下粘贴」时才读系统剪贴板；判断有没有新内容只看 changeCount 和 hasStrings，不读内容。
/// 存在 App Group 的文件里，只在本机：最多 20 条，超过 24 小时自动删除。不备份、不同步、不上传。
struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

enum ClipboardHistory {
    static let maxItems = 20
    static let lifetime: TimeInterval = 24 * 3600
    private static let enabledKey = "clipboard.history.enabled"
    private static let changeCountKey = "clipboard.lastChangeCount"
    /// App 和键盘都会写这个文件，按顺序来。
    private static let queue = DispatchQueue(label: "enclave.clipboard")

    /// 「剪贴板记录」开关，默认开。关掉时已有的一起删掉。
    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set {
            SharedStorage.defaults.set(newValue, forKey: enabledKey)
            if !newValue { clear() }
        }
    }

    /// 上次看过（粘贴过、或者自己写进剪贴板）时系统剪贴板的 changeCount；没有记录时为 nil。
    static var lastChangeCount: Int? {
        get { SharedStorage.defaults.object(forKey: changeCountKey) as? Int }
        set { SharedStorage.defaults.set(newValue, forKey: changeCountKey) }
    }

    /// 有没有新复制的内容：changeCount 变了，而且里面有文字。不读内容，系统不弹提示。
    static func hasNew(changeCount: Int, hasStrings: Bool) -> Bool {
        hasStrings && changeCount != lastChangeCount
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
        guard isEnabled, !text.isEmpty else { return load(now: now) }
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

    static func inserting(_ text: String, into items: [ClipItem], now: Date) -> [ClipItem] {
        var list = pruned(items, now: now)
        if let index = list.firstIndex(where: { $0.text == text }) {
            var item = list.remove(at: index)
            item.date = now
            list.insert(item, at: 0)
        } else {
            list.insert(ClipItem(text: text, date: now), at: 0)
        }
        return Array(list.prefix(maxItems))
    }

    static func pruned(_ items: [ClipItem], now: Date) -> [ClipItem] {
        let cutoff = now.addingTimeInterval(-lifetime)
        return Array(items.filter { $0.date > cutoff }.sorted { $0.date > $1.date }.prefix(maxItems))
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
