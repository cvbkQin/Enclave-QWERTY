import CoreGraphics

/// 一个按键做什么。
enum KeyKind: Equatable {
    case letter(String)
    case symbol(String)
    /// 九宫格的数字键（"'" 是分词）。
    case nine(String)
    case shift, delete, space, returnKey, toggleChinese, globe
    /// 九宫格的「^^」：平时打开颜文字，打拼音时是「重输」。
    case emoticon
    case emoji
    /// 九宫格左列的「常用」：打开放到键盘的常用词。
    case quickWords
    case layer(KeyboardModel.KeyLayer)
    /// 九宫格数字键盘的「.,:」：点一下是「.」，往左划「,」、往上划「:」。
    case digitPunct
    /// 九宫格数字键盘的「更多」：左列换成运算符，再点是「返回」。
    case digitsMore
    /// 全键盘空格旁的「，。」键（对齐清单第 80 条）：点一下逗号，往上划句号，长按一排标点（QuickPunct）。
    /// chinese：中文时全角，英文时半角。
    case quickPunct(chinese: Bool)
    /// iPad 全宽键盘（PK1、PK2）：Tab 键、右下角「收起键盘」。
    case tab, dismiss
    /// iPad 全宽键盘的标点、数字键（PK1、PK2）：按了 ⇧ 打 shifted（键帽上的灰色小字），平时打 base。
    case padSymbol(String, shifted: String)

    /// 会打出字符的键：按下时显示放大气泡，另一根手指按下时先上屏。
    var typesCharacter: Bool {
        switch self {
        case .letter, .symbol, .nine, .digitPunct, .quickPunct, .padSymbol: return true
        default: return false
        }
    }

    /// 按住直接往四个方向划就出十字（打拼音时的分词键除外）。「，。」键和九宫格标点键同一种判定，只有往上有字。
    func flicks(composing: Bool) -> Bool {
        switch self {
        case .nine(let digit): return !(digit == "'" && composing)
        case .digitPunct, .quickPunct: return true
        default: return false
        }
    }
}

/// 按键和它占的「格子」。格子之间没有空隙，按键的间隙算在格子里，所以整片区域都能点中最近的键。
struct KeySpec: Identifiable, Equatable {
    let id: String
    let kind: KeyKind
    /// 触摸范围。
    let frame: CGRect
    /// 画出来的格子（第二行两端的键触摸范围比画出来的大）。
    let visual: CGRect
    /// 格子里按键四周留的间隙。
    var insetX = KeyboardMetrics.keyInsetX
    var insetY = KeyboardMetrics.keyInsetY
    /// 往下滑打出的字（iPad 11 寸字母键上的灰色小字，PK1）；nil 不能下滑。
    var flick: String?

    init(id: String, kind: KeyKind, frame: CGRect, visual: CGRect? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.visual = visual ?? frame
    }

    /// 键帽本身的位置。
    var cap: CGRect { visual.insetBy(dx: insetX, dy: insetY) }
}

struct KeyLayoutResult: Equatable {
    var keys: [KeySpec] = []
    /// 九宫格打拼音时左列让给拼音选择栏，这块区域不归触摸层管。
    var pinyinColumn: CGRect?
    /// 九宫格数字键盘点了「更多」：左列上三格换成运算符列表，同样不归触摸层管。
    var operatorColumn: CGRect?
    /// 横屏九宫格（LN1）中间那块：上面 AI 栏、下面联想 / 候选 / 结果卡（LandscapeNineMiddle），不归触摸层管。
    var middle: CGRect?
    /// iPad 全宽 9 键（PK3、PK4）：功能键一列（回答卡开关、润色、问答、钉住的风格、撤销重做）和中间的联想 / 候选，
    /// 都不归触摸层管。
    var padFunctions: CGRect?
    var padMiddle: CGRect?
}

