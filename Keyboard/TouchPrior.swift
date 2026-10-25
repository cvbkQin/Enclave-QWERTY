import CoreGraphics
import Foundation

/// 动态热区：全键盘打拼音时，手指落在两个字母键交界附近，判给按拼音规律更可能的那个。
/// 和系统键盘一样，键的样子不变，只是判定悄悄偏向可能的字母：打了「zh」后 a/e/i/o/u 更容易按中，
/// 拼不成拼音的字母（比如开头的 i、u、v）要按得更准才算。按在键中间时永远是那个键。
enum TouchPrior {
    /// 每个键的「手指偏差」，按键宽高算的标准差。越小越相信落点。
    private static let sigma: Double = 0.45
    /// 下一个字母接着拼成当前音节、开始新音节、哪种都不行。
    private static let extendsWeight = 1.0
    private static let startsWeight = 0.55
    private static let impossibleWeight = 0.08

    /// 落点 point、原本命中的键 hit；只在字母键之间换。raw：已经打了、还没上屏的拼音。
    static func resolve(point: CGPoint, hit: KeySpec, keys: [KeySpec], raw: String) -> KeySpec {
        guard letter(of: hit) != nil else { return hit }
        let neighbors = keys.filter { key in
            guard letter(of: key) != nil else { return false }
            let dx = abs(point.x - key.frame.midX) / key.frame.width
            let dy = abs(point.y - key.frame.midY) / key.frame.height
            return dx < 1.1 && dy < 0.9
        }
        guard neighbors.count > 1 else { return hit }
        let context = Context(raw)
        var best = hit
        var bestScore = -1.0
        for key in neighbors {
            guard let char = letter(of: key) else { continue }
            let dx = Double((point.x - key.frame.midX) / key.frame.width)
            let dy = Double((point.y - key.frame.midY) / key.frame.height)
            let spatial = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
            let score = spatial * context.weight(of: char)
            if score > bestScore {
                bestScore = score
                best = key
            }
        }
        return best
    }

    private static func letter(of key: KeySpec) -> Character? {
        guard case .letter(let text) = key.kind, text.count == 1, let char = text.lowercased().first,
              char.isASCII, char.isLetter else { return nil }
        return char
    }

    /// 已打的拼音能怎么切：哪些位置之前恰好切成完整音节，以及从这些位置起剩下的那截（正在拼的音节）。
    private struct Context {
        /// 正在拼、还没拼完的那截（可能有几种切法）。
        let partial: [String]
        /// 已打的拼音恰好切成完整音节，下一个字母可以开始新音节。
        let complete: Bool

        init(_ raw: String) {
            // 只看最后一个分隔符之后的字母，最多 16 个。
            let letters = String(raw.lowercased().split(whereSeparator: { !($0.isASCII && $0.isLetter) }).last ?? "")
            let s = Array(letters.suffix(16))
            var reachable = Array(repeating: false, count: s.count + 1)
            reachable[0] = true
            for i in 0..<s.count where reachable[i] {
                for length in 1...min(6, s.count - i) where TouchPrior.syllables.contains(String(s[i..<(i + length)])) {
                    reachable[i + length] = true
                }
            }
            partial = (0..<s.count).filter { reachable[$0] }.map { String(s[$0...]) }.filter { TouchPrior.prefixes.contains($0) }
            complete = reachable[s.count]
        }

        func weight(of char: Character) -> Double {
            // 已打的字母本来就拼不成拼音（比如混着打的英文）：没法判断，不偏。
            guard !partial.isEmpty || complete else { return 1 }
            if partial.contains(where: { TouchPrior.prefixes.contains($0 + String(char)) }) { return TouchPrior.extendsWeight }
            if complete && TouchPrior.prefixes.contains(String(char)) {
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
}
