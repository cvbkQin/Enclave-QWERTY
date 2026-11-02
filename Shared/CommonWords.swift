import Foundation
import UIKit

/// 常用词：用户在 App 里加的、从别的输入法导入的词，打拼音或简码时排在候选最前。
/// 系统「文本替换」和通讯录人名只有键盘读得到（UILexicon），键盘读到后存一份快照，App 里只读显示。
struct CommonWord: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case manual, imported, textReplacement, contact }

    var id = UUID()
    var text: String
    /// 拼音，音节之间空格隔开，比如「you xiang」；英文、数字的词由用户自己填一个好记的拼音。
    var pinyin: String
    /// 简码，可不填，比如 yx。
    var shortcut: String = ""
    var source: Source = .manual

    /// 键盘里能打出这个词的编码：全拼，有简码时再加简码。
    var codes: [String] {
        [CommonWordStore.normalizeCode(pinyin), CommonWordStore.normalizeCode(shortcut)].filter { !$0.isEmpty }
    }

    var isReadOnly: Bool { source == .textReplacement || source == .contact }
}

enum CommonWordStore {
    private static let key = "commonWords.v2"
    private static let lexiconKey = "commonWords.lexicon"
    private static let textReplacementKey = "commonWords.useTextReplacement"
    private static let contactsKey = "commonWords.useContacts"
    private static let keyboardKey = "commonWords.keyboard"

