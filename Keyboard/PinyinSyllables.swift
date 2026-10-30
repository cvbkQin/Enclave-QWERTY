import Foundation

/// 选拼音用的音节（九宫格拼音行、全键盘换切法）；音节表本身在 Shared 的 PinyinTable。
enum PinyinSyllables {
    /// 全部音节，外加单独的 zh/ch/sh（简拼时用）。
    static let all: [String] = {
        var result = ["zh", "ch", "sh"]
        for (initial, finals) in PinyinTable.finalsByInitial {
            result += finals.split(separator: " ").map { initial + $0 }
        }
        return result
    }()

    static func digits(of syllable: String) -> String {
        String(syllable.map { letter in
            KeyLayout.nineKeyLetters.first { $0.value.lowercased().contains(letter) }?.key.first ?? letter
        })
    }

    private static let byDigits: [String: [String]] = Dictionary(grouping: all, by: digits(of:))

    private static let full: Set<String> = Set(all).subtracting(["zh", "ch", "sh"])

    /// 全键盘：一串字母切成整音节的几种切法（xian → xian、xi'an），音节少的在前，最多 limit 种。切不成整音节时是空的。
    static func segmentations(_ letters: String, limit: Int = 6) -> [String] {
        let chars = Array(letters)
        var results: [[String]] = []
        func walk(_ start: Int, _ path: [String]) {
            guard results.count < limit * 4 else { return }
            if start == chars.count { results.append(path); return }
            for end in stride(from: min(chars.count, start + 6), to: start, by: -1) {
                let piece = String(chars[start..<end])
                if full.contains(piece) { walk(end, path + [piece]) }
            }
        }
        walk(0, [])
        return results.sorted { $0.count < $1.count }.prefix(limit).map { $0.joined(separator: "'") }
    }

    /// 这串数字开头能拼出的音节，长的在前；最后补上第一个数字键上的单个字母。
    static func options(forDigits digits: String) -> [String] {
        guard let first = digits.first else { return [] }
        var result: [String] = []
        for length in stride(from: min(digits.count, 6), through: 2, by: -1) {
            result += (byDigits[String(digits.prefix(length))] ?? []).sorted()
        }
        let letters = KeyLayout.nineKeyLetters[String(first)]?.lowercased().map(String.init) ?? []
        return result + letters
    }
}
