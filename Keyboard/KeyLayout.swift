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
    /// 九宫格的「选拼音」。
    case pickPinyin
    case layer(KeyboardModel.KeyLayer)
    /// 九宫格数字键盘的「.,:」：点一下是「.」，往左划「,」、往上划「:」。
    case digitPunct
    /// 九宫格数字键盘的「更多」：左列换成运算符，再点是「返回」。
    case digitsMore

    /// 会打出字符的键：按下时显示放大气泡，另一根手指按下时先上屏。
    var typesCharacter: Bool {
        switch self {
        case .letter, .symbol, .nine, .digitPunct: return true
        default: return false
        }
    }

    /// 按住直接往四个方向划就出十字（打拼音时的分词键除外）。
    func flicks(composing: Bool) -> Bool {
        switch self {
        case .nine(let digit): return !(digit == "'" && composing)
        case .digitPunct: return true
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
}

/// 按当前状态算出所有按键的位置，参照 iOS 自带键盘的比例。
enum KeyLayout {
    struct State: Equatable {
        var layer: KeyboardModel.KeyLayer
        var nineKey: Bool
        var chineseMode: Bool
        var needsGlobeKey: Bool
        var composing = false
        var digitsMore = false
    }

    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let digits = "1234567890".map(String.init)

    static func build(_ state: State, size: CGSize) -> KeyLayoutResult {
        if state.layer == .letters && state.nineKey {
            return nineKey(state, size: size)
        }
        if state.layer == .digits {
            return digitPad(state, size: size)
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

        let returnWidth = unit * 2.5
        // 中文的数字和符号页照原生：底栏只有「拼音」、空格、换行，不放表情和中/英。
        if state.layer != .letters && (state.chineseMode || state.nineKey) {
            let back = unit * 2.4
            var x: CGFloat = 0
            add("layer", .layer(.letters), x: x, row: 3, width: back)
            x += back
            if state.needsGlobeKey {
                add("globe", .globe, x: x, row: 3, width: unit * 1.25)
                x += unit * 1.25
            }
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
        let toggle = KeyboardMetrics.toggleKeyWidth + KeyboardMetrics.keyInsetX * 2
        add("chinese", .toggleChinese, x: x, row: 3, width: toggle)
        x += toggle
        add("space", .space, x: x, row: 3, width: size.width - returnWidth - x)
        add("return", .returnKey, x: size.width - returnWidth, row: 3, width: returnWidth)
        return KeyLayoutResult(keys: keys)
    }

    /// 九宫格，照 iOS 26 的五列排法：
    /// 123   ,。?!  ABC   DEF   删除
    /// #@¥   GHI   JKL   MNO   ^^（打拼音时是重输）
    /// ABC   PQRS  TUV   WXYZ  换行
    /// 😀/地球 选拼音 空格（两格）   （换行占两行）
    /// 打拼音时左列上三格换成拼音选择栏。
    private static func nineKey(_ state: State, size: CGSize) -> KeyLayoutResult {
        let slot = KeyboardMetrics.nineRowPitch
        let top = KeyboardMetrics.nineTopOffset
        // 每格 = 键 + 一条缝；按键区本身离屏幕边 sidePadding，两边再各留（边距 − sidePadding − 半条缝）。
        let edge = KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding - KeyboardMetrics.nineKeyInsetX
        let column = (size.width - edge * 2) / 5
        var keys: [KeySpec] = []
        func add(_ id: String, _ kind: KeyKind, col: Int, row: Int, cols: Int = 1, rows: Int = 1) {
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: edge + CGFloat(col) * column, y: top + CGFloat(row) * slot,
                                            width: column * CGFloat(cols), height: slot * CGFloat(rows)))
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
        var pinyinColumn: CGRect?
        if state.composing {
            pinyinColumn = CGRect(x: edge, y: top, width: column, height: slot * 3)
        } else {
            add("layer", .layer(.digits), col: 0, row: 0)
            add("symbols", .layer(.numbers), col: 0, row: 1)
            add("chinese", .toggleChinese, col: 0, row: 2)
        }
        add(state.needsGlobeKey ? "globe" : "emoji", state.needsGlobeKey ? .globe : .emoji, col: 0, row: 3)
        add("pinyin", .pickPinyin, col: 1, row: 3)
        add("space", .space, col: 2, row: 3, cols: 2)
        add("delete", .delete, col: 4, row: 0)
        add("emoticon", .emoticon, col: 4, row: 1)
        add("return", .returnKey, col: 4, row: 2, rows: 2)
        return KeyLayoutResult(keys: keys, pinyinColumn: pinyinColumn)
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
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: edge + CGFloat(col) * column, y: top + CGFloat(row) * slot,
                                            width: column, height: slot * CGFloat(rows)))
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
        if state.digitsMore {
            operatorColumn = CGRect(x: edge, y: top, width: column, height: slot * 3)
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
        return KeyLayoutResult(keys: keys, operatorColumn: operatorColumn)
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
