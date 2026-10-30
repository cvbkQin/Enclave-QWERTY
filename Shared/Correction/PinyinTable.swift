import Foundation

/// 拼音音节表：按声母列出能跟的韵母，拼起来就是全部合法音节。键盘的选拼音（PinyinSyllables）和纠错（Corrector）共用。
enum PinyinTable {
    static let finalsByInitial: [String: String] = [
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

    /// 全部完整音节（不含单独的 zh/ch/sh）。
    static let syllables: [String] = finalsByInitial.flatMap { initial, finals in
        finals.split(separator: " ").map { initial + $0 }
    }
}
