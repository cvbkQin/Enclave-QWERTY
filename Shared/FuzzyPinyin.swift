import Foundation

/// 模糊拼音：每组是一对能互相代替的拼写，部署词库时写进方案的 speller/algebra 生效。
enum FuzzyPinyin: String, Codable, CaseIterable, Identifiable {
    case zh, ch, sh, nl, lr, fh
    case ang, eng, ing, iang, uang

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zh: return "z = zh"
        case .ch: return "c = ch"
        case .sh: return "s = sh"
        case .nl: return "n = l"
        case .lr: return "l = r"
        case .fh: return "f = h"
        case .ang: return "an = ang"
        case .eng: return "en = eng"
        case .ing: return "in = ing"
        case .iang: return "ian = iang"
        case .uang: return "uan = uang"
        }
    }

    static let initials: [FuzzyPinyin] = [.zh, .ch, .sh, .nl, .lr, .fh]
    static let finals: [FuzzyPinyin] = [.ang, .eng, .ing, .iang, .uang]

    /// 拼写运算规则，双向派生。an = ang 不碰 ian / uan，那两组单独开。
    var rules: [String] {
        switch self {
        case .zh: return ["derive/^zh/z/", "derive/^z([^h])/zh$1/"]
        case .ch: return ["derive/^ch/c/", "derive/^c([^h])/ch$1/"]
        case .sh: return ["derive/^sh/s/", "derive/^s([^h])/sh$1/"]
        case .nl: return ["derive/^n([^g]|$)/l$1/", "derive/^l/n/"]
        case .lr: return ["derive/^l/r/", "derive/^r/l/"]
        case .fh: return ["derive/^f/h/", "derive/^h/f/"]
        case .ang: return ["derive/^([^iu]*)an$/$1ang/", "derive/^([^iu]*)ang$/$1an/"]
        case .eng: return ["derive/en$/eng/", "derive/eng$/en/"]
        case .ing: return ["derive/in$/ing/", "derive/ing$/in/"]
        case .iang: return ["derive/ian$/iang/", "derive/iang$/ian/"]
        case .uang: return ["derive/uan$/uang/", "derive/uang$/uan/"]
        }
    }

    /// 快速选择。
    enum Preset: CaseIterable, Identifiable {
        case off, retroflex, nasal, southern

        var id: Self { self }

        var title: String {
            switch self {
            case .off: return "全部关闭"
            case .retroflex: return "平翘舌不分"
            case .nasal: return "前后鼻音不分"
            case .southern: return "南方口音"
            }
        }

        var groups: Set<FuzzyPinyin> {
            switch self {
            case .off: return []
            case .retroflex: return [.zh, .ch, .sh]
            case .nasal: return [.ang, .eng, .ing, .iang, .uang]
            case .southern: return [.zh, .ch, .sh, .nl, .fh, .eng, .ing]
            }
        }
    }

    /// 写进已部署版本号的后缀；模糊音变了，键盘就知道要重新加载。
    static func versionTag(_ groups: Set<FuzzyPinyin>) -> String {
        groups.isEmpty ? "" : "+fuzzy:" + allCases.filter(groups.contains).map(\.rawValue).joined(separator: ",")
    }

    /// 把规则插到方案 speller/algebra 列表最前面（九宫格要在数字映射之前派生）。找不到就原样返回。
    static func patchSchema(_ text: String, groups: Set<FuzzyPinyin>) -> String {
        guard !groups.isEmpty,
              let speller = text.range(of: "\nspeller:\n"),
              let algebra = text.range(of: "\n  algebra:\n", range: speller.upperBound..<text.endIndex)
        else { return text }
        let lines = allCases.filter(groups.contains).flatMap(\.rules).map { "    - \($0)\n" }.joined()
        var patched = text
        patched.insert(contentsOf: "    # Enclave 模糊拼音\n" + lines, at: algebra.upperBound)
        return patched
    }
}
