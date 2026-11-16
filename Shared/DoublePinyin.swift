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

    /// 同一个音节还能这样打（和 Rime 参考方案 rime-double-pinyin 一样认，双拼调研 P1）：
    /// - j q x y 后面的 ü 音节表里写 u（ju），按「ü 打 v」的习惯打 jv 也认；
    /// - 零声母两个字母的韵母照打（ai）之外，也认「首字母 + 韵母键」（小鹤 ad、自然码 al）。
    /// 这些编码在两套方案里都不是别的音节（单元测试查）。
    private func alternateCodes(_ initial: String, _ final: String) -> [String] {
        var codes: [String] = []
        if ["j", "q", "x", "y"].contains(initial), final == "u" { codes.append(initial + "v") }
        if initial.isEmpty, final.count == 2, let key = finalKeys[final] { codes.append(String(final.first!) + String(key)) }
        return codes
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

    // MARK: 键对、提示

    /// 两个键拼不拼得成音节（主编码和别的打法都算）。拼写栏把拼不成的键对标出来（双拼调研 P1）。
    func isSyllableCode(_ pair: String) -> Bool { Self.codeSets[self]?.contains(pair) ?? false }

    private static let codeSets = Dictionary(uniqueKeysWithValues: allCases.map { ($0, Set($0.readings.keys)) })

    /// 按键串怎么配对：从 from 往后（前面是分段选过的），遇到 ' 重新配；每两个键一对，最后单下的一个键自己一组。
    /// 返回每组在 raw 里的范围（按字符数）和这组的键。
    static func pairs(in raw: String, from: Int = 0) -> [(range: Range<Int>, keys: String)] {
        let chars = Array(raw.lowercased())
        var result: [(range: Range<Int>, keys: String)] = []
        var start: Int?
        var index = min(max(from, 0), chars.count)
        while index < chars.count {
            let char = chars[index]
            if char.isASCII, char.isLetter {
                if let begin = start {
                    result.append((begin..<(index + 1), String(chars[begin...index])))
                    start = nil
                } else {
                    start = index
                }
            } else if let begin = start {
                result.append((begin..<(begin + 1), String(chars[begin])))
                start = nil
            }
            index += 1
        }
        if let begin = start { result.append((begin..<(begin + 1), String(chars[begin]))) }
        return result
    }

    /// 键上提示该写什么（「跟着按键变」档，SP7）：下一个键是声母还是韵母、韵母前面是哪个键。
    enum HintPhase: Equatable {
        /// 固定档：每个键写它管的韵母和 zh/ch/sh。
        case all
        /// 该按声母：只在 u、i、v 上写 sh / ch / zh。
        case initial
        /// 按了声母键（或零声母的首字母），该按第二个键：每个键只写能和它拼上的韵母（一行），拼不上的键变淡。
        case final(Character)
    }

    /// 按键串最后该按什么（配对规则和 pairs 一样）。
    static func hintPhase(raw: String, from: Int = 0) -> HintPhase {
        guard let last = pairs(in: raw, from: from).last, last.keys.count == 1,
              last.range.upperBound == raw.count, let key = last.keys.first else { return .initial }
        return .final(key)
    }

    /// 某个阶段每个键上写的小字。
    func hints(for phase: HintPhase) -> [Character: [String]] {
        switch phase {
        case .all: return keyHints
        case .initial: return Self.retroflexHints
        case .final(let first): return Self.finalHintTables[self]?[first] ?? [:]
        }
    }

    /// 「跟着按键变」该按韵母时，这个键能不能和前一个键拼上；拼不上的键变淡（照样能按）。别的阶段都算能。
    func keyFits(_ key: Character, in phase: HintPhase) -> Bool {
        guard case .final(let first) = phase else { return true }
        return Self.fittingKeys[self]?[first]?.contains(key) ?? false
    }

    private static let retroflexHints: [Character: [String]] = Dictionary(uniqueKeysWithValues: retroflexKeys.map { ($0.value, [$0.key]) })

    /// 第一个键 → 第二个键 → 键上写的韵母（SP7）。只写主编码的（提示教标准打法）；同一编码几个音节时按拼写栏显示的那个（lo → luo 写 uo）。
    /// 韵母就是字母本身的（x 后面的 u、i）不写字。零声母的韵母是整个音节（a 后面的 h 写 ang）。
    private static let finalHintTables: [DoublePinyin: [Character: [Character: [String]]]] = Dictionary(uniqueKeysWithValues: allCases.map { scheme -> (DoublePinyin, [Character: [Character: [String]]]) in
        var table: [Character: [Character: [String]]] = [:]
        let readings = scheme.readings
        for entry in scheme.codes {
            let keys = Array(entry.code)
            let final = DoublePinyin.split(readings[entry.code] ?? entry.syllable).final
            table[keys[0], default: [:]][keys[1]] = final == String(keys[1]) ? [] : [final]
        }
        return (scheme, table)
    })

    /// 第一个键 → 能接的第二个键（主编码和别的打法都算：x 后面按 v 是 xu，不变淡）。
    private static let fittingKeys: [DoublePinyin: [Character: Set<Character>]] = Dictionary(uniqueKeysWithValues: allCases.map { scheme -> (DoublePinyin, [Character: Set<Character>]) in
        var table: [Character: Set<Character>] = [:]
        for code in scheme.readings.keys {
            let keys = Array(code)
            table[keys[0], default: []].insert(keys[1])
        }
        return (scheme, table)
    })

    /// 零声母音节（没有声母的字）怎么打：「双拼方案」页的说明卡用。例字、全拼、主编码、别的打法。
    var zeroInitialExamples: [(example: String, syllable: String, code: String, alternates: [String])] {
        let examples: [(String, String)] = [("啊", "a"), ("爱", "ai"), ("安", "an"), ("昂", "ang"), ("熬", "ao"), ("鹅", "e"),
                                            ("诶", "ei"), ("恩", "en"), ("鞥", "eng"), ("而", "er"), ("哦", "o"), ("欧", "ou")]
        let byCode = Dictionary(uniqueKeysWithValues: codes.map { ($0.syllable, $0) })
        return examples.compactMap { example, syllable in
            byCode[syllable].map { (example, syllable, $0.code, $0.alternates) }
        }
    }

    // MARK: 方案

    /// speller/algebra：模糊拼音（插在最前）派生出的拼写也是音节表里的音节，一样换成编码。
    /// 先换成大写（换完的编码不会再被后面的规则当成全拼音节），最后统一转回小写；换不了的生僻拼写删掉，免得双拼里还能打全拼。
    /// mixFull（也能打全拼，双拼调研 P3）：全拼拼写留着（derive 不 xform、不删），接在原来全键盘的规则后面用。
    func algebra(mixFull: Bool = false) -> [String] {
        var rules: [String] = []
        for entry in codes {
            for alternate in entry.alternates {
                rules.append("derive/^\(entry.syllable)$/\(alternate.uppercased())/")
            }
            rules.append("\(mixFull ? "derive" : "xform")/^\(entry.syllable)$/\(entry.code.uppercased())/")
        }
        if !mixFull { rules.append("erase/^.*[a-z].*$/") }
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
    /// mixFull：原来的全拼规则（简拼、ü、gn 手误）留着，双拼规则接在后面。
    func patchSchema(_ text: String, mixFull: Bool = false) -> String {
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
        let rules = ["    # Enclave 双拼（\(rawValue)\(mixFull ? "，也能打全拼" : "")）"] + algebra(mixFull: mixFull).map { "    - \($0)" }
        if mixFull {
            lines.insert(contentsOf: rules, at: algebraEnd)
        } else {
            lines.replaceSubrange((algebraStart + 1)..<algebraEnd, with: rules)
        }
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

    /// 写进已部署版本号的后缀；键盘看它知道词库是不是双拼、是哪一套、能不能也打全拼。
    static func versionTag(_ scheme: DoublePinyin?, mixFull: Bool = false) -> String {
        scheme.map { "+sp:" + $0.rawValue + (mixFull ? mixTag : "") } ?? ""
    }

    private static let mixTag = "+spmix"

    /// 部署的双拼词库也能打全拼（版本号带 +spmix）。
    static func mixesFull(versionString: String) -> Bool {
        DoublePinyin(versionString: versionString) != nil && versionString.contains(mixTag)
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

    /// 共享目录里部署好的双拼词库能不能也打全拼。
    static var deployedMixesFull: Bool {
        RimeStore.deployedVersion.map(mixesFull(versionString:)) ?? false
    }
}

/// 双拼键上的提示（「双拼方案」页）：不写、固定写每个键管的韵母（SP1）、跟着按键变（双拼调研 P2：该按声母时只写 zh/ch/sh，
/// 按了声母后每个键写和它拼出来的音节，拼不成的键不写）。
enum DoublePinyinHintMode: String, Codable, CaseIterable, Identifiable {
    case off
    case fixed
    case dynamic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return L("关", "Off", "オフ")
        case .fixed: return L("固定", "Fixed", "固定")
        case .dynamic: return L("跟着按键变", "Follow typing", "入力に合わせる")
        }
    }
}
