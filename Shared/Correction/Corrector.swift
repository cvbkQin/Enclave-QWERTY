import Foundation

/// 纠错层（0.94）：输入像打错了时，试着改一处（按反、多打、按到邻键、漏打），用 KeyLM 挑最像话的改法。
/// 只决定「改成哪个串、放第几位」；改后的串打出什么字，由调用的地方去问引擎（见 CorrectionMerge）。
/// 规则和参数来自 0.94 纠错方案（correction-094/HANDOFF.md），参考实现是 scripts/correction/corrector_ref.py，
/// 单元测试拿 Tests/Correction/golden.json 对拍。
final class Corrector {
    struct Guess: Equatable {
        /// 改过的按键串。
        var corrected: String
        /// 放第几位：1 首选（拼不成完整拼音时），2 第二位（拼得成，但改一处后像话得多）。
        var place: Int
    }

    let nineKey: Bool
    /// 双拼（双拼调研 P3-10，设计稿 SP9）：按的是键对。改法照样在按键上做（换邻键、按反、多打、漏打），
    /// 拼不拼得成按键对查，像不像话把键对换成全拼再用全拼那份表打分。
    let doublePinyin: DoublePinyin?
    private let lm: KeyLM

    /// 改法的罚分（nats）：九宫格一个数字对应几个字母，手误后的串常常还拼得成，罚得轻一些。
    private let penalty: [Edit: Double]
    /// 改过的串要比原样的可能性高约 400 倍（e^6）才动。
    static let margin = 6.0
    /// 改一处不够、改两处时多罚的。
    static let secondEdit = 1.0
    /// 拼不成时只改拼不下去那个位置往前 5 个键以内。
    static let window = 5
    /// 触点解码：手指落点的偏差（按键宽高算的标准差，和 TouchPrior 一样），
    /// 换成邻键时罚分最多加 2（按在正中间）、最多减 1（明显偏向那个邻键）。
    static let touchSigma = 0.45
    static let touchMaxExtra = 2.0
    static let touchMaxRelief = 1.0

    enum Edit { case swap, delete, substitute, insert }

    init(lm: KeyLM, nineKey: Bool, doublePinyin: DoublePinyin? = nil) {
        self.lm = lm
        self.nineKey = nineKey
        self.doublePinyin = nineKey ? nil : doublePinyin
        penalty = nineKey
            ? [.swap: 1.0, .delete: 2.0, .substitute: 1.0, .insert: 1.0]
            : [.swap: 1.5, .delete: 2.5, .substitute: 1.5, .insert: 1.5]
    }

    /// 词库自带的表在不在；不在就不纠（比如还没运行 scripts/fetch-rime.sh 生成）。
    static func bundled(nineKey: Bool, doublePinyin: DoublePinyin? = nil) -> Corrector? {
        KeyLM.bundled(nineKey: nineKey).map { Corrector(lm: $0, nineKey: nineKey, doublePinyin: doublePinyin) }
    }

