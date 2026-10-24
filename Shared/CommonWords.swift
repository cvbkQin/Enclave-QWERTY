import Foundation

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

    static var usesTextReplacement: Bool {
        get { SharedStorage.defaults.object(forKey: textReplacementKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: textReplacementKey) }
    }

    static var usesContacts: Bool {
        get { SharedStorage.defaults.object(forKey: contactsKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: contactsKey) }
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
            formats[baiduPinyin != nil ? "百度格式（词(拼|音) 词频）"
                    : line.hasPrefix("'") ? "搜狗格式（'拼'音 词）"
                    : line.contains("\t") ? "RIME 格式（词 拼音 权重）"
                    : written.isEmpty ? "每行一个词（拼音自动生成）" : "拼音 词", default: 0] += 1
            let code = normalizeCode(spelled)
            if code.isEmpty {
                unreadable += 1
                continue
            }
            guard seen.insert(word + "\t" + code).inserted else { continue }
            words.append(CommonWord(text: word, pinyin: spelled, source: .imported))
        }
        let format = formats.max { $0.value < $1.value }?.key ?? "没认出格式"
        return ImportResult(format: format, words: words, lines: lines, unreadable: unreadable)
    }

    // MARK: - 给拼音引擎

    /// 写成 librime 读的短语表（custom_phrase 格式：词、编码、权重）。九宫格用数字编码另写一份。
    static func phraseTable(_ entries: [(text: String, code: String)], nineKey: Bool) -> String {
        var lines = ["# 由 Enclave 生成，改动会被覆盖。", "# no comment"]
        for entry in entries {
            let code = nineKey ? nineKeyCode(entry.code) : entry.code
            let text = entry.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            guard !code.isEmpty, !text.isEmpty else { continue }
            lines.append("\(text)\t\(code)\t100")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 每个词的每个编码一行。
    static func phraseEntries(_ words: [CommonWord]) -> [(text: String, code: String)] {
        words.flatMap { word in word.codes.map { (text: word.text, code: $0) } }
    }
}