/// 按当前状态算出所有按键的位置，参照 iOS 自带键盘的比例。
enum KeyLayout {
    struct State: Equatable {
        var layer: KeyboardModel.KeyLayer
        var nineKey: Bool
        var chineseMode: Bool
        var needsGlobeKey: Bool
        /// 只用英文：底栏中/英键的位置换成逗号键，宽度不变。
        var englishOnly = false
        var composing = false
        var digitsMore = false
        /// 拼音显示在侧边（F12）：九宫格打字时左列上三格让给拼音列。
        var pinyinSide = false
        /// 横屏（LN1、LN2）：九宫格分左中右，全键盘底排照系统横屏的宽度。
        var landscape = false
        /// 全键盘字母页空格旁的「，。」键放哪边，中文、英文的全键盘都有（中文布局选九宫格时，英文的全键盘也有）；nil 不放。
        /// 只用英文时底栏已经有逗号键，不放。
        var quickPunct: QuickPunctSide?
        /// iPad 全宽键盘（PK1、PK2、PK9）：26 键和数字符号页按 iPad 原生排（KeyLayout+Pad）。
        /// 9 键开着回答卡时是压扁的那份（PK15）。
        var pad: PadMetrics?
        /// iPad 全宽 9 键：九键在左边（PK4），默认右边（PK3）。
        var nineOnLeft = false
        /// iPad 浮动键盘（PK13、PK14）：9 键数字页左列一直是运算符号，最下面一行 返回、☺、0、空格（浮动时 🌐 在系统下面那一排，字母页左下还是 ☺）。
        var floating = false
        /// iPad 11 寸 26 键字母上的灰色小字、往下滑打出来（设置「字母上的数字和符号」，默认开）。
        var padLetterHints = true
    }

    /// 横屏九宫格（LN1）：按 iPhone 16 Pro 横屏按键外沿 714 宽排，别的宽度按比例缩放。
    /// 左列 68 ｜ 8 ｜ 中间 340 ｜ 8 ｜ 右边四列各 68、列距 6。九宫格的五列里第 0 列放左边，第 1–4 列放右边。
    enum LandscapeNine {
        static let designWidth: CGFloat = 714
        /// 键帽离按键区边上多远：和竖屏九宫格一样，离屏幕边 7。
        static var capEdge: CGFloat { KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding }

        static func scale(_ width: CGFloat) -> CGFloat { max(width - capEdge * 2, 1) / designWidth }

        /// 第 col 列起、占 cols 列的键帽左边和宽度。
        static func cap(col: Int, cols: Int = 1, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
            let s = scale(width)
            if col == 0 { return (capEdge, 68 * s) }
            let x = 424 + 74 * CGFloat(col - 1)
            return (capEdge + x * s, (68 * CGFloat(cols) + 6 * CGFloat(cols - 1)) * s)
        }

        /// 中间那块（键帽那么高：四行键加三条缝）。
        static func middle(width: CGFloat) -> CGRect {
            let s = scale(width)
            let inset = KeyboardMetrics.nineKeyInsetY
            return CGRect(x: capEdge + 76 * s, y: KeyboardMetrics.nineTopOffset + inset,
                          width: 340 * s, height: KeyboardMetrics.nineRowPitch * 4 - inset * 2)
        }
    }

    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    static let digits = "1234567890".map(String.init)

    private static var lastBuild: (state: State, size: CGSize, result: KeyLayoutResult)?

    /// 状态和尺寸都没变时直接用上次排好的：打拼音时每个键都会让按键区重算一遍。
    static func cachedBuild(_ state: State, size: CGSize) -> KeyLayoutResult {
        if let cached = lastBuild, cached.state == state, cached.size == size { return cached.result }
        let result = build(state, size: size)
        lastBuild = (state, size, result)
        return result
    }

