import CoreGraphics
import Foundation

/// 盖在按键区上的面板。
enum KeysPanel: Equatable {
    case emoji, kaomoji, pinyin
}

/// 长按按键弹出的一排备选，手指左右滑动来选，松手上屏。
struct AlternatesPopup: Equatable {
    let key: KeySpec
    let options: [String]
    let containerWidth: CGFloat
    var selected = 0

    static let cellWidth: CGFloat = 34
    static let height: CGFloat = 48

    /// 从按键正上方往右排，排不下就整体往左挪。
    var frame: CGRect {
        let width = Self.cellWidth * CGFloat(options.count)
        var x = key.cap.midX - Self.cellWidth / 2
        x = min(max(x, 0), max(containerWidth - width, 0))
        return CGRect(x: x, y: key.cap.minY - Self.height - 4, width: width, height: Self.height)
    }

    func index(atX x: CGFloat) -> Int {
        let raw = Int(((x - frame.minX) / Self.cellWidth).rounded(.down))
        return min(max(raw, 0), options.count - 1)
    }
}

/// 表情按 Unicode 区段分组，只取默认就显示成彩色表情的字符，不用自己维护一大张表。
enum EmojiCatalog {
    struct Category: Identifiable {
        let id: String
        let symbol: String
        let emoji: [String]
    }

    private static func collect(_ ranges: [ClosedRange<UInt32>]) -> [String] {
        ranges.flatMap { $0 }.compactMap(Unicode.Scalar.init).filter(\.properties.isEmojiPresentation)
            .map { String($0) }
    }

    static let categories: [Category] = [
        Category(id: "笑脸", symbol: "face.smiling",
                 emoji: collect([0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1FAE0...0x1FAE8])),
        Category(id: "手势", symbol: "hand.raised",
                 emoji: collect([0x1F446...0x1F450, 0x1F90C...0x1F91F, 0x1F4AA...0x1F4AA, 0x1FAF0...0x1FAF8])),
        Category(id: "动物", symbol: "pawprint",
                 emoji: collect([0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F331...0x1F344])),
        Category(id: "食物", symbol: "fork.knife",
                 emoji: collect([0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB])),
        Category(id: "活动", symbol: "soccerball",
                 emoji: collect([0x1F380...0x1F3FA])),
        Category(id: "出行", symbol: "car",
                 emoji: collect([0x1F680...0x1F6FF, 0x1F300...0x1F320])),
        Category(id: "物品", symbol: "lightbulb",
                 emoji: collect([0x1F4A0...0x1F4FF, 0x1F500...0x1F53D])),
        Category(id: "符号", symbol: "heart",
                 emoji: collect([0x2600...0x27BF, 0x1F9E1...0x1F9E1, 0x1F90D...0x1F90F, 0x2B50...0x2B55])),
    ]
}

/// 最近用过的表情，存在共享设置里，最多 30 个。
enum RecentEmoji {
    private static let key = "keyboard.recentEmoji"

    static var all: [String] { SharedStorage.defaults.stringArray(forKey: key) ?? [] }

    static func add(_ emoji: String) {
        var list = all.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        SharedStorage.defaults.set(Array(list.prefix(30)), forKey: key)
    }
}

/// 常用颜文字。
enum Kaomoji {
    static let all: [String] = [
        "^_^", "^^", "(^_^)", "(≧▽≦)", "(｡•̀ᴗ-)✧", "(๑•̀ㅂ•́)و✧", "(*^▽^*)", "(～￣▽￣)～",
        "(＾▽＾)", "o(*￣▽￣*)o", "(´▽`ʃ♡ƪ)", "(づ｡◕‿‿◕｡)づ", "(｡･ω･｡)", "(・∀・)", "(￣▽￣)~*", "ヾ(≧▽≦*)o",
        "(；′⌒`)", "(T_T)", "(╥﹏╥)", "QAQ", "(´；ω；`)", "(￣﹏￣；)", "(⊙_⊙)?", "(°ー°〃)",
        "(╯°□°）╯︵ ┻━┻", "┬─┬ノ( º _ ºノ)", "(￣^￣)", "(｀へ´)", "(＃｀Д´)", "(；一_一)", "¯\\_(ツ)_/¯", "(-_-)zzz",
        "(｡>﹏<｡)", "(*/ω＼*)", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", "(ﾉ´ヮ`)ﾉ*: ･ﾟ", "♪(^∇^*)", "(ง •_•)ง", "orz", "Σ(っ °Д °;)っ",
    ]
}
