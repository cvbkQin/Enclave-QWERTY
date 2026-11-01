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