    static func build(_ state: State, size: CGSize) -> KeyLayoutResult {
        if let pad = state.pad, state.nineKey, state.layer == .letters || state.layer == .digits {
            return padNine(state, size: size, pad: pad)
        }
        if state.layer == .letters && state.nineKey {
            return nineKey(state, size: size)
        }
        if state.layer == .digits {
            return digitPad(state, size: size)
        }
        if let pad = state.pad {
            return padBoard(state, size: size, pad: pad)
        }
        let unit = size.width / 10
        let slot = KeyboardMetrics.slotHeight
        // 系统键盘的 Shift 和删除键比 1.5 格窄，和字母之间空出一段。
        let wideKey = KeyboardMetrics.shiftKeyWidth + KeyboardMetrics.keyInsetX * 2
        var keys: [KeySpec] = []

        func add(_ id: String, _ kind: KeyKind, x: CGFloat, row: Int, width: CGFloat, visualX: CGFloat? = nil, visualWidth: CGFloat? = nil) {
            let y = CGFloat(row) * slot
            let frame = CGRect(x: x, y: y, width: width, height: slot)
            let visual = CGRect(x: visualX ?? x, y: y, width: visualWidth ?? width, height: slot)
            keys.append(KeySpec(id: id, kind: kind, frame: frame, visual: visual))
        }

        switch state.layer {
        case .letters:
            for (i, l) in letterRows[0].enumerated() { add(l, .letter(l), x: CGFloat(i) * unit, row: 0, width: unit) }
            // 第二行两边各缩进半格，缩进的地方也算最边上的键。
            for (i, l) in letterRows[1].enumerated() {
                let first = i == 0, last = i == letterRows[1].count - 1
                let x = first ? 0 : unit / 2 + CGFloat(i) * unit
                let width = unit + (first || last ? unit / 2 : 0)
                add(l, .letter(l), x: x, row: 1, width: width, visualX: unit / 2 + CGFloat(i) * unit, visualWidth: unit)
            }
            add("shift", .shift, x: 0, row: 2, width: unit * 1.5, visualWidth: wideKey)
            for (i, l) in letterRows[2].enumerated() { add(l, .letter(l), x: unit * 1.5 + CGFloat(i) * unit, row: 2, width: unit) }
            add("delete", .delete, x: unit * 8.5, row: 2, width: unit * 1.5,
                visualX: size.width - wideKey, visualWidth: wideKey)
        case .numbers, .symbols, .digits:
            let rows = state.layer == .numbers ? numberSymbols(chinese: state.chineseMode) : moreSymbols(chinese: state.chineseMode)
            for row in 0..<2 {
                for (i, s) in rows[row].enumerated() {
                    add("s\(row)-\(i)", .symbol(s), x: CGFloat(i) * unit, row: row, width: unit)
                }
            }
            add("layer2", .layer(state.layer == .numbers ? .symbols : .numbers), x: 0, row: 2, width: unit * 1.5,
                visualWidth: wideKey)
            let width = unit * 7 / CGFloat(rows[2].count)
            for (i, s) in rows[2].enumerated() {
                add("s2-\(i)", .symbol(s), x: unit * 1.5 + CGFloat(i) * width, row: 2, width: width)
            }
            add("delete", .delete, x: unit * 8.5, row: 2, width: unit * 1.5,
                visualX: size.width - wideKey, visualWidth: wideKey)
        }

        // 横屏（LN2）照系统：123、表情、中/英各 1.25 格，回车 2 格，空格占剩下的。
        let returnWidth = unit * (state.landscape ? 2 : 2.5)
        let toggle = state.landscape ? unit * 1.25 : KeyboardMetrics.toggleKeyWidth + KeyboardMetrics.keyInsetX * 2
        // 中文的数字和符号页：底栏是「拼音」、中/英、空格、换行，不放表情。
        // 留着中/英，才能从中文符号直接切到英文符号。
        if state.layer != .letters && (state.chineseMode || state.nineKey) {
            let back = unit * 2.4
            var x: CGFloat = 0
            add("layer", .layer(.letters), x: x, row: 3, width: back)
            x += back
            if state.needsGlobeKey {
                add("globe", .globe, x: x, row: 3, width: unit * 1.25)
                x += unit * 1.25
            }
            add("chinese", .toggleChinese, x: x, row: 3, width: toggle)
            x += toggle
            add("space", .space, x: x, row: 3, width: size.width - returnWidth - x)
            add("return", .returnKey, x: size.width - returnWidth, row: 3, width: returnWidth)
            return KeyLayoutResult(keys: keys)
        }

        // 底栏：123、（地球）、表情、中/英、空格、换行。
        let side = unit * 1.25
        var x: CGFloat = 0
        add("layer", .layer(state.layer == .letters ? .numbers : .letters), x: x, row: 3, width: side)
        x += side
        if state.needsGlobeKey {
            add("globe", .globe, x: x, row: 3, width: side)
            x += side
        } else {
            // 有地球键时空格已经不宽了，表情从地球键旁的系统按钮或九宫格的 ^^ 进。
            add("emoji", .emoji, x: x, row: 3, width: side)
            x += side
        }
        add(state.englishOnly ? "comma" : "chinese", state.englishOnly ? .symbol(",") : .toggleChinese, x: x, row: 3, width: toggle)
        x += toggle
        // 「，。」键（PU4、PU3）：宽一格、和字母键一样，只从空格里让出来，123、表情、中/英、回车的位置和宽度都不动。
        // 放左边时夹在中/英和空格中间，放右边时夹在空格和回车中间。
        let punct = state.layer == .letters && !state.englishOnly ? state.quickPunct : nil
        let punctKind = KeyKind.quickPunct(chinese: state.chineseMode)
        if punct == .left {
            add("quickPunct", punctKind, x: x, row: 3, width: unit)
            x += unit
        }
        let spaceEnd = size.width - returnWidth - (punct == .right ? unit : 0)
        add("space", .space, x: x, row: 3, width: spaceEnd - x)
        if punct == .right {
            add("quickPunct", punctKind, x: spaceEnd, row: 3, width: unit)
        }
        add("return", .returnKey, x: size.width - returnWidth, row: 3, width: returnWidth)
        return KeyLayoutResult(keys: keys)
    }

