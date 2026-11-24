import CoreGraphics
import Foundation

/// 盖在按键区上的面板。
enum KeysPanel: Equatable {
    case emoji, kaomoji, quickWords
    /// 长按结果卡打开的分词面板（BB1）。
    case words
}

/// 长按按键弹出的一排备选，手指左右滑动来选，松手上屏。
/// 默认那格正对按键中心、一弹出就选中，其余往两边排（T92，AlternatesRow）。
struct AlternatesPopup: Equatable {
    let key: KeySpec
    /// 从左到右。
    let options: [String]
    let containerWidth: CGFloat
    /// 一开始是默认那格。
    var selected: Int
    /// 整排左边的 x。
    let minX: CGFloat

    /// iPad 全宽键盘（PK8 ①）：每格 56×60，跟着 iPad 的键大一号。
    static var cellWidth: CGFloat { KeyboardMetrics.pad == nil ? 34 : 56 }
    static var height: CGFloat { KeyboardMetrics.pad == nil ? 48 : 60 }

    init(key: KeySpec, row: AlternatesRow, containerWidth: CGFloat) {
        let arranged = row.arranged(centerX: key.cap.midX, cellWidth: Self.cellWidth, containerWidth: containerWidth)
        self.key = key
        self.options = arranged.options
        self.containerWidth = containerWidth
        self.selected = arranged.selected
        self.minX = arranged.minX
    }

    /// 按键正上方一排。
    /// iPad：不出键盘顶（26 键上面有顶栏，9 键上面什么都没有），太靠上时往下压。
    var frame: CGRect {
        let width = Self.cellWidth * CGFloat(options.count)
        var y = key.cap.minY - Self.height - 4
        if KeyboardMetrics.pad != nil {
            y = max(y, 2 - (KeyboardMetrics.padNine ? 0 : KeyboardMetrics.topRow))
        }
        return CGRect(x: minX, y: y, width: width, height: Self.height)
    }

    func index(atX x: CGFloat) -> Int {
        let raw = Int(((x - frame.minX) / Self.cellWidth).rounded(.down))
        return min(max(raw, 0), options.count - 1)
    }
}

/// 长按「中/英」的拼音布局菜单（P11）：宽 168，小标题 + 「九宫格」「全键盘」两项，手指滑到哪项选哪项。
struct LayoutMenuPopup: Equatable {
    /// 菜单里的一项：拼音布局（九宫格 / 全键盘）或拼音显示（上方一行 / 侧边，F12）。
    enum Option: Equatable {
        case layout(KeyboardLayout)
        case display(PinyinDisplay)
    }

    let key: KeySpec
    let containerWidth: CGFloat
    let currentLayout: KeyboardLayout
    let currentDisplay: PinyinDisplay
    /// 手指停在哪一项上；松手时只改这一项，离开菜单为 nil 时什么都不改。
    var hover: Option?

    static let width: CGFloat = 168
    static let titleHeight: CGFloat = 26
    static let rowHeight: CGFloat = 36
    static let padding: CGFloat = 6
    /// 两组之间的细线（上下各留 4）。
    static let dividerHeight: CGFloat = 9
    static let options: [Option] = [.layout(.nineKey), .layout(.qwerty), .display(.row), .display(.side)]
    static var height: CGFloat { padding * 2 + titleHeight * 2 + dividerHeight + rowHeight * CGFloat(options.count) }

    var frame: CGRect {
        // iPad（PK8 ②）：「中/英」在第二排（9 键在最下面一排），上面放不下，菜单挂在按键右边（右边放不下挂左边），
        // 上下以按键为中心、不出按键区，不盖住手指。
        if KeyboardMetrics.pad != nil {
            var x = key.cap.maxX + 8
            if x + Self.width > containerWidth - 4 { x = key.cap.minX - 8 - Self.width }
            let y = min(max(key.cap.midY - Self.height / 2, 0), max(KeyboardMetrics.keysHeight - Self.height, 0))
            return CGRect(x: x, y: y, width: Self.width, height: Self.height)
        }
        let x = min(max(key.cap.minX, 4), max(containerWidth - Self.width - 4, 0))
        // 两组放不下时往上伸到候选栏 / AI 栏那一排（按键区这时整块盖在最上层）。
        return CGRect(x: x, y: max(key.cap.minY - Self.height - 6, -KeyboardMetrics.topRow), width: Self.width, height: Self.height)
    }

