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

/// 长按「中/英」的拼音布局菜单（P11）：宽 168，小标题 + 「九宫格」「全键盘」两项，手指滑到哪项选哪项。
struct LayoutMenuPopup: Equatable {
    let key: KeySpec
    let containerWidth: CGFloat
    var selected: KeyboardLayout?

    static let width: CGFloat = 168
    static let titleHeight: CGFloat = 26
    static let rowHeight: CGFloat = 36
    static let padding: CGFloat = 6
    static let options: [KeyboardLayout] = [.nineKey, .qwerty]
    static var height: CGFloat { padding * 2 + titleHeight + rowHeight * CGFloat(options.count) }

    var frame: CGRect {
        let x = min(max(key.cap.minX, 4), max(containerWidth - Self.width - 4, 0))
        return CGRect(x: x, y: max(key.cap.minY - Self.height - 6, 0), width: Self.width, height: Self.height)
    }

    func rowFrame(_ index: Int) -> CGRect {
        CGRect(x: frame.minX + Self.padding, y: frame.minY + Self.padding + Self.titleHeight + CGFloat(index) * Self.rowHeight,
               width: Self.width - Self.padding * 2, height: Self.rowHeight)
    }

    /// 手指在哪一项上；离菜单太远（横向超出、或回到键上）时不选。
    func option(at point: CGPoint) -> KeyboardLayout? {
        for (index, option) in Self.options.enumerated() {
            let row = rowFrame(index).insetBy(dx: -12, dy: 0)
            if row.contains(point) { return option }
        }
        return nil
    }
}

/// 九宫格长按弹出的十字，和原生一样：中间是按下的键，四周最多四个选项，手指滑到哪格选哪格，滑回中间松手取消。
struct CrossPopup: Equatable {
    enum Direction: CaseIterable { case left, up, right, down }

    let key: KeySpec
    let options: [Direction: String]
    let containerWidth: CGFloat
    /// 手指按下的位置，方向从这里算；没有就用键中心。
    var origin: CGPoint?
    var selected: Direction?

    /// 每格 = 一个键加一条缝。
    var cellSize: CGSize {
        CGSize(width: key.cap.width + KeyboardMetrics.nineColumnGap, height: KeyboardMetrics.nineRowPitch)
    }

    /// 中间那格：以按下的键为中心；贴边时整个十字往里收，离屏幕边至少 4pt。
    var center: CGRect {
        let size = cellSize
        var x = key.cap.midX - size.width / 2
        // 按键区离屏幕边 sidePadding，换算成离屏幕边 4pt。
        let margin = 4 - KeyboardMetrics.sidePadding
        x = min(max(x, margin + size.width), containerWidth - margin - size.width * 2)
        return CGRect(x: x, y: key.cap.midY - size.height / 2, width: size.width, height: size.height)
    }

    func frame(for direction: Direction) -> CGRect {
        let c = center
        switch direction {
        case .left: return c.offsetBy(dx: -c.width, dy: 0)
        case .right: return c.offsetBy(dx: c.width, dy: 0)
        case .up:
            // 第一行往上只有 AI 栏那么高，超出键盘顶会被裁平；顶到离键盘顶 2pt 为止，格子矮一点。
            let up = c.offsetBy(dx: 0, dy: -c.height)
            let top = max(up.minY, 2 - KeyboardMetrics.topRow)
            return CGRect(x: up.minX, y: top, width: up.width, height: up.maxY - top)
        case .down: return c.offsetBy(dx: 0, dy: c.height)
        }
    }

    /// 手指离按下的位置不到 14pt 算在中间（nil，松手取消）；再远就按偏得更多的那个方向算，
    /// 和原生一样轻轻一划就选中，不用划进格子里。那个方向没有选项也是 nil。
    func direction(at point: CGPoint) -> Direction? {
        let start = origin ?? CGPoint(x: key.cap.midX, y: key.cap.midY)
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard hypot(dx, dy) > 14 else { return nil }
        let direction: Direction = abs(dx) >= abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
        return options[direction] == nil ? nil : direction
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
