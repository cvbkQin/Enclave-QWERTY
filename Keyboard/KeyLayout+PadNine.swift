import CoreGraphics

/// iPad 全宽 9 键（PK3 九键在右、PK4 九键在左，11-22 定稿，照 iPhone 横屏九宫格的思路；11-23 PK17–PK19 改底排、中间那块）：
///
///  功能键 │ 联想 / 候选（3 排高）      │ 123   ，。?!  ABC   DEF   ⌫
///  一列   │                           │ #@¥   GHI   JKL   MNO   ^^
///         │                           │ 常用  PQRS  TUV   WXYZ  发送
///  🌐 ⌨↓ ， 。 ？ ！（横屏多 、：） ⇆    │ ☺     中/英  空格（两格）    （发送占两排）
///
/// 九键五列靠一边（竖屏占一半宽，横屏 46%），另一边上面三排高是功能键一列和中间那块（都不归触摸层管，
/// 见 PadNineFunctions、PadNineMiddle），最下面一排横跨这两块：🌐 ⌨↓ 在外侧，⇆（九键换边）挨着九键。
/// 九键在左时整个镜像：功能键一列在最右，最下面一排 ⇆ 在最左、🌐 在最右，标点顺序不变。
/// 键高竖屏 56、横屏 62（11-23 加高，和 9 键模式下的英文一样高，PK19），键距照 26 键，最下面一排矮 15%（PadMetrics.nine）。
/// 左列 123、#@¥、常用剪贴板只换中间那块（PK17、PK18）：#@¥ 是符号，常用剪贴板是两个标签；
/// 123 时九键 3×3 换成 1–9，最下面一行 ☺ .,: 0 空格，左列、右列不动，中间那块是运算符号。
extension KeyLayout {
    /// 九键那块占按键区多宽：竖屏 820 里 412，横屏 1180 里 540。
    static func padNineWidth(_ width: CGFloat, pad: PadMetrics) -> CGFloat {
        (width * (pad.landscape ? 0.46 : 0.5)).rounded()
    }

    /// 功能键一列（含两边半条缝）：润色键那么宽，竖屏 86、横屏 94（PK3 ①）。
    static func padFunctionWidth(_ pad: PadMetrics) -> CGFloat {
        (pad.landscape ? 94 : 86) + pad.gap
    }

