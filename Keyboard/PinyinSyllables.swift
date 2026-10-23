import Foundation

/// 九宫格选拼音用的音节表：按声母列出能跟的韵母，拼起来就是全部合法音节。
enum PinyinSyllables {
    private static let table: [String: String] = [
        "": "a ai an ang ao e ei en eng er o ou",
        "b": "a ai an ang ao ei en eng i ian iao ie in ing o u",
        "p": "a ai an ang ao ei en eng i ian iao ie in ing o ou u",
        "m": "a ai an ang ao e ei en eng i ian iao ie in ing iu o ou u",
        "f": "a an ang ei en eng o ou u",
        "d": "a ai an ang ao e ei en eng i ia ian iao ie ing iu ong ou u uan ui un uo",
        "t": "a ai an ang ao e ei eng i ian iao ie ing ong ou u uan ui un uo",
        "n": "a ai an ang ao e ei en eng i ian iang iao ie in ing iu ong ou u uan un uo v ve",
        "l": "a ai an ang ao e ei eng i ia ian iang iao ie in ing iu o ong ou u uan un uo v ve",
        "g": "a ai an ang ao e ei en eng ong ou u ua uai uan uang ui un uo",
        "k": "a ai an ang ao e ei en eng ong ou u ua uai uan uang ui un uo",
        "h": "a ai an ang ao e ei en eng ong ou u ua uai uan uang ui un uo",
        "j": "i ia ian iang iao ie in ing iong iu u uan ue un",
        "q": "i ia ian iang iao ie in ing iong iu u uan ue un",
        "x": "i ia ian iang iao ie in ing iong iu u uan ue un",
        "zh": "a ai an ang ao e ei en eng i ong ou u ua uai uan uang ui un uo",
        "ch": "a ai an ang ao e en eng i ong ou u ua uai uan uang ui un uo",
        "sh": "a ai an ang ao e ei en eng i ou u ua uai uan uang ui un uo",
        "r": "an ang ao e en eng i ong ou u ua uan ui un uo",
        "z": "a ai an ang ao e ei en eng i ong ou u uan ui un uo",
        "c": "a ai an ang ao e en eng i ong ou u uan ui un uo",
        "s": "a ai an ang ao e en eng i ong ou u uan ui un uo",
        "y": "a an ang ao e i in ing o ong ou u uan ue un",
        "w": "a ai an ang ei en eng o u",
    ]

    /// 全部音节，外加单独的 zh/ch/sh（简拼时用）。
    static let all: [String] = {
        var result = ["zh", "ch", "sh"]
        for (initial, finals) in table {
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