    /// App 里加的和导入的词。
    static func load() -> [CommonWord] {
        guard let data = SharedStorage.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CommonWord].self, from: data)) ?? []
    }

    static func save(_ words: [CommonWord]) {
        if let data = try? JSONEncoder().encode(words) {
            SharedStorage.defaults.set(data, forKey: key)
        }
    }

    /// 键盘上次读到的系统「文本替换」和通讯录人名。
    static var lexicon: [CommonWord] {
        get {
            guard let data = SharedStorage.defaults.data(forKey: lexiconKey) else { return [] }
            return (try? JSONDecoder().decode([CommonWord].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedStorage.defaults.set(data, forKey: lexiconKey) }
        }
    }

    /// 系统「文本替换」和通讯录人名默认不用，用户在常用词页里自己打开。
    static var usesTextReplacement: Bool {
        get { SharedStorage.defaults.object(forKey: textReplacementKey) as? Bool ?? false }
        set { SharedStorage.defaults.set(newValue, forKey: textReplacementKey) }
    }

    static var usesContacts: Bool {
        get { SharedStorage.defaults.object(forKey: contactsKey) as? Bool ?? false }
        set { SharedStorage.defaults.set(newValue, forKey: contactsKey) }
    }

    private static let phrasesKey = "commonWords.keyboard.v2"
    private static let phraseDisplayKey = "commonWords.keyboard.display"

    /// 键盘常用语（对齐清单第 62 条）：九宫格「常用 / 剪贴板」面板左栏里点着输入的词句，按用户排的顺序。
    /// 每条有标题（可空）、内容、简码（可空）；内容是这一条的身份，内容相同的两条合并。
    /// 老数据（只有一串字）读出来时标题、简码都空。
    static var keyboardPhrases: [KeyboardPhrase] {
        get {
            if let data = SharedStorage.defaults.data(forKey: phrasesKey),
               let phrases = try? JSONDecoder().decode([KeyboardPhrase].self, from: data) {
                return phrases
            }
            return (SharedStorage.defaults.stringArray(forKey: keyboardKey) ?? []).map { KeyboardPhrase(text: $0) }
        }
        set {
            let merged = KeyboardPhrase.merged(newValue)
            if let data = try? JSONEncoder().encode(merged) { SharedStorage.defaults.set(data, forKey: phrasesKey) }
            // 老版本（和备份）还读这一份。
            SharedStorage.defaults.set(merged.map(\.text), forKey: keyboardKey)
        }
    }

    /// 只要内容：备份、老版本用。写回时按内容保留原来的标题和简码。
    static var keyboardTexts: [String] {
        get { keyboardPhrases.map(\.text) }
        set {
            let old = Dictionary(keyboardPhrases.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
            keyboardPhrases = newValue.map { old[$0] ?? KeyboardPhrase(text: $0) }
        }
    }

    /// 常用语怎么显示：键盘左栏和 App 常用语页共用一个值（App Group），哪边改两边都变。
    static var phraseDisplay: PhraseDisplay {
        get { SharedStorage.defaults.string(forKey: phraseDisplayKey).flatMap(PhraseDisplay.init(rawValue:)) ?? .both }
        set { SharedStorage.defaults.set(newValue.rawValue, forKey: phraseDisplayKey) }
    }

    /// 填了简码的常用语交给拼音引擎：打简码时内容排在候选第一，和常用词的简码同一套；同一个简码两边都有时常用语在前（权重高一点）。
    /// 候选里一行放不下换行和制表符，写成空格；选中后由键盘换回原文（KeyboardPhrase.flattened）。
    static func phraseShortcutEntries(_ phrases: [KeyboardPhrase]) -> [(text: String, code: String)] {
        phrases.compactMap { phrase in
            let code = normalizeCode(phrase.shortcut)
            return code.isEmpty ? nil : (text: phrase.flattened, code: code)
        }
    }

    /// 键盘这次要用的全部常用词：自己加的、导入的，加上打开了开关的系统来源。
    static func active(lexicon: [CommonWord]) -> [CommonWord] {
        load() + lexicon.filter {
            ($0.source == .textReplacement && usesTextReplacement) || ($0.source == .contact && usesContacts)
        }
    }

    static func containsHanzi(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    /// 汉字转成不带声调的拼音，音节之间一个空格，比如「你好」→ ni hao。没有汉字时返回空。
    static func pinyin(of text: String) -> String {
        guard containsHanzi(text) else { return "" }
        let latin = NSMutableString(string: text)
        CFStringTransform(latin, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(latin, nil, kCFStringTransformStripDiacritics, false)
        return (latin as String).lowercased()
            .replacingOccurrences(of: "ü", with: "v")
            .split(whereSeparator: { !($0.isASCII && $0.isLetter) })
            .joined(separator: " ")
    }

    /// 编码只留小写字母，ü 写成 v。
    static func normalizeCode(_ code: String) -> String {
        String(code.lowercased().replacingOccurrences(of: "ü", with: "v").filter { $0.isASCII && $0.isLetter })
    }

    /// 全拼换成九宫格的数字键，比如 nihao → 64426。
    static func nineKeyCode(_ code: String) -> String {
        let keys: [Character: Character] = [
            "a": "2", "b": "2", "c": "2", "d": "3", "e": "3", "f": "3", "g": "4", "h": "4", "i": "4",
            "j": "5", "k": "5", "l": "5", "m": "6", "n": "6", "o": "6", "p": "7", "q": "7", "r": "7", "s": "7",
            "t": "8", "u": "8", "v": "8", "w": "9", "x": "9", "y": "9", "z": "9",
        ]
        return String(code.compactMap { keys[$0] })
    }

    // MARK: - 导入

    struct ImportResult {
        /// 识别出的格式，导入预览里显示。
        var format: String
        var words: [CommonWord]
        /// 文件里的有效行数（不算注释和空行）。
        var lines: Int
        /// 读不出的行：没有汉字、也没有拼音。
        var unreadable: Int
    }

    /// 解析别的输入法导出的词库文本。常见的几种：
    /// RIME「你好\tni hao\t1」、搜狗「'ni'hao 你好」、百度「你好(ni|hao) 1」、QQ「ni'hao 你好 1」、每行一个词。
    /// 没写拼音的按汉字自动注音；以 # 开头的行和 RIME 的文件头跳过。
    static func parseImport(_ text: String) -> ImportResult {
        var seen = Set<String>()
        var words: [CommonWord] = []
        var lines = 0
        var unreadable = 0
        var formats: [String: Int] = [:]
        var inHeader = text.hasPrefix("---\n") || text.contains("\n---\n")
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { inHeader = true; continue }
            if line == "..." { inHeader = false; continue }
            if inHeader || line.isEmpty || line.hasPrefix("#") { continue }
            lines += 1
            // 百度：你好(ni|hao) 1
            var cleaned = line
            var baiduPinyin: String?
            if let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close {
                baiduPinyin = line[line.index(after: open)..<close].replacingOccurrences(of: "|", with: " ")
                cleaned = String(line[..<open]) + " " + String(line[line.index(after: close)...])
            }
            let fields = cleaned.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "," }).map(String.init)
            guard let word = fields.first(where: containsHanzi) else {
                unreadable += 1
                continue
            }
            let letters = fields.filter { field in
                field != word && field.contains(where: \.isLetter) && field.allSatisfy { $0.isASCII }
            }
            let written = baiduPinyin ?? letters.joined(separator: " ")
            let spelled = written.isEmpty
                ? Self.pinyin(of: word)
                : written.split(whereSeparator: { $0 == "'" || $0 == " " }).joined(separator: " ").lowercased()
            formats[baiduPinyin != nil ? L("百度格式（词(拼|音) 词频）", "Baidu format", "Baidu 形式")
                    : line.hasPrefix("'") ? L("搜狗格式（'拼'音 词）", "Sogou format", "Sogou 形式")
                    : line.contains("\t") ? L("RIME 格式（词 拼音 权重）", "RIME format", "RIME 形式")
                    : written.isEmpty ? L("每行一个词（拼音自动生成）", "One word per line (pinyin added automatically)", "1 行に 1 語（ピンインは自動）") : L("拼音 词", "Pinyin + word", "ピンイン + 語"), default: 0] += 1
            let code = normalizeCode(spelled)
            if code.isEmpty {
                unreadable += 1
                continue
            }
            guard seen.insert(word + "\t" + code).inserted else { continue }
            words.append(CommonWord(text: word, pinyin: spelled, source: .imported))
        }
        let format = formats.count > 1 ? L("多种格式（每行分别识别）", "Mixed formats (each line detected)", "複数の形式（行ごとに判別）") : formats.first?.key ?? L("没认出格式", "Unknown format", "形式を判別できません")
        return ImportResult(format: format, words: words, lines: lines, unreadable: unreadable)
    }

    // MARK: - 给拼音引擎

    /// 写成 librime 读的短语表（custom_phrase 格式：词、编码、权重）。九宫格用数字编码另写一份。
    /// priority 的条目（填了简码的键盘常用语）权重 101，同一个编码排在常用词（100）前面。
    static func phraseTable(_ entries: [(text: String, code: String)], nineKey: Bool,
                            priority: [(text: String, code: String)] = []) -> String {
        var lines = ["# 由 Enclave 生成，改动会被覆盖。", "# no comment"]
        for (list, weight) in [(priority, 101), (entries, 100)] {
            for entry in list {
                let code = nineKey ? nineKeyCode(entry.code) : entry.code
                let text = entry.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                guard !code.isEmpty, !text.isEmpty else { continue }
                lines.append("\(text)\t\(code)\t\(weight)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 每个词的每个编码一行。
    static func phraseEntries(_ words: [CommonWord]) -> [(text: String, code: String)] {
        words.flatMap { word in word.codes.map { (text: word.text, code: $0) } }
    }
}

/// 一条键盘常用语：标题（可空，键盘里显示在内容上面）、内容（点一下输入的就是它）、简码（可空，只收字母）。
struct KeyboardPhrase: Codable, Equatable, Hashable, Identifiable {
    var title: String = ""
    var text: String
    var shortcut: String = ""

    var id: String { text }

    init(title: String = "", text: String, shortcut: String = "") {
        self.title = title
        self.text = text
        self.shortcut = shortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
    }

    /// 标题去掉首尾空白后为空就当没填。
    var displayTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 写进候选的样子：换行、制表符换成空格（短语表一行一条）。
    var flattened: String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
    }

    /// 内容相同的合并成一条：留先出现那条的位置，标题、简码哪条填了用哪条。
    static func merged(_ phrases: [KeyboardPhrase]) -> [KeyboardPhrase] {
        var result: [KeyboardPhrase] = []
        var index: [String: Int] = [:]
        for phrase in phrases where !phrase.text.isEmpty {
            if let at = index[phrase.text] {
                if result[at].displayTitle == nil { result[at].title = phrase.title }
                if result[at].shortcut.isEmpty { result[at].shortcut = phrase.shortcut }
            } else {
                index[phrase.text] = result.count
                result.append(phrase)
            }
        }
        return result
    }
}

/// 常用语的显示方式（CW3）：点一下依次 标题和内容 → 标题 → 内容 → 标题和内容。
enum PhraseDisplay: String, CaseIterable {
    case both, title, content

    var next: PhraseDisplay {
        switch self {
        case .both: return .title
        case .title: return .content
        case .content: return .both
        }
    }

    var name: String {
        switch self {
        case .both: return L("标题和内容", "Title & text", "タイトルと内容")
        case .title: return L("标题", "Title", "タイトル")
        case .content: return L("内容", "Text", "内容")
        }
    }
}

/// 键盘「常用 / 剪贴板」面板的边距：内容左右和九宫格的键对齐，离屏幕边 7pt。
enum KeyboardWordsLayout {
    static let sideMargin: CGFloat = 7
}
