import Foundation

/// 常用词：用户在 App 里加的、从别的输入法导入的词，打拼音时排在候选最前。
/// 系统「文本替换」和通讯录人名由键盘自己读（UILexicon），不存在这里。
struct CommonWord: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case manual, imported }

    var id = UUID()
    var text: String
    /// 全拼，不带声调和空格，比如 nihao；也可以是自己定的缩写，比如 yx。
    var code: String
    var source: Source = .manual
}

enum CommonWordStore {
    private static let key = "commonWords.v1"
    private static let lexiconKey = "commonWords.useLexicon"

    static func load() -> [CommonWord] {
        guard let data = SharedStorage.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CommonWord].self, from: data)) ?? []
    }

    static func save(_ words: [CommonWord]) {
        if let data = try? JSONEncoder().encode(words) {
            SharedStorage.defaults.set(data, forKey: key)
        }
    }

    /// 键盘是否把系统「文本替换」和通讯录人名也当常用词。
    static var usesLexicon: Bool {
        get { SharedStorage.defaults.object(forKey: lexiconKey) as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: lexiconKey) }
    }

    /// 汉字转成不带声调的全拼，比如「你好」→ nihao。不是汉字的部分去掉。
    static func pinyin(of text: String) -> String {
        let latin = NSMutableString(string: text)
        CFStringTransform(latin, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(latin, nil, kCFStringTransformStripDiacritics, false)
        return normalizeCode(latin as String)
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

    /// 解析别的输入法导出的词库文本。常见的几种：
    /// 「你好\tnihao\t1」（RIME）、「ni'hao 你好」「'ni'hao 你好」（搜狗）、「你好 ni hao」、只有一列词。
    /// 没写拼音的按汉字自动注音；以 # 开头的行和 RIME 的文件头跳过。
    static func parseImport(_ text: String) -> [CommonWord] {
        var seen = Set<String>()
        var words: [CommonWord] = []
        var inHeader = text.hasPrefix("---") || text.contains("\n---\n")
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { inHeader = true; continue }
            if line == "..." { inHeader = false; continue }
            if inHeader || line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "," }).map(String.init)
            let hanzi = fields.filter { $0.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
            guard let word = hanzi.first else { continue }
            let letters = fields.filter { $0 != word && $0.contains(where: \.isLetter) && $0.allSatisfy { $0.isASCII } }
            let code = letters.isEmpty ? pinyin(of: word) : normalizeCode(letters.joined())
            guard !code.isEmpty, seen.insert(word + "\t" + code).inserted else { continue }
            words.append(CommonWord(text: word, code: code, source: .imported))
        }
        return words
    }

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
}
