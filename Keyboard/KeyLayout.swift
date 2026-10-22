import CoreGraphics

/// 一个按键做什么。
enum KeyKind: Equatable {
    case letter(String)
    case symbol(String)
    /// 九宫格的数字键（"'" 是分词）。
    case nine(String)
    case shift, delete, space, returnKey, toggleChinese, globe, clearComposition
    case layer(KeyboardModel.KeyLayer)

    /// 会打出字符的键：按下时显示放大气泡，另一根手指按下时先上屏。
    var typesCharacter: Bool {
        switch self {
        case .letter, .symbol, .nine: return true
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
}

/// 按当前状态算出所有按键的位置，参照 iOS 自带键盘的比例。
enum KeyLayout {
    struct State: Equatable {
        var layer: KeyboardModel.KeyLayer
        var nineKey: Bool
        var chineseMode: Bool
        var needsGlobeKey: Bool
    }

    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let digits = "1234567890".map(String.init)

    static func build(_ state: State, size: CGSize) -> KeyLayoutResult {
        if state.layer == .letters && state.nineKey {
            return nineKey(state, size: size)
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
        case .numbers, .symbols:
            let rows = state.layer == .numbers ? numberSymbols(chinese: state.chineseMode) : moreSymbols
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

        // 底栏：123、（地球）、中/英、空格、换行。
        let side = unit * 1.25
        var x: CGFloat = 0
        add("layer", .layer(state.layer == .letters ? .numbers : .letters), x: x, row: 3, width: side)
        x += side
        if state.needsGlobeKey {
            add("globe", .globe, x: x, row: 3, width: side)
            x += side
        }
        add("chinese", .toggleChinese, x: x, row: 3, width: side)
        x += side
        let returnWidth = unit * 2.5
        add("space", .space, x: x, row: 3, width: size.width - returnWidth - x)
        add("return", .returnKey, x: size.width - returnWidth, row: 3, width: returnWidth)
        return KeyLayoutResult(keys: keys)
    }

    /// 九宫格，照 iOS 26 的五列排法：
    /// 123   ，。?!  ABC   DEF   删除
    /// #@¥   GHI   JKL   MNO   重输
    /// 英文   PQRS  TUV   WXYZ  换行
    /// 地球/，  。    空格（两格）   （换行占两行）
    private static func nineKey(_ state: State, size: CGSize) -> KeyLayoutResult {
        let slot = KeyboardMetrics.slotHeight
        let column = size.width / 5
        var keys: [KeySpec] = []
        func add(_ id: String, _ kind: KeyKind, col: Int, row: Int, cols: Int = 1, rows: Int = 1) {
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: CGFloat(col) * column, y: CGFloat(row) * slot,
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
        add("layer", .layer(.numbers), col: 0, row: 0)
        add("symbols", .layer(.symbols), col: 0, row: 1)
        add("chinese", .toggleChinese, col: 0, row: 2)
        if state.needsGlobeKey {
            add("globe", .globe, col: 0, row: 3)
        } else {
            add("comma", .symbol("，"), col: 0, row: 3)
        }
        add("period", .symbol("。"), col: 1, row: 3)
        add("space", .space, col: 2, row: 3, cols: 2)
        add("delete", .delete, col: 4, row: 0)
        add("clear", .clearComposition, col: 4, row: 1)
        add("return", .returnKey, col: 4, row: 2, rows: 2)
        return KeyLayoutResult(keys: keys)
    }

    static func numberSymbols(chinese: Bool) -> [[String]] {
        chinese
            ? [digits, ["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"], ["。", "，", "、", "？", "！", "."]]
            : [digits, ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
    }

    static let moreSymbols: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "•", "…"],
        ["·", "《", "》", "‘", "’"],
    ]

    static let nineKeyLetters: [String: String] = [
        "'": "分词", "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
        "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ",
    ]
}
