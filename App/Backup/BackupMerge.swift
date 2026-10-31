import Foundation

/// 恢复时怎么把备份里的东西和现有的合在一起（B3，BV4）：纯逻辑，单元测试也编。
/// 合并：词和风格加进来，现有的都保留；同名的风格用备份里的。替换：先清空这一项，再用备份里的。
/// 设置总是直接用备份里的；学到的词由拼音引擎合并（两边都有的词取权重大的），不在这里。
enum BackupMerge {
    enum Mode: String, Codable { case merge, replace }

    /// 一种风格（润色或问答）的列表和默认那条。
    struct Styles: Codable, Equatable {
        var list: [StylePreset]
        var selectedID: UUID?
    }

    struct StylesResult: Equatable {
        var styles: Styles
        /// 新加的条数（合并时同名覆盖的不算）。
        var added: Int
    }

    static func styles(current: Styles, backup: Styles, mode: Mode) -> StylesResult {
        guard mode == .merge else {
            let selected = backup.selectedID.flatMap { id in backup.list.contains { $0.id == id } ? id : nil }
            return StylesResult(styles: Styles(list: backup.list, selectedID: selected), added: backup.list.count)
        }
        var list = current.list
        var added = 0
        var selected = current.selectedID
        for item in backup.list {
            if let index = list.firstIndex(where: { $0.name == item.name }) {
                // 同名的用备份里的内容，id 保留现有的（键盘的默认、本周次数跟着 id）。
                list[index].prompt = item.prompt
                if backup.selectedID == item.id { selected = list[index].id }
            } else {
                list.append(item)
                added += 1
                if backup.selectedID == item.id { selected = item.id }
            }
        }
        return StylesResult(styles: Styles(list: list, selectedID: selected), added: added)
    }

    struct WordsResult: Equatable {
        var words: [CommonWord]
        var added: Int
        /// 备份里有、现在也已经有的。
        var existing: Int
    }

    /// 常用词：同样的字算同一个词（拼音、简码以现有的为准）。只合并自己加的和导入的，系统「文本替换」和通讯录的不带。
    static func commonWords(current: [CommonWord], backup: [CommonWord], mode: Mode) -> WordsResult {
        let incoming = backup.filter { !$0.isReadOnly }
        guard mode == .merge else { return WordsResult(words: incoming, added: incoming.count, existing: 0) }
        var words = current
        var seen = Set(current.map(\.text))
        var added = 0, existing = 0
        for word in incoming {
            if seen.contains(word.text) {
                existing += 1
            } else {
                words.append(word)
                seen.insert(word.text)
                added += 1
            }
        }
        return WordsResult(words: words, added: added, existing: existing)
    }

    /// 键盘常用语：合并时没有的加在最后。
    static func keyboardTexts(current: [String], backup: [String], mode: Mode) -> [String] {
        guard mode == .merge else { return backup }
        var result = current
        for text in backup where !result.contains(text) { result.append(text) }
        return result
    }

    struct HistoryResult: Equatable {
        var entries: [AIHistoryEntry]
        var added: Int
    }

    /// AI 历史：同一条（id 一样）留现有的，新的在前。
    static func history(current: [AIHistoryEntry], backup: [AIHistoryEntry], mode: Mode) -> HistoryResult {
        guard mode == .merge else {
            return HistoryResult(entries: backup.sorted { $0.date > $1.date }, added: backup.count)
        }
        let ids = Set(current.map(\.id))
        let new = backup.filter { !ids.contains($0.id) }
        return HistoryResult(entries: (current + new).sorted { $0.date > $1.date }, added: new.count)
    }

    // MARK: - iCloud 同步：三方合并

    /// 按 key 的三方合并（iCloud 同步，常用词、键盘常用语、AI 历史）：base 是上次同步完两边都一样的那份。
    /// 两边各自加的都留下；一边删了、另一边没改的就删掉；两边都有的，本机改过（和 base 不同）用本机的，否则用 iCloud 的。
    /// 没有 base（第一次同步）时取并集，本机的在前。顺序：本机的顺序，iCloud 新加的接在后面。
    static func threeWay<T: Equatable>(base: [T]?, local: [T], remote: [T], key: (T) -> String) -> [T] {
        let remoteByKey = Dictionary(remote.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        guard let base else {
            let localKeys = Set(local.map(key))
            return local + remote.filter { !localKeys.contains(key($0)) }
        }
        let baseByKey = Dictionary(base.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [T] = []
        var seen = Set<String>()
        for item in local {
            let k = key(item)
            guard seen.insert(k).inserted else { continue }
            if let theirs = remoteByKey[k] {
                // 两边都有：本机没动过就用 iCloud 的。
                result.append(baseByKey[k] == item ? theirs : item)
            } else if baseByKey[k] == nil {
                result.append(item)      // 本机新加的
            }
            // 否则：上次同步过、iCloud 那边删掉了。
        }
        for item in remote {
            let k = key(item)
            guard !seen.contains(k) else { continue }
            if baseByKey[k] == nil {
                result.append(item)      // iCloud 新加的
                seen.insert(k)
            }
            // 否则：上次同步过、本机删掉了。
        }
        return result
    }

    /// 整块的三方合并（设置、风格）：只有一边改过就用改过的那边；两边都改了用 both(本机, iCloud)。
    static func threeWayValue<T: Equatable>(base: T?, local: T, remote: T, both: (T, T) -> T) -> T {
        guard let base else { return both(local, remote) }
        if local == base { return remote }
        if remote == base { return local }
        return both(local, remote)
    }

    /// 设置里属于「润色风格 · 问答风格」的那几项：设置和风格分开备份、分开恢复。
    static let styleKeys = ["styles", "selectedStyleID", "answerStyles", "selectedAnswerStyleID"]

    /// 设置导出成 JSON 对象，去掉风格那几项。
    static func settingsObject(_ settings: EnclaveSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for key in styleKeys { object.removeValue(forKey: key) }
        return object
    }

    /// 恢复设置：用备份里的设置，风格那几项留现有的。
    static func restoreSettings(_ object: [String: Any], keepingStylesOf current: EnclaveSettings) throws -> EnclaveSettings {
        var merged = object
        for key in styleKeys { merged.removeValue(forKey: key) }
        let currentObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any] ?? [:]
        for key in styleKeys { if let value = currentObject[key] { merged[key] = value } }
        let data = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(EnclaveSettings.self, from: data)
    }

    /// 学到的词的快照（librime 的 *.userdb.txt）里有几个词：去掉 # 开头的元数据和删掉的（c 为负）。
    static func learnedCount(_ snapshot: String) -> Int {
        var count = 0
        for line in snapshot.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3 else { continue }
            if fields[2].split(separator: " ").contains(where: { $0.hasPrefix("c=-") }) { continue }
            count += 1
        }
        return count
    }
}