    /// 这个输入要不要纠、纠成什么。带分词符的、全是声母的（简拼）不纠。
    /// extraMargin：这个输入学到的门槛调整（CorrectionMemory.bias），正的更难纠。
    /// touches：每个键的落点（TouchTrail），没有时照固定罚分（和 0.94、参考实现一致）。
    func guess(_ input: String, extraMargin: Double = 0, touches: [TouchTrail.Offset]? = nil) -> Guess? {
        let keys = Array(input.utf8)
        guard !keys.isEmpty, keys.allSatisfy(isKey) else { return nil }
        let touches = touches?.count == keys.count ? touches : nil
        // 全是声母的是简拼，不纠；双拼的键对本来就常没有元音（xl＝xiang），不看这条。
        if !nineKey, doublePinyin == nil, keys.allSatisfy({ !Self.vowels.contains($0) }) { return nil }
        let original = score(keys)
        let reach = strictPrefix(keys)
        var found: [[UInt8]: Double] = [:]
        let place: Int
        if reach < keys.count {
            // 拼不成：改一处够了就不试两处。
            let first = edits(keys, from: reach - Self.window, to: reach + 1, touches: touches)
            for (variant, cost) in first where strictPrefix(variant) == variant.count {
                found[variant] = cost
            }
            if found.isEmpty {
                // 第二处改在改过的串上，位置对不上落点了，按固定罚分。
                for (variant, firstCost) in first {
                    let reach2 = strictPrefix(variant)
                    for (variant2, secondCost) in edits(variant, from: reach2 - Self.window, to: reach2 + 1, touches: nil)
                    where strictPrefix(variant2) == variant2.count {
                        let cost = firstCost + secondCost + Self.secondEdit
                        if found[variant2].map({ cost < $0 }) ?? true { found[variant2] = cost }
                    }
                }
            }
            place = 1
        } else {
            for (variant, cost) in edits(keys, from: 0, to: keys.count, touches: touches) where strictPrefix(variant) == variant.count {
                found[variant] = cost
            }
            place = 2
        }
        // 按字节序挨个比，分数一样时取先遇到的，和参考实现一致。
        var best: (keys: [UInt8], score: Double)?
        for variant in found.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let total = score(variant) + found[variant]!
            if best.map({ total < $0.score }) ?? true { best = (variant, total) }
        }
        guard let best, best.score < original - Self.margin - extraMargin else { return nil }
        return Guess(corrected: String(decoding: best.keys, as: UTF8.self), place: place)
    }

    // MARK: 改法

    private static let letters = Array("abcdefghijklmnopqrstuvwxyz".utf8)
    private static let digits = Array("23456789".utf8)
    private static let vowels = Set("aeiouv".utf8)

    private func isKey(_ key: UInt8) -> Bool {
        nineKey ? Self.digits.contains(key) : Self.letters.contains(key)
    }

    /// 改一处，只改 [from, to) 这一段，返回改过的串和罚分。同一个结果有几种改法时记第一种（顺序和参考实现相同）。
    /// touches 和 keys 对齐时，换成邻键的罚分按落点调（touchAdjustment）。
    private func edits(_ keys: [UInt8], from: Int, to: Int, touches: [TouchTrail.Offset]?) -> [([UInt8], Double)] {
        var seen: Set<[UInt8]> = [keys]
        var out: [([UInt8], Double)] = []
        func add(_ variant: [UInt8], _ edit: Edit, _ adjust: Double = 0) {
            if seen.insert(variant).inserted { out.append((variant, penalty[edit]! + adjust)) }
        }
        let n = keys.count
        let low = max(0, from)
        if low < min(n, to) {
            for i in low..<min(n, to) {
                if i + 1 < n, keys[i] != keys[i + 1] {
                    var swapped = keys
                    swapped.swapAt(i, i + 1)
                    add(swapped, .swap)
                }
                var removed = keys
                removed.remove(at: i)
                add(removed, .delete)
                for neighbor in neighbors(keys[i]) {
                    var replaced = keys
                    replaced[i] = neighbor
                    add(replaced, .substitute, touches.map { touchAdjustment(keys[i], to: neighbor, at: $0[i]) } ?? 0)
                }
            }
        }
        if low <= min(n, to) {
            for i in low...min(n, to) {
                for key in nineKey ? Self.digits : Self.letters {
                    var inserted = keys
                    inserted.insert(key, at: i)
                    add(inserted, .insert)
                }
            }
        }
        return out
    }

    // 全键盘按 iPhone 的错位排：键宽为单位，第二、三排右移半个、一个半键；邻键是上下左右和斜对角（横向一个键以内）。
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let keyPosition: [UInt8: (x: Double, y: Int)] = {
        var result: [UInt8: (x: Double, y: Int)] = [:]
        for (row, keys) in rows.enumerated() {
            for (index, key) in keys.utf8.enumerated() { result[key] = (Double(index) + [0, 0.5, 1.5][row], row) }
        }
        return result
    }()
    private static let letterNeighbors: [UInt8: [UInt8]] = {
        var result: [UInt8: [UInt8]] = [:]
        for (key, position) in keyPosition {
            result[key] = keyPosition.keys.sorted().filter { other in
                let p = keyPosition[other]!
                return other != key && abs(p.y - position.y) <= 1 && abs(p.x - position.x) <= 1.0
            }
        }
        return result
    }()
    // 九宫格：上下左右。
    private static let gridPosition: [UInt8: (x: Int, y: Int)] = [
        0x32: (1, 0), 0x33: (2, 0), 0x34: (0, 1), 0x35: (1, 1), 0x36: (2, 1), 0x37: (0, 2), 0x38: (1, 2), 0x39: (2, 2),
    ]
    private static let digitNeighbors: [UInt8: [UInt8]] = {
        var result: [UInt8: [UInt8]] = [:]
        for (key, position) in gridPosition {
            result[key] = gridPosition.keys.sorted().filter { other in
                let p = gridPosition[other]!
                return abs(p.x - position.x) + abs(p.y - position.y) == 1
            }
        }
        return result
    }()

    private func neighbors(_ key: UInt8) -> [UInt8] {
        (nineKey ? Self.digitNeighbors : Self.letterNeighbors)[key] ?? []
    }

    /// 邻键相对按下的键在哪（键宽、键高为单位）。
    private func relative(_ neighbor: UInt8, from key: UInt8) -> (x: Double, y: Double)? {
        if nineKey {
            guard let a = Self.gridPosition[key], let b = Self.gridPosition[neighbor] else { return nil }
            return (Double(b.x - a.x), Double(b.y - a.y))
        }
        guard let a = Self.keyPosition[key], let b = Self.keyPosition[neighbor] else { return nil }
        return (b.x - a.x, Double(b.y - a.y))
    }

    /// 换成邻键的罚分调整（nats）：落点离邻键中心比离本键中心近多少，按高斯落点算对数似然比，取反后夹在范围里。
    /// 按在正中间 ≈ +2（更难改成邻键），在两键正中线上 ≈ 0（同 0.94），明显偏向邻键 ≈ −1。
    func touchAdjustment(_ key: UInt8, to neighbor: UInt8, at touch: TouchTrail.Offset) -> Double {
        guard let n = relative(neighbor, from: key) else { return 0 }
        let own = touch.dx * touch.dx + touch.dy * touch.dy
        let other = (touch.dx - n.x) * (touch.dx - n.x) + (touch.dy - n.y) * (touch.dy - n.y)
        let llr = (own - other) / (2 * Self.touchSigma * Self.touchSigma)
        return -min(max(llr, -Self.touchMaxExtra), Self.touchMaxRelief)
    }

    /// 像不像话：全拼、九宫格直接查表；双拼先把键对换成全拼（最后单下一个键换成声母），换不成的（有拼不成的键对）是 .infinity。
    private func score(_ keys: [UInt8]) -> Double {
        guard let doublePinyin else { return lm.score(keys) }
        guard let spelled = Self.spell(keys, doublePinyin) else { return .infinity }
        return lm.score(spelled)
    }

    /// 双拼按键 → 全拼字母（nihc → nihao，xl u → xiangsh）。有拼不成的键对时为 nil。
    static func spell(_ keys: [UInt8], _ scheme: DoublePinyin) -> [UInt8]? {
        let readings = Self.readingTables[scheme] ?? [:]
        var out: [UInt8] = []
        var index = 0
        while index + 1 < keys.count {
            guard let syllable = readings[String(decoding: keys[index...(index + 1)], as: UTF8.self)] else { return nil }
            out += syllable.utf8
            index += 2
        }
        if index < keys.count {
            let key = keys[index]
            guard Self.firstKeys[scheme]?.contains(key) == true else { return nil }
            let initial = DoublePinyin.retroflexKeys.first { $0.value == Character(UnicodeScalar(key)) }?.key
            out += initial.map { Array($0.utf8) } ?? [key]
        }
        return out
    }

    private static let readingTables = Dictionary(uniqueKeysWithValues: DoublePinyin.allCases.map { ($0, $0.readings) })
    /// 键对的第一下能按哪些键。
    private static let firstKeys = Dictionary(uniqueKeysWithValues: DoublePinyin.allCases.map { scheme in
        (scheme, Set(scheme.readings.keys.compactMap { $0.utf8.first }))
    })

    // MARK: 拼不拼得成

    /// 音节和音节前缀，压成整数（每个键 5 位）放进集合，查得快。
    private static func pack(_ keys: ArraySlice<UInt8>) -> UInt64 {
        keys.reduce(UInt64(0)) { $0 << 5 | UInt64($1 & 31) }
    }
    private static func tables(digits: Bool) -> (syllables: Set<UInt64>, prefixes: Set<UInt64>) {
        let map = Dictionary(uniqueKeysWithValues: [("2", "abc"), ("3", "def"), ("4", "ghi"), ("5", "jkl"), ("6", "mno"), ("7", "pqrs"), ("8", "tuv"), ("9", "wxyz")]
            .flatMap { digit, letters in letters.map { ($0, Character(digit)) } })
        var syllables = Set<UInt64>(), prefixes = Set<UInt64>()
        for syllable in PinyinTable.syllables {
            let keys = Array((digits ? String(syllable.map { map[$0] ?? $0 }) : syllable).utf8)
            syllables.insert(pack(keys[...]))
            for length in 1...keys.count { prefixes.insert(pack(keys[..<length])) }
        }
        return (syllables, prefixes)
    }
    private static let letterTables = tables(digits: false)
    private static let digitTables = tables(digits: true)

    /// 能拼成「整音节 + 最后一个没打完的音节」的最长前缀。不认中间单独的声母；全键盘词中间不认零声母音节（a、o、e 开头）。
    func strictPrefix(_ keys: [UInt8]) -> Int {
        if let doublePinyin { return Self.pairPrefix(keys, doublePinyin) }
        let (syllables, prefixes) = nineKey ? Self.digitTables : Self.letterTables
        let n = keys.count
        var ok = [Bool](repeating: false, count: n + 1)
        ok[0] = true
        var best = 0
        for i in 0..<n where ok[i] {
            for length in 1...6 {
                if i + length > n { break }
                if !nineKey, i > 0, [0x61, 0x6F, 0x65].contains(keys[i]) { continue }
                let piece = Self.pack(keys[i..<(i + length)])
                if syllables.contains(piece) { ok[i + length] = true }
                if prefixes.contains(piece) { best = max(best, i + length) }
            }
        }
        return max(best, ok.lastIndex(of: true) ?? 0)
    }

    /// 双拼：从头两两配对，都是音节、最后单下一个键能当第一下时整串都算拼得成；
    /// 卡在某一对时返回到这一对为止（这一对的第一下能当第一下时算上它）。
    static func pairPrefix(_ keys: [UInt8], _ scheme: DoublePinyin) -> Int {
        let readings = readingTables[scheme] ?? [:]
        let first = firstKeys[scheme] ?? []
        var index = 0
        while index + 1 < keys.count, readings[String(decoding: keys[index...(index + 1)], as: UTF8.self)] != nil { index += 2 }
        if index < keys.count, first.contains(keys[index]) { index += 1 }
        return index
    }
}

/// 把纠正的词并进候选：拼不成时放首选、原样的首选排第二；拼得成时放第二位。
/// 改过的串打出来的首选和原样的首选一样、或原样首选是整串英文词（wifi、iPhone），就不动。
enum CorrectionMerge {
    struct Result: Equatable {
        var candidates: [String]
        /// 纠正的词在第几个（从 0 数）。
        var index: Int
        /// 原来候选里和它重复、被拿掉的那个的位置。
        var removed: Int?
    }

    static func merge(_ candidates: [String], input: String, guess: Corrector.Guess, correctedTop: String?) -> Result? {
        guard let text = correctedTop, !text.isEmpty, let top = candidates.first, text != top else { return nil }
        // 引擎首选就是整串英文（WiFi、iPhone、OK）：不纠。
        if top.lowercased().filter({ $0 != "-" && $0 != " " }) == input.lowercased() { return nil }
        var list = candidates
        let removed = list.firstIndex(of: text)
        if let removed { list.remove(at: removed) }
        let index = min(guess.place - 1, list.count)
        list.insert(text, at: index)
        return Result(candidates: list, index: index, removed: removed)
    }
}
