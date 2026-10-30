import CoreGraphics
import Foundation

/// 动态热区：打拼音时手指落在两个键交界附近，判给按拼音规律更可能的那个。全键盘按字母算，九宫格按数字串算
/// （比如打了 94 之后，哪些数字还能接成拼音）。
/// 和系统键盘一样，键的样子不变，只是判定悄悄偏向可能的字母：打了「zh」后 a/e/i/o/u 更容易按中，
/// 拼不成拼音的字母（比如开头的 i、u、v）要按得更准才算。按在键中间时永远是那个键。
enum TouchPrior {
    /// 每个键的「手指偏差」，按键宽高算的标准差。越小越相信落点。
    private static let sigma: Double = 0.45
    /// 下一个字母接着拼成当前音节、开始新音节、哪种都不行。
    private static let extendsWeight = 1.0
    private static let startsWeight = 0.55
    private static let impossibleWeight = 0.08
    /// 落在命中键中间这一块（离校准后的中心横向不到 1/4 键宽、纵向不到 0.3 键高）就不换：
    /// 拼不成拼音的字母（wifi 的 i）权重低，没有这条按正中间也会输给隔壁。按偏了交给纠错层。
    private static let centerX = 0.25
    private static let centerY = 0.3

    /// 落点 point、原本命中的键 hit；只在字母键之间换。raw：已经打了、还没上屏的拼音，不在打拼音时为空（只按手指习惯校准）。
    static func resolve(point: CGPoint, hit: KeySpec, keys: [KeySpec], raw: String?) -> KeySpec {
        guard let mode = Mode(hit), let hitChar = symbol(of: hit, mode) else { return hit }
        let hitShift = TouchCalibration.shift(for: calibrationKey(hitChar, mode))
        if abs(Double((point.x - hit.frame.midX) / hit.frame.width) - hitShift.dx) < centerX,
           abs(Double((point.y - hit.frame.midY) / hit.frame.height) - hitShift.dy) < centerY {
            return hit
        }
        let neighbors = keys.filter { key in
            guard symbol(of: key, mode) != nil else { return false }
            let dx = abs(point.x - key.frame.midX) / key.frame.width
            let dy = abs(point.y - key.frame.midY) / key.frame.height
            return dx < 1.1 && dy < 0.9
        }
        guard neighbors.count > 1 else { return hit }
        let context = raw.map { Context($0, mode) }
        var best = hit
        var bestScore = -1.0
        for key in neighbors {
            guard let char = symbol(of: key, mode) else { continue }
            // 键的中心按手指习惯挪过（没学到时不挪）。
            let shift = TouchCalibration.shift(for: calibrationKey(char, mode))
            let dx = Double((point.x - key.frame.midX) / key.frame.width) - shift.dx
            let dy = Double((point.y - key.frame.midY) / key.frame.height) - shift.dy
            let spatial = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
            let score = spatial * (context?.weight(of: char) ?? 1)
            if score > bestScore {
                bestScore = score
                best = key
            }
        }
        return best
    }

    /// 纠错的触点解码（TouchTrail）：这个键打出的字母（小写）或数字，和落点相对（按手指习惯挪过的）键中心的偏移。别的键为 nil。
    static func trailEntry(for key: KeySpec, at point: CGPoint) -> (Character, TouchTrail.Offset)? {
        guard let mode = Mode(key), let char = symbol(of: key, mode) else { return nil }
        let shift = TouchCalibration.shift(for: calibrationKey(char, mode))
        return (char, TouchTrail.Offset(dx: Double((point.x - key.frame.midX) / key.frame.width) - Double(shift.dx),
                                        dy: Double((point.y - key.frame.midY) / key.frame.height) - Double(shift.dy)))
    }

    /// 校准用的键名：全键盘和九宫格分开记。别的键不校准。
    static func calibrationKey(for key: KeySpec) -> String? {
        guard let mode = Mode(key), let char = symbol(of: key, mode) else { return nil }
        return calibrationKey(char, mode)
    }

    private static func calibrationKey(_ char: Character, _ mode: Mode) -> String {
        (mode == .letters ? "q:" : "9:") + String(char)
    }

    private enum Mode {
        case letters, digits