    func rowFrame(_ index: Int) -> CGRect {
        let groupOffset = index >= 2 ? Self.dividerHeight + Self.titleHeight : 0
        return CGRect(x: frame.minX + Self.padding,
                      y: frame.minY + Self.padding + Self.titleHeight + CGFloat(index) * Self.rowHeight + groupOffset,
                      width: Self.width - Self.padding * 2, height: Self.rowHeight)
    }

    /// 这一项显示成选中：手指停在同一组的某项上时按手指，否则按现在的设置。
    func isChecked(_ option: Option) -> Bool {
        switch (option, hover) {
        case (.layout(let layout), .layout(let hovered)?): return layout == hovered
        case (.display(let display), .display(let hovered)?): return display == hovered
        case (.layout(let layout), _): return layout == currentLayout
        case (.display(let display), _): return display == currentDisplay
        }
    }

    /// 手指在哪一项上；离菜单太远（横向超出、或回到键上）时不选。
    func option(at point: CGPoint) -> Option? {
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

    /// 每格 = 一个键加一条缝。iPad 全宽 9 键（PK8 ③）键帽 64（比 iPhone 大一点，跟着 iPad 的键高），不跟着键宽。
    var cellSize: CGSize {
        if let pad = KeyboardMetrics.pad { return CGSize(width: 64 + pad.gap, height: 64 + pad.gap) }
        return CGSize(width: key.cap.width + KeyboardMetrics.nineColumnGap, height: KeyboardMetrics.nineRowPitch)
    }

    /// iPad（第 87 条）：上、下那格出了按键区时最矮压到 40，离按键区边留 2。
    static let padMinCell: CGFloat = 40
    static let padEdge: CGFloat = 2

    /// 中间那格：以按下的键为中心；贴边时整个十字往里收，离屏幕边至少 4pt。
    /// iPad 9 键上面没有 AI 栏可以伸，十字留在按键区里（第 87 条，11-24 cvbk「弹出的应该在中间，这样一挪动就是从中间挪动」）：
    /// 中间那格对准按键，上、下哪格出了按键区就压矮那一格（frame(for:)），最矮 40；
    /// 压到 40 还放不下才整个十字往里挪，只有第一排往上会这样（上面只剩 4）。没有选项的那一边不算。
    var center: CGRect {
        let size = cellSize
        var x = key.cap.midX - size.width / 2
        // 按键区离屏幕边 sidePadding，换算成离屏幕边 4pt。
        let margin = 4 - KeyboardMetrics.sidePadding
        x = min(max(x, margin + size.width), containerWidth - margin - size.width * 2)
        var y = key.cap.midY - size.height / 2
        if KeyboardMetrics.pad != nil {
            let top = Self.padEdge
            let bottom = KeyboardMetrics.keysHeight - Self.padEdge
            if options[.up] != nil, y - top < Self.padMinCell { y = top + size.height }
            if options[.down] != nil, bottom - (y + size.height) < Self.padMinCell { y = bottom - size.height * 2 }
            y = min(max(y, top), bottom - size.height)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    func frame(for direction: Direction) -> CGRect {
        let c = center
        switch direction {
        case .left: return c.offsetBy(dx: -c.width, dy: 0)
        case .right: return c.offsetBy(dx: c.width, dy: 0)
        case .up:
            // 第一行往上只有 AI 栏那么高，超出键盘顶会被裁平；顶到离键盘顶 2pt 为止，格子矮一点。
            // iPad 留在按键区里，顶到离按键区顶 2 为止（center 保证不矮过 40）。
            let up = c.offsetBy(dx: 0, dy: -c.height)
            let limit = KeyboardMetrics.pad != nil ? Self.padEdge : 2 - KeyboardMetrics.topRow
            let top = max(up.minY, limit)
            return CGRect(x: up.minX, y: top, width: up.width, height: up.maxY - top)
        case .down:
            let down = c.offsetBy(dx: 0, dy: c.height)
            // iPad 第三排往下：碰到按键区底（离边 2）就压矮这一格，竖屏约 52、键压扁时约 42（第 87 条）。
            guard KeyboardMetrics.pad != nil else { return down }
            let bottom = min(down.maxY, KeyboardMetrics.keysHeight - Self.padEdge)
            return CGRect(x: down.minX, y: down.minY, width: down.width, height: bottom - down.minY)
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

/// 回答卡里按住回车弹出的十字（第 70 条，EA2）：中间是回车（识意），正上方「✨ 润色」，左边「问答」。
/// 两格和普通键一样大（宽同回车那一列、高 46）：上格离回车 7pt，左格离回车 6pt、和回车下半对齐；贴屏幕边时往里收。
/// 选法和九宫格 ABC 十字一样：离按下的地方 14pt 内是中间，再远按偏得多的方向；滑出十字松手是取消（nil）。
struct EnterCrossPopup: Equatable {
    enum Choice: Equatable { case auto, polish, ask }

    let key: KeySpec
    let containerWidth: CGFloat
    /// 润色 / 问答关掉或不能用：那一格不弹。
    let polish: Bool
    let ask: Bool
    var origin: CGPoint
    var selected: Choice? = .auto

    static let cellHeight: CGFloat = 46
    static let upGap: CGFloat = 7
    static let leftGap: CGFloat = 6

    /// 按键区离屏幕边 sidePadding，换算成离屏幕边 4pt。
    private var margin: CGFloat { 4 - KeyboardMetrics.sidePadding }
    private var cellWidth: CGFloat { min(key.cap.width, 120) }

    var upFrame: CGRect {
        var x = key.cap.midX - cellWidth / 2
        x = min(max(x, margin), containerWidth - margin - cellWidth)
        let y = max(key.cap.minY - Self.upGap - Self.cellHeight, 2 - KeyboardMetrics.topRow)
        return CGRect(x: x, y: y, width: cellWidth, height: Self.cellHeight)
    }

    var leftFrame: CGRect {
        let x = max(key.cap.minX - Self.leftGap - cellWidth, margin)
        return CGRect(x: x, y: key.cap.maxY - Self.cellHeight, width: cellWidth, height: Self.cellHeight)
    }

    func choice(at point: CGPoint) -> Choice? {
        var frames = [key.cap]
        if polish { frames.append(upFrame) }
        if ask { frames.append(leftFrame) }
        // 离十字太远（任何一格外 20pt）：松手取消。
        guard frames.contains(where: { $0.insetBy(dx: -20, dy: -20).contains(point) }) else { return nil }
        if polish, upFrame.insetBy(dx: -6, dy: -6).contains(point) { return .polish }
        if ask, leftFrame.insetBy(dx: -6, dy: -6).contains(point) { return .ask }
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if hypot(dx, dy) <= 14 { return .auto }
        if abs(dy) > abs(dx), dy < 0, polish { return .polish }
        if abs(dx) >= abs(dy), dx < 0, ask { return .ask }
        return key.cap.contains(point) ? .auto : nil
    }
}

/// 表情面板的全部 emoji，分类和顺序对齐 iOS 系统键盘（含国旗、键帽、❤️ 这类带 FE0F 的、多人组合）。
/// 数据 Keyboard/Emoji/emoji_panel.tsv 由 scripts/build-emoji-panel.py 从 Unicode emoji-test.txt 生成；
/// 旗帜里不放 🇹🇼（中国大陆上架合规，同系统键盘在中国大陆的做法）。
/// 系统版本太旧显示不出来的新 emoji（会变成方框）按 Unicode emoji 版本藏掉。
enum EmojiCatalog {
    struct Item: Hashable {
        let emoji: String
        /// 肤色变体，留给长按选肤色用；系统显示不出来的已去掉。
        let tones: [Tone]
        /// 两人组合（🤝 💏 👫…）：两人可以分别选肤色。
        var isPair: Bool { tones.contains { $0.code.count == 2 } }
    }

    struct Tone: Hashable {
        let emoji: String
        /// 1–5 浅到深；两人组合两位，第一位是左边那个人（🫱🏻‍🫲🏼 是 "12"）。
        let code: String
    }

    struct Category: Identifiable {
        let id: String
        let symbol: String
        let items: [Item]
        var emoji: [String] { items.map(\.emoji) }
    }

    /// 分类名 → 底栏图标。
    private static let symbols: [String: String] = [
        "笑脸与人物": "face.smiling", "动物与自然": "pawprint", "食物与饮料": "fork.knife", "活动": "soccerball",
        "旅行与地点": "car", "物品": "lightbulb", "符号": "heart", "旗帜": "flag",
    ]

    static let categories: [Category] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "emoji_panel", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, os: ProcessInfo.processInfo.operatingSystemVersion)
    }()

    /// 「# 分类」一行开一个分类；其余每行「emoji<Tab>版本<Tab>肤色变体（emoji/版本/肤色，空格分开）」。
    static func parse(_ text: String, os: OperatingSystemVersion) -> [Category] {
        var result: [Category] = []
        var name: String?
        var items: [Item] = []
        func flush() {
            if let name, !items.isEmpty {
                result.append(Category(id: name, symbol: symbols[name] ?? "circle", items: items))
            }
            items = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# ") {
                flush()
                name = String(line.dropFirst(2))
                continue
            }
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, supported(String(parts[1]), os: os) else { continue }
            let tones: [Tone] = parts.count > 2
                ? parts[2].split(separator: " ").compactMap { tone -> Tone? in
                    let fields = tone.split(separator: "/")
                    guard fields.count == 3, supported(String(fields[1]), os: os) else { return nil }
                    return Tone(emoji: String(fields[0]), code: String(fields[2]))
                }
                : []
            items.append(Item(emoji: String(parts[0]), tones: tones))
        }
        flush()
        return result
    }

    /// Unicode emoji 版本 → iOS 起码要几版才有字形（iOS 16 起步，14.0 及以前的都有）。
    static func supported(_ version: String, os: OperatingSystemVersion) -> Bool {
        let need: (Int, Int)
        switch version {
        case "15.0": need = (16, 4)
        case "15.1": need = (17, 4)
        case "16.0": need = (18, 4)
        case "17.0": need = (26, 4)
        default:
            guard let major = Double(version) else { return false }
            if major <= 14.0 { return true }
            // 比 17.0 还新的：没对过，先不放。
            return false
        }
        return (os.majorVersion, os.minorVersion) >= need
    }

    /// 原型和每个肤色变体 → 那一项（只含这台系统能显示的）：打字候选的 emoji 用它跳过显示不出来的（见 EmojiTable）。
    static let lookup: [String: Item] = {
        var result: [String: Item] = [:]
        for category in categories {
            for item in category.items {
                result[item.emoji] = item
                for tone in item.tones { result[tone.emoji] = item }
            }
        }
        return result
    }()

    private final class BundleToken {}
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

/// 常用颜文字（EP2）：分开心、难过、生气、害羞、无语五组，面板里每组一个小标题，底栏按组跳。
enum Kaomoji {
    struct Mood: Identifiable {
        let id: String
        let items: [String]
    }

    static let groups: [Mood] = [
        Mood(id: "开心", items: [
            "^_^", "^^", "(^_^)", "(≧▽≦)", "(｡•̀ᴗ-)✧", "(๑•̀ㅂ•́)و✧", "(*^▽^*)", "(～￣▽￣)～", "(＾▽＾)",
            "o(*￣▽￣*)o", "(´▽`ʃ♡ƪ)", "(づ｡◕‿‿◕｡)づ", "(｡･ω･｡)", "(・∀・)", "(￣▽￣)~*", "ヾ(≧▽≦*)o", "(ﾉ´ヮ`)ﾉ*: ･ﾟ",
            "♪(^∇^*)", "(ง •_•)ง",
        ]),
        Mood(id: "难过", items: [
            "(；′⌒`)", "(T_T)", "(╥﹏╥)", "QAQ", "(´；ω；`)", "(￣﹏￣；)", "(｡>﹏<｡)", "orz",
        ]),
        Mood(id: "生气", items: [
            "(╯°□°）╯︵ ┻━┻", "┬─┬ノ( º _ ºノ)", "(￣^￣)", "(｀へ´)", "(＃｀Д´)", "(；一_一)",
        ]),
        Mood(id: "害羞", items: [
            "(*/ω＼*)", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)",
        ]),
        Mood(id: "无语", items: [
            "(⊙_⊙)?", "(°ー°〃)", "Σ(っ °Д °;)っ", "¯\\_(ツ)_/¯", "(-_-)zzz",
        ]),
    ]

    static var all: [String] { groups.flatMap(\.items) }

    /// 底栏和小标题上的名字（id 是中文组名）。
    static func title(_ id: String) -> String {
        switch id {
        case "最近": return L("最近", "Recent", "最近")
        case "开心": return L("开心", "Happy", "うれしい")
        case "难过": return L("难过", "Sad", "かなしい")
        case "生气": return L("生气", "Angry", "おこ")
        case "害羞": return L("害羞", "Shy", "てれ")
        case "无语": return L("无语", "Speechless", "あきれ")
        default: return id
        }
    }
}

/// 用过的颜文字（EP2「最近」）：最多 8 个，还没用过就没有这一组。
enum RecentKaomoji {
    private static let key = "keyboard.recentKaomoji"

    static var all: [String] { SharedStorage.defaults.stringArray(forKey: key) ?? [] }

    static func add(_ kaomoji: String) {
        var list = all.filter { $0 != kaomoji }
        list.insert(kaomoji, at: 0)
        SharedStorage.defaults.set(Array(list.prefix(8)), forKey: key)
    }
}

/// 表情面板的分类（EP1）：最近、笑脸、手势、动物、食物、活动、出行、物品、符号、旗帜。
/// 「笑脸与人物」从 👋 起拆成笑脸、手势两类（手势后面接着人物），别的照 emoji_panel.tsv 的分类。
struct EmojiPanelSection: Identifiable {
    let id: String
    let symbol: String
    let emoji: [String]

    var title: String {
        switch id {
        case "最近": return L("最近", "Recent", "最近")
        case "笑脸": return L("笑脸", "Smileys", "スマイリー")
        case "手势": return L("手势", "Gestures", "ジェスチャー")
        case "动物": return L("动物", "Animals", "動物")
        case "食物": return L("食物", "Food", "食べ物")
        case "活动": return L("活动", "Activities", "アクティビティ")
        case "出行": return L("出行", "Travel", "旅行")
        case "物品": return L("物品", "Objects", "もの")
        case "符号": return L("符号", "Symbols", "記号")
        case "旗帜": return L("旗帜", "Flags", "旗")
        default: return id
        }
    }

    static let catalog: [EmojiPanelSection] = {
        let names = ["动物与自然": "动物", "食物与饮料": "食物", "旅行与地点": "出行"]
        var result: [EmojiPanelSection] = []
        for category in EmojiCatalog.categories {
            if category.id == "笑脸与人物", let split = category.emoji.firstIndex(of: "👋") {
                result.append(EmojiPanelSection(id: "笑脸", symbol: category.symbol, emoji: Array(category.emoji[..<split])))
                result.append(EmojiPanelSection(id: "手势", symbol: "hand.raised", emoji: Array(category.emoji[split...])))
            } else {
                let id = category.id == "笑脸与人物" ? "笑脸" : names[category.id] ?? category.id
                result.append(EmojiPanelSection(id: id, symbol: category.symbol, emoji: category.emoji))
            }
        }
        return result
    }()

    /// 有用过的表情时前面加「最近」。
    static var all: [EmojiPanelSection] {
        let recent = RecentEmoji.all
        return (recent.isEmpty ? [] : [EmojiPanelSection(id: "最近", symbol: "clock", emoji: recent)]) + catalog
    }
}
