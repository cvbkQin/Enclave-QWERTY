import Foundation

/// 双拼：一个音节打两个键（声母键 + 韵母键）。词库、整句模型、常用词都和全拼共用，
/// 部署词库时把全键盘方案的拼写规则换成这一套（见 patchSchema），九宫格不动。
/// 只做小鹤和自然码（用户定的；微软双拼的 ing 在「;」键上，全键盘没有这个键，不做）。
/// 规则不是照搬别人的方案文件，而是按下面的键位表给音节表里每个音节算出两键编码再生成的，单元测试检查每套都覆盖全部音节、互不冲突。
enum DoublePinyin: String, Codable, CaseIterable, Identifiable {
    case flypy
    case ziranma

    var id: String { rawValue }

    /// 「双拼 · 小鹤」里的短名字。
    var shortTitle: String {
        switch self {
        case .flypy: return L("小鹤", "Xiaohe", "小鶴")
        case .ziranma: return L("自然码", "Ziranma", "自然碼")
        }
    }

    var title: String {
        switch self {
        case .flypy: return L("小鹤双拼", "Xiaohe", "小鶴双拼")
        case .ziranma: return L("自然码", "Ziranma", "自然碼")
        }
    }

    // MARK: 键位

    /// zh ch sh 打哪个键；别的声母就是它自己。三套一样。
    static let retroflexKeys: [String: Character] = ["zh": "v", "ch": "i", "sh": "u"]

    /// 韵母打哪个键。音节表里的写法：ü 写 v（lv、lve），j q x y 后面的 ü 写 u（ju、xue、yuan、jun）。
    var finalKeys: [String: Character] { Self.finalKeyTables[self] ?? [:] }

