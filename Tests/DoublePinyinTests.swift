import XCTest

/// 双拼（第 12 条）：小鹤、自然码两套键位覆盖音节表里每个音节、编码互不冲突；生成的拼写规则、拼写栏规则照 Rime 的方式跑一遍结果对。
final class DoublePinyinTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testEverySyllableHasTwoKeyCode() {
        for scheme in DoublePinyin.allCases {
            for syllable in PinyinTable.syllables {
                let code = scheme.code(for: syllable)
                XCTAssertEqual(code?.count, 2, "\(scheme) \(syllable) → \(code ?? "nil")")
                XCTAssertTrue(code?.allSatisfy { $0.isASCII && $0.isLowercase } ?? false, "\(scheme) \(syllable)")
            }
        }
    }

    /// 只有 lo 和 luo 共用一个编码（两套都这样，韵母 o 和 uo 在同一个键上）。
    func testCodesDoNotCollide() {
        for scheme in DoublePinyin.allCases {
            var bySyllable: [String: [String]] = [:]
            for entry in scheme.codes {
                for code in [entry.code] + entry.alternates { bySyllable[code, default: []].append(entry.syllable) }
            }
            let shared = bySyllable.filter { $0.value.count > 1 }
            XCTAssertEqual(shared.keys.sorted(), ["lo"], "\(scheme): \(shared)")
        }
    }

    func testKnownCodes() {
        let flypy: [String: String] = ["shuang": "ul", "pin": "pb", "xiang": "xl", "zhi": "vi", "chi": "ii", "a": "aa", "ai": "ai",
                                       "ang": "ah", "er": "er", "o": "oo", "lv": "lv", "lve": "lt", "ju": "ju", "yuan": "yr",
                                       "jiong": "js", "kuai": "kk", "ying": "yk", "dui": "dv", "gua": "gx", "liu": "lq"]
        let ziranma: [String: String] = ["shuang": "ud", "pin": "pn", "xiang": "xd", "ai": "ai", "ang": "ah", "ying": "yy",
                                         "kuai": "ky", "zou": "zb", "mei": "mz", "lve": "lt", "dun": "dp"]
        for (scheme, table) in [(DoublePinyin.flypy, flypy), (.ziranma, ziranma)] {
            for (syllable, code) in table { XCTAssertEqual(scheme.code(for: syllable), code, "\(scheme) \(syllable)") }
        }
        XCTAssertEqual(DoublePinyin.ziranma.codes.first { $0.syllable == "ai" }?.alternates, ["al"])
        // 双拼调研 P1：小鹤零声母也认「首字母 + 韵母键」，j q x y 后面的 ü 也认 v（和 Rime 参考方案一样）。
        XCTAssertEqual(DoublePinyin.flypy.codes.first { $0.syllable == "ai" }?.alternates, ["ad"])
        for scheme in DoublePinyin.allCases {
            let alternates = Dictionary(uniqueKeysWithValues: scheme.codes.map { ($0.syllable, $0.alternates) })
            for syllable in ["ju", "qu", "xu", "yu"] {
                XCTAssertEqual(alternates[syllable], [String(syllable.first!) + "v"], "\(scheme) \(syllable)")
            }
            XCTAssertEqual(alternates["er"], [], "\(scheme)")
        }
        let readings = DoublePinyin.flypy.readings
        for (code, syllable) in ["ad": "ai", "aj": "an", "ac": "ao", "ew": "ei", "ef": "en", "oz": "ou", "jv": "ju", "xv": "xu"] {
            XCTAssertEqual(readings[code], syllable, code)
        }
    }

    func testEncodeCommonWordPinyin() {
        XCTAssertEqual(DoublePinyin.flypy.encode(pinyin: "youxiang"), "yzxl")
        XCTAssertEqual(DoublePinyin.flypy.encode(pinyin: "xian"), "xm")
        XCTAssertEqual(DoublePinyin.ziranma.encode(pinyin: "beijingshi"), "bzjyui")
        XCTAssertNil(DoublePinyin.flypy.encode(pinyin: "yx"))
        XCTAssertNil(DoublePinyin.flypy.encode(pinyin: ""))
        let table = CommonWordStore.phraseTable([(text: "邮箱", code: "youxiang"), (text: "公司", code: "gs")],
                                                nineKey: false, doublePinyin: .flypy)
        XCTAssertTrue(table.contains("邮箱\tyzxl\t100\n邮箱\tyouxiang\t100\n"), table)
        XCTAssertTrue(table.contains("公司\tgs\t100\n"), table)
        XCTAssertFalse(table.contains("公司\tgs\t100\n公司"), table)
        // 九宫格照旧。
        XCTAssertEqual(CommonWordStore.phraseTable([(text: "邮箱", code: "youxiang")], nineKey: true, doublePinyin: .flypy),
                       CommonWordStore.phraseTable([(text: "邮箱", code: "youxiang")], nineKey: true))
    }

    /// 键上提示照 UI 稿（SP1）：zh/ch/sh 排第一行，最多两行，a/e 这种不写。
    func testKeyHints() {
        XCTAssertEqual(DoublePinyin.flypy.keyHints["v"], ["zh", "ui"])
        XCTAssertEqual(DoublePinyin.flypy.keyHints["k"], ["uai", "ing"])
        XCTAssertEqual(DoublePinyin.ziranma.keyHints["y"], ["ing", "uai"])
        XCTAssertNil(DoublePinyin.flypy.keyHints["a"])
        XCTAssertNil(DoublePinyin.flypy.keyHints["e"])
        for scheme in DoublePinyin.allCases {
            XCTAssertTrue(scheme.keyHints.values.allSatisfy { (1...2).contains($0.count) })
            // 提示写的每个韵母都确实在那个键上。
            for (key, lines) in scheme.keyHints {
                for final in lines where !["zh", "ch", "sh"].contains(final) {
                    XCTAssertEqual(scheme.finalKeys[final], key, "\(scheme) \(final)")
                }
            }
        }
    }

    func testVersionTag() {
        XCTAssertEqual(DoublePinyin.versionTag(nil), "")
        XCTAssertEqual(DoublePinyin(versionString: "shared:2026-10-31+t9delim+sp:ziranma+grammar"), .ziranma)
        XCTAssertNil(DoublePinyin(versionString: "shared:2026-10-31+t9delim+fuzzy:zh"))
        XCTAssertEqual(DoublePinyin(versionString: "x" + DoublePinyin.versionTag(.flypy)), .flypy)
    }

    /// 照 Rime 拼写运算的方式跑生成的规则：音节表（加上模糊拼音派生）变成的拼写正好是每个音节的编码、别的打法和单键简拼。
    func testAlgebraProducesCodes() {
        for scheme in DoublePinyin.allCases {
            var spellings = Set(PinyinTable.syllables)
            spellings.insert("hm") // 音节表外的生僻拼写要删掉
            let result = Self.run(scheme.algebra(), on: spellings)
            var expected = Set<String>()
            for entry in scheme.codes {
                expected.insert(entry.code)
                expected.formUnion(entry.alternates)
                expected.insert(String(entry.code.first!))
                expected.formUnion(entry.alternates.map { String($0.first!) })
            }
            XCTAssertEqual(result, expected, "\(scheme): 多 \(result.subtracting(expected).sorted()) 少 \(expected.subtracting(result).sorted())")
        }
        // 模糊拼音的规则插在前面：z = zh 时 zi 的编码也能打出 zhi 的字（反过来同理），编码本身都是双拼的。
        let fuzzy = FuzzyPinyin.zh.rules + DoublePinyin.flypy.algebra()
        let result = Self.run(fuzzy, on: ["zi", "zhi"])
        XCTAssertEqual(result, ["zi", "vi", "z", "v"])
    }

    /// 也认全拼（双拼调研 P3）：全拼拼写留着，双拼编码一样有。
    func testAlgebraMixFull() {
        let result = Self.run(DoublePinyin.flypy.algebra(mixFull: true), on: ["xiang", "hao", "ai"])
        XCTAssertTrue(result.isSuperset(of: ["xiang", "hao", "ai", "xl", "hc", "ad", "x", "h", "a"]), "\(result.sorted())")
        let url = Self.root.appendingPathComponent("Configs/Rime/enclave.schema.yaml")
        let text = try! String(contentsOf: url, encoding: .utf8)
        let patched = DoublePinyin.flypy.patchSchema(text, mixFull: true)
        // 全拼的规则留着，双拼规则接在后面，不删全拼拼写。
        XCTAssertTrue(patched.contains("abbrev/^([zcs]h).+$/$1/"))
        XCTAssertTrue(patched.contains("    # Enclave 双拼（flypy，也能打全拼）\n    - derive/^a$/AA/"))
        XCTAssertFalse(patched.contains("erase/^.*[a-z].*$/"))
        XCTAssertEqual(DoublePinyin.versionTag(.flypy, mixFull: true), "+sp:flypy+spmix")
        XCTAssertEqual(DoublePinyin(versionString: "shared:x+sp:flypy+spmix+grammar"), .flypy)
        XCTAssertTrue(DoublePinyin.mixesFull(versionString: "shared:x+sp:flypy+spmix"))
        XCTAssertFalse(DoublePinyin.mixesFull(versionString: "shared:x+sp:flypy+grammar"))
    }

    /// 按键配对、拼不成的键对、「跟着按键变」的提示（SP6、SP7）。
    func testPairsAndDynamicHints() {
        XCTAssertEqual(DoublePinyin.pairs(in: "nibz").map(\.keys), ["ni", "bz"])
        XCTAssertEqual(DoublePinyin.pairs(in: "nihcx").map(\.keys), ["ni", "hc", "x"])
        XCTAssertEqual(DoublePinyin.pairs(in: "x'xl").map(\.keys), ["x", "xl"])
        XCTAssertEqual(DoublePinyin.pairs(in: "nihcxl", from: 4).map(\.range), [4..<6])
        XCTAssertTrue(DoublePinyin.flypy.isSyllableCode("ni"))
        XCTAssertTrue(DoublePinyin.flypy.isSyllableCode("jv"))
        XCTAssertFalse(DoublePinyin.flypy.isSyllableCode("bz"))

        XCTAssertEqual(DoublePinyin.hintPhase(raw: ""), .initial)
        XCTAssertEqual(DoublePinyin.hintPhase(raw: "x"), .final("x"))
        XCTAssertEqual(DoublePinyin.hintPhase(raw: "xl"), .initial)
        XCTAssertEqual(DoublePinyin.hintPhase(raw: "x'"), .initial)
        XCTAssertEqual(DoublePinyin.hintPhase(raw: "nihcx", from: 4), .final("x"))

        let scheme = DoublePinyin.flypy
        XCTAssertEqual(scheme.hints(for: .initial), ["u": ["sh"], "i": ["ch"], "v": ["zh"]])
        let afterX = scheme.hints(for: .final("x"))
        XCTAssertEqual(afterX["k"], ["ing"])
        XCTAssertEqual(afterX["l"], ["iang"])
        XCTAssertEqual(afterX["s"], ["iong"])
        XCTAssertEqual(afterX["u"], [])   // xu：韵母就是字母本身，不写字
        XCTAssertNil(afterX["d"])
        XCTAssertTrue(scheme.keyFits("u", in: .final("x")))
        XCTAssertTrue(scheme.keyFits("v", in: .final("x")))   // xv = xu
        XCTAssertFalse(scheme.keyFits("d", in: .final("x")))
        XCTAssertTrue(scheme.keyFits("d", in: .initial))
        XCTAssertEqual(scheme.hints(for: .final("v"))["l"], ["uang"])   // zhuang
        XCTAssertEqual(scheme.hints(for: .final("l"))["o"], ["uo"])     // lo 显示成 luo
        XCTAssertEqual(scheme.hints(for: .final("a"))["h"], ["ang"])    // 零声母：整个音节
        XCTAssertEqual(scheme.hints(for: .final("a"))["a"], [])
        XCTAssertEqual(scheme.hints(for: .all)["k"], scheme.keyHints["k"])
    }

    func testZeroInitialExamples() {
        let flypy = DoublePinyin.flypy.zeroInitialExamples
        XCTAssertEqual(flypy.map(\.code), ["aa", "ai", "an", "ah", "ao", "ee", "ei", "en", "eg", "er", "oo", "ou"])
        XCTAssertEqual(flypy.first { $0.syllable == "ai" }?.alternates, ["ad"])
        XCTAssertEqual(DoublePinyin.ziranma.zeroInitialExamples.first { $0.syllable == "ou" }?.alternates, ["ob"])
    }

    /// 键上提示从开关换成三档：旧设置里的开 / 关读成固定 / 不显示。
    func testHintModeMigration() throws {
        func decode(_ json: String) throws -> EnclaveSettings {
            try JSONDecoder().decode(EnclaveSettings.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("{}").doublePinyinHintMode, .fixed)
        XCTAssertEqual(try decode("{\"doublePinyinHints\": false}").doublePinyinHintMode, .off)
        XCTAssertEqual(try decode("{\"doublePinyinHints\": true}").doublePinyinHintMode, .fixed)
        XCTAssertEqual(try decode("{\"doublePinyinHintMode\": \"dynamic\"}").doublePinyinHintMode, .dynamic)
        XCTAssertFalse(try decode("{}").doublePinyinMixFull)
    }

    func testPreeditShowsFullPinyin() {
        let rules = DoublePinyin.flypy.preeditFormat
        XCTAssertEqual(Self.format(rules, "xl hc"), "xiang hao")
        XCTAssertEqual(Self.format(rules, "ul pb"), "shuang pin")
        XCTAssertEqual(Self.format(rules, "xl xl'x"), "xiang xiang'x")
        XCTAssertEqual(Self.format(rules, "lo"), "luo")
        XCTAssertEqual(Self.format(rules, "aa ah"), "a ang")
        XCTAssertEqual(Self.format(DoublePinyin.ziranma.preeditFormat, "al"), "ai")
        XCTAssertEqual(Self.format(DoublePinyin.ziranma.preeditFormat, "xd hk"), "xiang hao")
    }

    func testPatchSchema() throws {
        let url = Self.root.appendingPathComponent("Configs/Rime/enclave.schema.yaml")
        let text = try String(contentsOf: url, encoding: .utf8)
        let patched = DoublePinyin.flypy.patchSchema(text)
        XCTAssertNotEqual(patched, text)
        // 全拼的简拼、ü 和手误规则都换掉了，双拼规则在 algebra 下面。
        XCTAssertFalse(patched.contains("abbrev/^([zcs]h).+$/$1/"))
        XCTAssertFalse(patched.contains("derive/([aeio])ng$/$1gn/"))
        XCTAssertTrue(patched.contains("  algebra:\n    # Enclave 双拼（flypy）\n    - xform/^a$/AA/"))
        XCTAssertTrue(patched.contains("  preedit_format:\n    # Enclave 双拼（flypy）"))
        XCTAssertTrue(patched.contains("    - xform/([jqxy])v/$1u/"))
        // 后面的段落原样留着。
        XCTAssertTrue(patched.contains("translator:\n  dictionary: enclave\n"))
        XCTAssertTrue(patched.hasSuffix(text.components(separatedBy: "# 中英混输").last!))
        // 模糊拼音接着打补丁，插在双拼规则前面。
        let both = FuzzyPinyin.patchSchema(patched, groups: [.zh])
        XCTAssertTrue(both.contains("  algebra:\n    # Enclave 模糊拼音\n    - derive/^zh/z/\n    - derive/^z([^h])/zh$1/\n    # Enclave 双拼"))
        XCTAssertTrue(patched.contains("  alphabet: zyxwvutsrqponmlkjihgfedcba\n"))
    }

    // MARK: 照 Rime 的拼写运算跑规则（只实现这里用到的几种）

    private static func split(_ rule: String) -> (op: String, a: String, b: String) {
        let parts = rule.components(separatedBy: "/")
        return (parts[0], parts[1], parts.count > 2 ? parts[2] : "")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func apply(_ pattern: String, _ template: String, _ text: String) -> String {
        let regex = regex(pattern)
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        regex(pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func run(_ rules: [String], on input: Set<String>) -> Set<String> {
        var spellings = input
        for rule in rules {
            let (op, a, b) = split(rule)
            switch op {
            case "xform":
                spellings = Set(spellings.map { apply(a, b, $0) })
            case "derive", "abbrev":
                spellings.formUnion(spellings.filter { matches(a, $0) }.map { apply(a, b, $0) })
            case "erase":
                spellings = spellings.filter { !matches(a, $0) }
            case "xlit":
                let map = Dictionary(uniqueKeysWithValues: zip(a, b))
                spellings = Set(spellings.map { String($0.map { map[$0] ?? $0 }) })
            default:
                XCTFail("没实现的运算 \(op)")
            }
        }
        return spellings
    }

    static func format(_ rules: [String], _ text: String) -> String {
        run(rules, on: [text]).first ?? ""
    }
}

/// App 里的双拼练习（SP10）：一组怎么挑、按对按错怎么算、记进练习记录。
final class DoublePinyinPracticeTests: XCTestCase {
    private let items = DoublePinyinPracticeItem.parse("想\txiang\n小\txiao\n你好\tni hao\n坏行\tbad\n")

    func testParseDropsMismatchedLines() {
        XCTAssertEqual(items.map(\.text), ["想", "小", "你好"])
        XCTAssertEqual(items[2].syllables, ["ni", "hao"])
    }

    func testPickPutsMissedFirstAndStopsAtCount() {
        let picked = DoublePinyinPracticeItem.pick(from: items, missed: ["你好"], mastered: ["想"], count: 3)
        XCTAssertEqual(picked.map(\.text), ["你好", "小"])
        XCTAssertEqual(DoublePinyinPracticeItem.pick(from: items, missed: [], mastered: [], count: 30).count, 3)
    }

    func testRunRightWrongAndRecord() {
        var run = DoublePinyinPracticeRun(scheme: .flypy, level: .basic, items: Array(items.prefix(2)), started: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(run.currentCode, "xl")
        XCTAssertEqual(run.press("x"), .right)
        // 小鹤 xk 是 xing：按成了 ing，iang 在 l。
        XCTAssertEqual(run.press("k"), .wrong(.init(got: "ing", unit: "iang", key: "l")))
        XCTAssertEqual(run.typed, "x")
        XCTAssertEqual(run.press("l"), .nextCharacter)
        XCTAssertEqual(run.doneCharacters, 1)
        // 第一下按错：u 是 sh。
        XCTAssertEqual(run.press("u"), .wrong(.init(got: "sh", unit: "x", key: "x")))
        XCTAssertEqual(run.press("x"), .right)
        XCTAssertEqual(run.press("n"), .finished)
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(run.keys, 6)
        XCTAssertEqual(run.wrong, 2)
        XCTAssertEqual(run.missedItems, ["想", "小"])
        XCTAssertEqual(run.missedCharacters.map { $0.code }, ["xl", "xn"])

        var state = DoublePinyinPracticeState()
        run.record(into: &state, now: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(state.sessions.first?.characters, 2)
        XCTAssertEqual(state.mistakes["l|iang"], 1)
        XCTAssertEqual(state.mistakes["x|x"], 1)
        XCTAssertEqual(state.missed[.basic], ["想", "小"])
        XCTAssertEqual(state.mastered[.basic] ?? [], [])
        XCTAssertEqual(DoublePinyinPracticeStore.topMistakes(state).first?.times, 1)
    }

    func testRunAcceptsAlternates() {
        var run = DoublePinyinPracticeRun(scheme: .flypy, level: .basic,
                                          items: DoublePinyinPracticeItem.parse("爱\tai\n去\tqu\n"))
        XCTAssertEqual(run.press("a"), .right)
        XCTAssertEqual(run.press("d"), .nextCharacter)
        XCTAssertEqual(run.press("q"), .right)
        XCTAssertEqual(run.press("v"), .finished)
        XCTAssertEqual(run.wrong, 0)
        XCTAssertEqual(run.cleanItems, ["爱", "去"])
    }
}

/// 双拼纠错（SP9）：键对换成全拼、拼得成的前缀（不用 KeyLM 的那部分）。
final class DoublePinyinCorrectionTests: XCTestCase {
    func testSpell() {
        XCTAssertEqual(Corrector.spell(Array("nihc".utf8), .flypy).map { String(decoding: $0, as: UTF8.self) }, "nihao")
        // 最后单下一个键换成声母：u 是 sh。
        XCTAssertEqual(Corrector.spell(Array("xlu".utf8), .flypy).map { String(decoding: $0, as: UTF8.self) }, "xiangsh")
        XCTAssertEqual(Corrector.spell(Array("nihv".utf8), .flypy).map { String(decoding: $0, as: UTF8.self) }, "nihui")
        XCTAssertNil(Corrector.spell(Array("nifk".utf8), .flypy))
    }

    func testPairPrefix() {
        XCTAssertEqual(Corrector.pairPrefix(Array("nihc".utf8), .flypy), 4)
        XCTAssertEqual(Corrector.pairPrefix(Array("nihcm".utf8), .flypy), 5)
        // fk 拼不成：卡在这一对，f 能当第一下，算到 f。
        XCTAssertEqual(Corrector.pairPrefix(Array("nifkma".utf8), .flypy), 3)
    }
}
