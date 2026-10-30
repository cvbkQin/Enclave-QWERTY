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
    private let lm: KeyLM

    /// 改法的罚分（nats）：九宫格一个数字对应几个字母，手误后的串常常还拼得成，罚得轻一些。
    private let penalty: [Edit: Double]
    /// 改过的串要比原样的可能性高约 400 倍（e^6）才动。
    static let margin = 6.0
    /// 改一处不够、改两处时多罚的。
    static let secondEdit = 1.0
    /// 拼不成时只改拼不下去那个位置往前 5 个键以内。
    static let window = 5

    enum Edit { case swap, delete, substitute, insert }

    init(lm: KeyLM, nineKey: Bool) {
        self.lm = lm
        self.nineKey = nineKey
        penalty = nineKey
            ? [.swap: 1.0, .delete: 2.0, .substitute: 1.0, .insert: 1.0]
            : [.swap: 1.5, .delete: 2.5, .substitute: 1.5, .insert: 1.5]
    }

    /// 词库自带的表在不在；不在就不纠（比如还没运行 scripts/fetch-rime.sh 生成）。
    static func bundled(nineKey: Bool) -> Corrector? {
        KeyLM.bundled(nineKey: nineKey).map { Corrector(lm: $0, nineKey: nineKey) }
    }

    /// 这个输入要不要纠、纠成什么。带分词符的、全是声母的（简拼）不纠。
    /// extraMargin：这个输入学到的门槛调整（CorrectionMemory.bias），正的更难纠。
    func guess(_ input: String, extraMargin: Double = 0) -> Guess? {
        let keys = Array(input.utf8)
        guard !keys.isEmpty, keys.allSatisfy(isKey) else { return nil }
        if !nineKey && keys.allSatisfy({ !Self.vowels.contains($0) }) { return nil }
        let original = lm.score(keys)
        let reach = strictPrefix(keys)
        var found: [[UInt8]: Double] = [:]
        let place: Int
        if reach < keys.count {
            // 拼不成：改一处够了就不试两处。
            let first = edits(keys, from: reach - Self.window, to: reach + 1)
            for (variant, edit) in first where strictPrefix(variant) == variant.count {
                found[variant] = penalty[edit]!
            }
            if found.isEmpty {
                for (variant, edit) in first {
                    let reach2 = strictPrefix(variant)
                    for (variant2, edit2) in edits(variant, from: reach2 - Self.window, to: reach2 + 1)
                    where strictPrefix(variant2) == variant2.count {
                        let cost = penalty[edit]! + penalty[edit2]! + Self.secondEdit
                        if found[variant2].map({ cost < $0 }) ?? true { found[variant2] = cost }
                    }
                }
            }
            place = 1
        } else {
            for (variant, edit) in edits(keys, from: 0, to: keys.count) where strictPrefix(variant) == variant.count {
                found[variant] = penalty[edit]!
            }
            place = 2
        }
        // 按字节序挨个比，分数一样时取先遇到的，和参考实现一致。
        var best: (keys: [UInt8], score: Double)?
        for variant in found.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let score = lm.score(variant) + found[variant]!
            if best.map({ score < $0.score }) ?? true { best = (variant, score) }
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

    /// 改一处，只改 [from, to) 这一段。同一个结果有几种改法时记第一种（顺序和参考实现相同）。
    private func edits(_ keys: [UInt8], from: Int, to: Int) -> [([UInt8], Edit)] {
        var seen: Set<[UInt8]> = [keys]
        var out: [([UInt8], Edit)] = []
        func add(_ variant: [UInt8], _ edit: Edit) {
            if seen.insert(variant).inserted { out.append((variant, edit)) }
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
                    add(replaced, .substitute)
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
