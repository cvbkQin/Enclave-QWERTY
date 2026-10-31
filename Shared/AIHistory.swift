import Foundation

/// 润色和问答的历史（第 48 条，效果图 design/ai-history/）：键盘每一轮 EditSession 记一条，App 的「历史」标签读。
/// 存在 App Group 里单独的文件（History/ai-history.json），只在本机，不上传。
/// 一轮还没结束也先记：会话每存一次（出了新版、手改、替换 / 插入）就把这一条更新成最新的样子，键盘被系统回收也不丢。
struct AIHistoryEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case polish, answer }
    enum Use: String, Codable { case replaced, inserted }

    struct Version: Codable, Equatable {
        var text: String
        var edited = false
        var style: String?
        var provider: String?
        /// 联网回答过的：哪一家。
        var searchedBy: String?
        var use: Use?
        /// 时间线（0.95_7 起记，旧记录没有）：出来的时间、怎么来的（EditSession.VersionSource）、用时、
        /// 手改的是第几版、联网搜索的时间和是否自动、替换 / 插入的时间。
        var at: Date?
        var source: String?
        var ms: Int?
        var editedFrom: Int?
        var searchAt: Date?
        var searchAuto: Bool?
        var usedAt: Date?
    }

    var id: String
    var kind: Kind
    var date: Date
    /// 润色：原文；问答：问题（帮我写：第一句要求）。
    var original: String
    /// 问答一起发送的上下文（输入框里光标前的文字），没有就是空。
    var context: String
    var versions: [Version]

    /// 用过的那版（替换 / 插入了的，有几版就取最后一版）；没用就是 nil。
    var usedIndex: Int? { versions.lastIndex { $0.use != nil } }

    /// 列表上显示的那版：用过的那版，没用就最后一版。
    var shownIndex: Int { usedIndex ?? max(versions.count - 1, 0) }
    var shown: String { versions.indices.contains(shownIndex) ? versions[shownIndex].text : "" }
    var searched: Bool { versions.contains { $0.searchedBy != nil } }

    /// 更新前记的：每一版都没有时间，时间线不写每一步的时间。
    var isLegacy: Bool { !versions.contains { $0.at != nil } }

    /// 最后一步的时间（替换 / 插入，没有就最后一版出来的时间）。
    var endDate: Date? {
        (versions.compactMap(\.usedAt) + versions.compactMap(\.at)).max()
    }

    /// 搜索：原文、上下文、所有版本，大小写不敏感。
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([original, context] + versions.map(\.text)).contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// 由一轮会话生成。没出任何结果的不记（返回 nil）。
    init?(session: EditSession) {
        guard let id = session.historyID, !session.versions.isEmpty else { return nil }
        let answers = session.answerVersions ?? []
        let firstAnswer = answers.min()
        self.id = id
        kind = session.mode == .write || firstAnswer != nil ? .answer : .polish
        date = session.startedAt ?? Date()
        let source = firstAnswer.flatMap { session.askSources?[String($0)] }
        original = source?.question ?? session.original
        context = source?.context ?? ""
        versions = session.versions.enumerated().map { index, text in
            let key = String(index)
            let info = session.versionInfo?[key]
            return Version(text: text, edited: session.editedVersions?.contains(index) ?? false,
                           style: info?.style, provider: info?.provider,
                           searchedBy: session.searchedVersions?[key],
                           use: session.usedVersions?[key].flatMap(Use.init(rawValue:)),
                           at: info?.at, source: info?.source, ms: info?.ms, editedFrom: info?.editedFrom,
                           searchAt: info?.searchAt, searchAuto: info?.searchAuto, usedAt: session.usedTimes?[key])
        }
    }
}

enum AIHistory {
    /// 保留时间：天数，0 是一直保留。
    enum Retention: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, year = 365, forever = 0

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .week: return L("7 天", "7 days", "7 日")
            case .month: return L("30 天", "30 days", "30 日")
            case .year: return L("1 年", "1 year", "1 年")
            case .forever: return L("一直保留", "Forever", "ずっと保存")
            }
        }
    }

    static let maxEntries = 1000
    private static let enabledKey = "history.enabled"
    private static let retentionKey = "history.retentionDays"
    /// App 和键盘都会写这个文件，按顺序一个个来，不在主线程读写。
    private static let queue = DispatchQueue(label: "enclave.history")

    /// 「记录润色和问答」，默认开。
    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: enabledKey) }
    }

    static var retention: Retention {
        get { Retention(rawValue: SharedStorage.defaults.object(forKey: retentionKey) as? Int ?? 30) ?? .month }
        set { SharedStorage.defaults.set(newValue.rawValue, forKey: retentionKey) }
    }

    static var fileURL: URL? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return container.appendingPathComponent("History/ai-history.json")
    }

    /// 新的在前。读不到就是空的。
    static func load() -> [AIHistoryEntry] {
        queue.sync { read() }
    }

    /// 键盘每存一次会话调一次：同一轮更新原来那条，新的一轮加在最前。关着记录时不写。
    static func record(_ session: EditSession) {
        guard isEnabled, let entry = AIHistoryEntry(session: session) else { return }
        queue.async {
            var entries = read()
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.insert(entry, at: 0)
            }
            write(pruned(entries))
        }
    }

    static func delete(_ id: String) {
        queue.sync { write(read().filter { $0.id != id }) }
    }

    /// 备份恢复（B3）：整份换成给的这些（已经合并好的）。
    static func replaceAll(_ entries: [AIHistoryEntry]) {
        queue.sync { write(Array(entries.sorted { $0.date > $1.date }.prefix(maxEntries))) }
    }

    static func clear() {
        queue.sync {
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// 打开历史页时按保留时间删一次过期的。
    static func prune() {
        queue.sync {
            let entries = read()
            let kept = pruned(entries)
            if kept.count != entries.count { write(kept) }
        }
    }

    /// 超过保留时间的删掉，最多留 1,000 条（满了先删最早的）。
    static func pruned(_ entries: [AIHistoryEntry], now: Date = Date(), retention: Retention = retention) -> [AIHistoryEntry] {
        var kept = entries
        if retention != .forever {
            let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
            kept.removeAll { $0.date < cutoff }
        }
        return Array(kept.sorted { $0.date > $1.date }.prefix(maxEntries))
    }

    private static func read() -> [AIHistoryEntry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([AIHistoryEntry].self, from: data)) ?? []
    }

    private static func write(_ entries: [AIHistoryEntry]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 键盘没解锁时也要能写（锁屏下用键盘），文件保护放宽到第一次解锁后。
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