    /// 九宫格，五列：
    /// 123   ,。?!  ABC   DEF   删除
    /// #@¥   GHI   JKL   MNO   ^^（打拼音时是重输）
    /// 常用  PQRS  TUV   WXYZ  换行
    /// 😀/地球 中/英 空格（两格）   （换行占两行）
    /// 中/英放在底排第二格，和全键盘的位置大体一致。
    private static func nineKey(_ state: State, size: CGSize) -> KeyLayoutResult {
        let slot = KeyboardMetrics.nineRowPitch
        let top = KeyboardMetrics.nineTopOffset
        // 每格 = 键 + 一条缝；按键区本身离屏幕边 sidePadding，两边再各留（边距 − sidePadding − 半条缝）。
        let edge = KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding - KeyboardMetrics.nineKeyInsetX
        let column = (size.width - edge * 2) / 5
        var keys: [KeySpec] = []
        func add(_ id: String, _ kind: KeyKind, col: Int, row: Int, cols: Int = 1, rows: Int = 1) {
            let (x, width) = columnSpan(state, col: col, cols: cols, edge: edge, column: column, width: size.width)
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: x, y: top + CGFloat(row) * slot,
                                            width: width, height: slot * CGFloat(rows)))
            key.insetX = KeyboardMetrics.nineKeyInsetX
            key.insetY = KeyboardMetrics.nineKeyInsetY
            keys.append(key)
        }
        let digits = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        for row in 0..<3 {
            for col in 0..<3 {
                let digit = digits[row][col]
                add("n\(digit)", .nine(digit == "1" ? "'" : digit), col: col + 1, row: row)
            }
        }
        // 拼音在上方一行时左列照平时留着（PY1）；在侧边（F12）时打字中左列上三格换成拼音列。
        var pinyinColumn: CGRect?
        if state.composing && state.pinyinSide {
            let (x, width) = columnSpan(state, col: 0, cols: 1, edge: edge, column: column, width: size.width)
            pinyinColumn = CGRect(x: x, y: top, width: width, height: slot * 3)
        } else {
            add("layer", .layer(.digits), col: 0, row: 0)
            add("symbols", .layer(.numbers), col: 0, row: 1)
            add("quickWords", .quickWords, col: 0, row: 2)
        }
        add(state.needsGlobeKey ? "globe" : "emoji", state.needsGlobeKey ? .globe : .emoji, col: 0, row: 3)
        add("chinese", .toggleChinese, col: 1, row: 3)
        add("space", .space, col: 2, row: 3, cols: 2)
        add("delete", .delete, col: 4, row: 0)
        add("emoticon", .emoticon, col: 4, row: 1)
        add("return", .returnKey, col: 4, row: 2, rows: 2)
        return KeyLayoutResult(keys: keys, pinyinColumn: pinyinColumn,
                               middle: state.landscape ? LandscapeNine.middle(width: size.width) : nil)
    }

    /// 九宫格第 col 列起、占 cols 列的触摸范围（左边、宽）。竖屏五列等宽；横屏照 LandscapeNine 分左右，
    /// 触摸范围是键帽左右各加半条缝。
    private static func columnSpan(_ state: State, col: Int, cols: Int, edge: CGFloat, column: CGFloat, width: CGFloat) -> (CGFloat, CGFloat) {
        guard state.landscape else { return (edge + CGFloat(col) * column, column * CGFloat(cols)) }
        let cap = LandscapeNine.cap(col: col, cols: cols, width: width)
        let inset = KeyboardMetrics.nineKeyInsetX
        return (cap.x - inset, cap.width + inset * 2)
    }

    /// 九宫格数字键盘，照 iOS 26：
    /// 拼音  1  2  3  删除
    /// #@¥  4  5  6  更多
    /// 中/英 7  8  9  换行
    /// 😀   .,: 0 空格 （换行占两行）
    /// 点「更多」后左列上三格换成可上下滑的运算符。
    private static func digitPad(_ state: State, size: CGSize) -> KeyLayoutResult {
        let slot = KeyboardMetrics.nineRowPitch
        let top = KeyboardMetrics.nineTopOffset
        let edge = KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding - KeyboardMetrics.nineKeyInsetX
        let column = (size.width - edge * 2) / 5
        var keys: [KeySpec] = []
        func add(_ id: String, _ kind: KeyKind, col: Int, row: Int, rows: Int = 1) {
            let (x, width) = columnSpan(state, col: col, cols: 1, edge: edge, column: column, width: size.width)
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: x, y: top + CGFloat(row) * slot,
                                            width: width, height: slot * CGFloat(rows)))
            key.insetX = KeyboardMetrics.nineKeyInsetX
            key.insetY = KeyboardMetrics.nineKeyInsetY
            keys.append(key)
        }
        for row in 0..<3 {
            for col in 0..<3 {
                let digit = String(row * 3 + col + 1)
                add("d\(digit)", .symbol(digit), col: col + 1, row: row)
            }
        }
        var operatorColumn: CGRect?
        if state.floating {
            let (x, width) = columnSpan(state, col: 0, cols: 1, edge: edge, column: column, width: size.width)
            add("layer", .layer(.letters), col: 0, row: 3)
            add("emoji", .emoji, col: 1, row: 3)
            add("d0", .symbol("0"), col: 2, row: 3)
            add("space", .space, col: 3, row: 3)
            add("delete", .delete, col: 4, row: 0)
            add("dot", .digitPunct, col: 4, row: 1)
            add("return", .returnKey, col: 4, row: 2, rows: 2)
            return KeyLayoutResult(keys: keys, operatorColumn: CGRect(x: x, y: top, width: width, height: slot * 3))
        }
        if state.digitsMore {
            let (x, width) = columnSpan(state, col: 0, cols: 1, edge: edge, column: column, width: size.width)
            operatorColumn = CGRect(x: x, y: top, width: width, height: slot * 3)
        } else {
            add("layer", .layer(.letters), col: 0, row: 0)
            add("symbols", .layer(.numbers), col: 0, row: 1)
            add("chinese", .toggleChinese, col: 0, row: 2)
        }
        add(state.needsGlobeKey ? "globe" : "emoji", state.needsGlobeKey ? .globe : .emoji, col: 0, row: 3)
        add("dot", .digitPunct, col: 1, row: 3)
        add("d0", .symbol("0"), col: 2, row: 3)
        add("space", .space, col: 3, row: 3)
        add("delete", .delete, col: 4, row: 0)
        add("more", .digitsMore, col: 4, row: 1)
        add("return", .returnKey, col: 4, row: 2, rows: 2)
        return KeyLayoutResult(keys: keys, operatorColumn: operatorColumn,
                               middle: state.landscape ? LandscapeNine.middle(width: size.width) : nil)
    }

    /// 数字键盘「更多」里的运算符。
    static let operators = ["+", "−", "×", "÷", "=", "%"]

    static func numberSymbols(chinese: Bool) -> [[String]] {
        chinese
            ? [digits, ["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"], ["。", "，", "、", "？", "！", "."]]
            : [digits, ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
    }

    /// 符号页（九宫格的 #@¥）。中文时第三行放九宫格长按里拿掉的那些标点。
    static func moreSymbols(chinese: Bool) -> [[String]] {
        chinese
            ? [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
               ["_", "\\", "|", "～", "<", ">", "€", "£", "•", "…"],
               ["、", "：", "；", "·", "《", "》", "“", "”"]]
            : [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
               ["_", "\\", "|", "~", "<", ">", "€", "£", "•", "…"],
               ["·", "《", "》", "‘", "’"]]
    }

    /// 九宫格长按的十字：标点键左「，」上「。」右「？」下「！」；字母键 DEF 是左 D 上 E 右 F，四字母键第四个在下。
    static func cross(for kind: KeyKind, chinese: Bool) -> [CrossPopup.Direction: String]? {
        if kind == .digitPunct { return [.left: ",", .up: ":"] }
        // 「，。」键往上划出句号（长按是一排，见 alternates）。
        if case .quickPunct(let chinese) = kind { return [.up: QuickPunct.up(chinese: chinese)] }
        guard case .nine(let digit) = kind else { return nil }
        let options: [String]
        if digit == "'" {
            options = chinese ? ["，", "。", "？", "！"] : [",", ".", "?", "!"]
        } else {
            guard let letters = nineKeyLetters[digit] else { return nil }
            options = letters.map(String.init)
        }
        return Dictionary(uniqueKeysWithValues: zip(CrossPopup.Direction.allCases, options))
    }

    /// 全键盘长按弹出的备选：第一行是数字，元音带声调和变音。
    static func alternates(for kind: KeyKind, chinese: Bool) -> [String]? {
        switch kind {
        case .letter(let letter):
            var options: [String] = []
            if let index = letterRows[0].firstIndex(of: letter) { options.append(digits[index]) }
            options += accents[letter] ?? []
            return options.isEmpty ? nil : [letter] + options
        case .symbol(","):
            // 只用英文时底栏的逗号键：长按出常用英文标点。
            return [",", "'", "?", "!"]
        case .quickPunct(let chinese):
            return QuickPunct.row(chinese: chinese)
        default:
            return nil
        }
    }

    private static let accents: [String: [String]] = [
        "a": ["ā", "á", "ǎ", "à"], "e": ["ē", "é", "ě", "è", "ê"], "i": ["ī", "í", "ǐ", "ì"],
        "o": ["ō", "ó", "ǒ", "ò"], "u": ["ū", "ú", "ǔ", "ù", "ü"], "v": ["ü", "ǖ", "ǘ", "ǚ", "ǜ"],
        "n": ["ñ"], "c": ["ç"], "s": ["ß"],
    ]

    static let nineKeyLetters: [String: String] = [
        "'": "分词", "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
        "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ",
    ]
}