        init?(_ key: KeySpec) {
            switch key.kind {
            case .letter: self = .letters
            case .nine: self = .digits
            default: return nil
            }
        }

        var syllables: Set<String> { self == .letters ? TouchPrior.syllables : TouchPrior.digitSyllables }
        var prefixes: Set<String> { self == .letters ? TouchPrior.prefixes : TouchPrior.digitPrefixes }

        func belongs(_ char: Character) -> Bool {
            self == .letters ? (char.isASCII && char.isLetter) : ("2"..."9").contains(char)
        }
    }

    /// 键上的字母（全键盘）或数字 2–9（九宫格）；别的键不参与。
    private static func symbol(of key: KeySpec, _ mode: Mode) -> Character? {
        let text: String
        switch (key.kind, mode) {
        case (.letter(let value), .letters): text = value.lowercased()
        case (.nine(let value), .digits): text = value
        default: return nil
        }
        guard text.count == 1, let char = text.first, mode.belongs(char) else { return nil }
        return char
    }

    /// 已打的拼音能怎么切：哪些位置之前恰好切成完整音节，以及从这些位置起剩下的那截（正在拼的音节）。
    private struct Context {
        /// 正在拼、还没拼完的那截（可能有几种切法）。
        let partial: [String]
        /// 已打的拼音恰好切成完整音节，下一个字母可以开始新音节。
        let complete: Bool

        let prefixes: Set<String>

        init(_ raw: String, _ mode: Mode) {
            let prefixSet = mode.prefixes
            prefixes = prefixSet
            let syllables = mode.syllables
            // 只看最后一个分隔符（九宫格还有选拼音后留下的字母）之后的部分，最多 16 个。
            let tail = String(raw.lowercased().split(whereSeparator: { !mode.belongs($0) }).last ?? "")
            let s = Array(tail.suffix(16))
            var reachable = Array(repeating: false, count: s.count + 1)
            reachable[0] = true
            for i in 0..<s.count where reachable[i] {
                for length in 1...min(6, s.count - i) where syllables.contains(String(s[i..<(i + length)])) {
                    reachable[i + length] = true
                }
            }
            partial = (0..<s.count).filter { reachable[$0] }.map { String(s[$0...]) }.filter { prefixSet.contains($0) }
            complete = reachable[s.count]
        }

        func weight(of char: Character) -> Double {
            // 已打的字母本来就拼不成拼音（比如混着打的英文）：没法判断，不偏。
            guard !partial.isEmpty || complete else { return 1 }
            if partial.contains(where: { prefixes.contains($0 + String(char)) }) { return TouchPrior.extendsWeight }
            if complete && prefixes.contains(String(char)) {
                return partial.isEmpty ? TouchPrior.extendsWeight : TouchPrior.startsWeight
            }
            return TouchPrior.impossibleWeight
        }
    }

    /// 完整音节，加上方案里认的写法：单独的声母（简拼）、ü 写成 v、ong 少个 g、ng 打成 gn。
    static let syllables: Set<String> = {
        var result = Set(PinyinSyllables.all)
        for initial in ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"] {
            result.insert(initial)
        }
        for syllable in PinyinSyllables.all {
            if let first = syllable.first, "jqxy".contains(first), syllable.dropFirst().hasPrefix("u") {
                result.insert(String(first) + "v" + syllable.dropFirst(2))
            }
            if syllable.hasSuffix("ong") { result.insert(String(syllable.dropLast())) }
            if syllable.hasSuffix("ng"), let vowel = syllable.dropLast(2).last, "aeio".contains(vowel) {
                result.insert(String(syllable.dropLast(2)) + "gn")
            }
        }
        return result
    }()

    /// 所有音节的前缀（含完整音节），正在拼的那截是不是还拼得下去。
    static let prefixes: Set<String> = {
        var result = Set<String>()
        for syllable in syllables {
            for length in 1...syllable.count { result.insert(String(syllable.prefix(length))) }
        }
        return result
    }()

    /// 九宫格：同样的音节和前缀换成数字串。
    static let digitSyllables = Set(syllables.map(PinyinSyllables.digits(of:)))
    static let digitPrefixes = Set(prefixes.map(PinyinSyllables.digits(of:)))
}