    private static let finalKeyTables = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makeFinalKeys()) })

    private func makeFinalKeys() -> [String: Character] {
        var keys: [String: Character] = ["a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v", "uo": "o"]
        let table: [Character: [String]]
        switch self {
        case .flypy:
            table = ["q": ["iu"], "w": ["ei"], "r": ["uan"], "t": ["ue", "ve"], "y": ["un"], "p": ["ie"],
                     "s": ["ong", "iong"], "d": ["ai"], "f": ["en"], "g": ["eng"], "h": ["ang"], "j": ["an"],
                     "k": ["ing", "uai"], "l": ["iang", "uang"], "z": ["ou"], "x": ["ia", "ua"], "c": ["ao"],
                     "v": ["ui"], "b": ["in"], "n": ["iao"], "m": ["ian"]]
        case .ziranma:
            table = ["q": ["iu"], "w": ["ia", "ua"], "r": ["uan"], "t": ["ue", "ve"], "y": ["ing", "uai"], "p": ["un"],
                     "s": ["ong", "iong"], "d": ["iang", "uang"], "f": ["en"], "g": ["eng"], "h": ["ang"], "j": ["an"],
                     "k": ["ao"], "l": ["ai"], "z": ["ei"], "x": ["ie"], "c": ["iao"], "v": ["ui"], "b": ["ou"],
                     "n": ["in"], "m": ["ian"]]
        }
        for (key, finals) in table {
            for final in finals { keys[final] = key }
        }
        return keys
    }

    /// 键上的提示（UI 稿 SP1/SP3）：每个键除了字母本身还管的 zh/ch/sh（排第一行）和韵母，最多两行。
    /// 韵母就是字母本身的（a、e、i、u、o）、ü、ve 不写。
    var keyHints: [Character: [String]] { Self.hintTables[self] ?? [:] }

    private static let hintTables = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makeHints()) })

    private func makeHints() -> [Character: [String]] {
        let common: [Character: [String]] = ["q": ["iu"], "r": ["uan"], "t": ["ue"], "u": ["sh"], "i": ["ch"], "o": ["uo"],
                                             "s": ["iong", "ong"], "f": ["en"], "g": ["eng"], "h": ["ang"], "j": ["an"],
                                             "v": ["zh", "ui"], "m": ["ian"]]
        let own: [Character: [String]]
        switch self {
        case .flypy:
            own = ["w": ["ei"], "y": ["un"], "p": ["ie"], "d": ["ai"], "k": ["uai", "ing"], "l": ["iang", "uang"],
                   "z": ["ou"], "x": ["ia", "ua"], "c": ["ao"], "b": ["in"], "n": ["iao"]]
        case .ziranma:
            own = ["w": ["ia", "ua"], "y": ["ing", "uai"], "p": ["un"], "d": ["iang", "uang"], "k": ["ao"], "l": ["ai"],
                   "z": ["ei"], "x": ["ie"], "c": ["iao"], "b": ["ou"], "n": ["in"]]
        }
        return common.merging(own) { $1 }
    }

    /// 零声母音节（a、ai、ang、er……）的两键编码。
    private func zeroInitialCode(_ final: String) -> String? {
        // 两套一样：单韵母双击，两个字母的照打，三个字母的打首字母 + 韵母键。
        switch final.count {
        case 1: return final + final
        case 2: return final
        default: return finalKeys[final].map { String(final.first!) + String($0) }
        }
    }

    /// 同一个音节还能这样打：自然码零声母也认「首字母 + 韵母键」（al = ai）。
    private func alternateCodes(_ initial: String, _ final: String) -> [String] {
        guard self == .ziranma, initial.isEmpty, final.count == 2 else { return [] }
        return finalKeys[final].map { [String(final.first!) + String($0)] } ?? []
    }

    static func split(_ syllable: String) -> (initial: String, final: String) {
        if let two = ["zh", "ch", "sh"].first(where: { syllable.hasPrefix($0) }) {
            return (two, String(syllable.dropFirst(2)))
        }
        guard let first = syllable.first, !"aoe".contains(first) else { return ("", syllable) }
        return (String(first), String(syllable.dropFirst()))
    }

    /// 一个全拼音节的两键编码；不在音节表里时为 nil。
    func code(for syllable: String) -> String? {
        let (initial, final) = Self.split(syllable)
        if initial.isEmpty { return zeroInitialCode(final) }
        let first = Self.retroflexKeys[initial].map(String.init) ?? initial
        return finalKeys[final].map { first + String($0) }
    }

    /// 音节表里每个音节的编码（主编码 + 别的打法）。
    var codes: [(syllable: String, code: String, alternates: [String])] {
        PinyinTable.syllables.sorted().compactMap { syllable in
            guard let code = code(for: syllable) else { return nil }
            let (initial, final) = Self.split(syllable)
            let first = Self.retroflexKeys[initial].map(String.init) ?? initial
            return (syllable, code, alternateCodes(first, final).filter { $0 != code })
        }
    }

    /// 同一个编码对应几个音节时（lo 和 luo 都打 lo），拼写栏显示常用的那个。
    private static let preferredReading: [String: String] = ["lo": "luo"]

    /// 编码 → 拼写栏显示的全拼。别的打法（自然码的 al）也换回全拼，不和主编码抢。
    var readings: [String: String] {
        var result: [String: String] = [:]
        for entry in codes {
            if let existing = result[entry.code], existing == Self.preferredReading[entry.code] { continue }
            if result[entry.code] == nil || Self.preferredReading[entry.code] == entry.syllable {
                result[entry.code] = entry.syllable
            }
        }
        for entry in codes {
            for alternate in entry.alternates where result[alternate] == nil { result[alternate] = entry.syllable }
        }
        return result
    }

    // MARK: 方案

    /// speller/algebra：模糊拼音（插在最前）派生出的拼写也是音节表里的音节，一样换成编码。
    /// 先换成大写（换完的编码不会再被后面的规则当成全拼音节），最后统一转回小写；换不了的生僻拼写删掉，免得双拼里还能打全拼。
    var algebra: [String] {
        var rules: [String] = []
        for entry in codes {
            for alternate in entry.alternates {
                rules.append("derive/^\(entry.syllable)$/\(alternate.uppercased())/")
            }
            rules.append("xform/^\(entry.syllable)$/\(entry.code.uppercased())/")
        }
        rules.append("erase/^.*[a-z].*$/")
        rules.append("xlit/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/")
        // 只打声母键也能出字（简拼）。
        rules.append("abbrev/^(.).+$/$1/")
        return rules
    }

    /// translator/preedit_format：拼写栏把编码换回全拼（xl hc → xiang hao）。
    /// 一样先换成大写再转小写，换出来的全拼不会再被后面的规则改。
    var preeditFormat: [String] {
        var rules = readings.sorted { $0.key < $1.key }.map { pair -> String in
            let (code, syllable) = (pair.key, pair.value)
            return "xform/(^|[ '])\(code)\\b/$1\(syllable.uppercased())/"
        }
        rules.append("xlit/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/")
        return rules
    }

    /// 把全键盘方案的拼写规则换成这一套双拼。找不到要换的段落就原样返回。
    func patchSchema(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let speller = lines.firstIndex(of: "speller:"),
              let algebraStart = lines[speller...].firstIndex(of: "  algebra:"),
              let translator = lines.firstIndex(of: "translator:"),
              let preedit = lines[translator...].firstIndex(of: "  preedit_format:")
        else { return text }
        // 两段规则都是紧跟着的「    - 」行（中间可以夹注释）。
        func ruleEnd(after start: Int) -> Int {
            var end = start + 1
            while end < lines.count, lines[end].hasPrefix("    ") { end += 1 }
            return end
        }
        let preeditLines = ["    # Enclave 双拼（\(rawValue)）：拼写栏显示全拼"] + preeditFormat.map { "    - \($0)" }
        // 原来的「jv 显示成 ju」接在后面照用。
        lines.insert(contentsOf: preeditLines, at: preedit + 1)
        let algebraEnd = ruleEnd(after: algebraStart)
        lines.replaceSubrange((algebraStart + 1)..<algebraEnd,
                              with: ["    # Enclave 双拼（\(rawValue)）"] + algebra.map { "    - \($0)" })
        return lines.joined(separator: "\n")
    }

    /// 常用词的全拼编码换成双拼编码（youxiang → yz xl）。切不成音节的（简码、英文）返回 nil。
    func encode(pinyin: String) -> String? {
        guard let syllables = Self.segment(pinyin) else { return nil }
        let parts = syllables.compactMap(code(for:))
        return parts.count == syllables.count ? parts.joined() : nil
    }

    private static let syllableSet = Set(PinyinTable.syllables)

    /// 按音节表切全拼，音节最少的切法（xian 是一个音节）。
    static func segment(_ pinyin: String) -> [String]? {
        let chars = Array(pinyin)
        guard !chars.isEmpty, chars.count <= 64 else { return nil }
        var best: [[String]?] = Array(repeating: nil, count: chars.count + 1)
        best[0] = []
        for end in 1...chars.count {
            for length in 1...min(6, end) {
                guard let prefix = best[end - length] else { continue }
                let piece = String(chars[(end - length)..<end])
                guard syllableSet.contains(piece) else { continue }
                if best[end] == nil || prefix.count + 1 < best[end]!.count { best[end] = prefix + [piece] }
            }
        }
        return best[chars.count]
    }

    // MARK: 版本

    /// 写进已部署版本号的后缀；键盘看它知道词库是不是双拼、是哪一套。
    static func versionTag(_ scheme: DoublePinyin?) -> String {
        scheme.map { "+sp:" + $0.rawValue } ?? ""
    }

    /// 从已部署的版本号读出双拼方案；全拼时为 nil。
    init?(versionString: String) {
        guard let range = versionString.range(of: "+sp:") else { return nil }
        let tail = versionString[range.upperBound...].prefix { $0.isLetter }
        self.init(rawValue: String(tail))
    }

    /// 共享目录里部署好的词库是不是双拼。
    static var deployed: DoublePinyin? {
        RimeStore.deployedVersion.flatMap(DoublePinyin.init(versionString:))
    }
}