    static func padNine(_ state: State, size: CGSize, pad: PadMetrics) -> KeyLayoutResult {
        let gap = pad.gap
        let pitch = pad.keyHeight + gap
        let nineWidth = padNineWidth(size.width, pad: pad)
        let column = nineWidth / 5
        let nineX = state.nineOnLeft ? 0 : size.width - nineWidth
        let areaX = state.nineOnLeft ? nineWidth : 0
        let areaWidth = size.width - nineWidth

        /// 第 row 排格子（键帽 + 一条缝）的上边和高。
        func rowSpan(_ row: Int, rows: Int = 1) -> (y: CGFloat, height: CGFloat) {
            let y = pad.top - gap / 2 + CGFloat(row) * pitch
            let last = row + rows - 1
            let height = CGFloat(rows - 1) * pitch + (last == 3 ? pad.bottomKeyHeight : pad.keyHeight) + gap
            return (y, height)
        }

        var keys: [KeySpec] = []
        func add(_ id: String, _ kind: KeyKind, x: CGFloat, width: CGFloat, row: Int, rows: Int = 1) {
            let span = rowSpan(row, rows: rows)
            // 触摸范围：第一排往上、最后一排往下一直到按键区边上（和 26 键一样）。
            let touchTop = row == 0 ? 0 : span.y
            let touchBottom = row + rows - 1 == 3 ? max(size.height, span.y + span.height) : span.y + span.height
            var key = KeySpec(id: id, kind: kind,
                              frame: CGRect(x: x, y: touchTop, width: width, height: touchBottom - touchTop),
                              visual: CGRect(x: x, y: span.y, width: width, height: span.height))
            key.insetX = gap / 2
            key.insetY = gap / 2
            keys.append(key)
        }
        func nine(_ id: String, _ kind: KeyKind, col: Int, row: Int, cols: Int = 1, rows: Int = 1) {
            add(id, kind, x: nineX + CGFloat(col) * column, width: column * CGFloat(cols), row: row, rows: rows)
        }
        func cellRect(col: Int, rows: Int) -> CGRect {
            let span = rowSpan(0, rows: rows)
            return CGRect(x: nineX + CGFloat(col) * column, y: span.y, width: column, height: span.height)
        }

        var pinyinColumn: CGRect?
        /// 左列三颗：点了只换中间那块（PK17），不换页、不开面板。
        func middleKeys() {
            nine("layer", .padMiddle(.digits), col: 0, row: 0)
            nine("symbols", .padMiddle(.symbols), col: 0, row: 1)
            nine("quickWords", .padMiddle(.quick), col: 0, row: 2)
        }
        if state.layer == .digits {
            // 123（PK17 第三张、PK18 中间）：中间 3×3 换成 1–9，最下面一行 .（十字滑出 , 和 :）、0（在 8 正下面）、空格；
            // 左列、右列不动，运算符号在中间那块。
            for row in 0..<3 {
                for col in 0..<3 {
                    let digit = String(row * 3 + col + 1)
                    nine("d\(digit)", .symbol(digit), col: col + 1, row: row)
                }
            }
            middleKeys()
            nine("emoji", .emoji, col: 0, row: 3)
            nine("dot", .digitPunct, col: 1, row: 3)
            nine("d0", .symbol("0"), col: 2, row: 3)
            nine("space", .space, col: 3, row: 3)
            nine("delete", .delete, col: 4, row: 0)
            nine("emoticon", .emoticon, col: 4, row: 1)
            nine("return", .returnKey, col: 4, row: 2, rows: 2)
        } else {
            let digits = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
            for row in 0..<3 {
                for col in 0..<3 {
                    let digit = digits[row][col]
                    nine("n\(digit)", .nine(digit == "1" ? "'" : digit), col: col + 1, row: row)
                }
            }
            // 拼音在侧边（F12）时打字中左列上三格换成拼音列；在上方一行时拼音在中间那块第一排（PadNineMiddle）。
            if state.composing && state.pinyinSide {
                pinyinColumn = cellRect(col: 0, rows: 3)
            } else {
                middleKeys()
            }
            // 🌐 在另一边最下面一排，这里照 PK3 放表情。
            nine("emoji", .emoji, col: 0, row: 3)
            nine("chinese", .toggleChinese, col: 1, row: 3)
            nine("space", .space, col: 2, row: 3, cols: 2)
            nine("delete", .delete, col: 4, row: 0)
            nine("emoticon", .emoticon, col: 4, row: 1)
            nine("return", .returnKey, col: 4, row: 2, rows: 2)
        }

        // 另一边最下面一排（PK17，11-23 cvbk「收起键盘快捷键挪到切换键盘按钮边上去」）：🌐 ⌨↓ ， 。 ？ ！（横屏多 、 ：） ⇆，等宽。
        // 🌐 ⌨↓ 一直在外侧，⇆ 一直挨着九键：九键在左时整排反过来（⇆ 标点 ⌨↓ 🌐），标点顺序不变。
        let chinese = state.chineseMode
        let marks = chinese ? ["，", "。", "？", "！", "、", "："] : [",", ".", "?", "!", "'", ":"]
        let shown = pad.landscape ? marks : Array(marks.prefix(4))
        let markKeys = shown.enumerated().map { ("p-mark\($0.offset)", KeyKind.symbol($0.element)) }
        let outer: [(String, KeyKind)] = [("globe", .globe), ("dismiss", .dismiss)]
        let swap: (String, KeyKind) = ("swapSide", .swapNineSide)
        let bottom: [(String, KeyKind)] = state.nineOnLeft ? [swap] + markKeys + Array(outer.reversed()) : outer + markKeys + [swap]
        let cell = areaWidth / CGFloat(bottom.count)
        for (index, item) in bottom.enumerated() {
            add(item.0, item.1, x: areaX + CGFloat(index) * cell, width: cell, row: 3)
        }

        // 上面三排高：功能键一列靠屏幕边，中间那块夹在它和九键之间。两块都按键帽算（离格子边半条缝）。
        let upper = rowSpan(0, rows: 3)
        let functionWidth = padFunctionWidth(pad)
        let functionX = state.nineOnLeft ? size.width - functionWidth : 0
        let middleX = state.nineOnLeft ? areaX : functionWidth
        let functions = CGRect(x: functionX, y: upper.y, width: functionWidth, height: upper.height).insetBy(dx: gap / 2, dy: gap / 2)
        let middle = CGRect(x: middleX, y: upper.y, width: areaWidth - functionWidth, height: upper.height).insetBy(dx: gap / 2, dy: gap / 2)

        var result = KeyLayoutResult(keys: keys, pinyinColumn: pinyinColumn)
        result.padFunctions = functions
        result.padMiddle = middle
        result.padUpper = CGRect(x: areaX, y: 0, width: areaWidth, height: upper.y + upper.height)
        return result
    }
}
