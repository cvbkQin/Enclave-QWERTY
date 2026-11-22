import CoreGraphics

/// iPad 全宽 9 键（PK3 九键在右、PK4 九键在左，11-22 定稿，照 iPhone 横屏九宫格的思路）：
///
///  功能键 │ 联想 / 候选（3 排高）      │ 123   ，。?!  ABC   DEF   ⌫
///  一列   │                           │ #@¥   GHI   JKL   MNO   ^^
///         │                           │ 常用  PQRS  TUV   WXYZ  发送
///  🌐 ， 。 ？ ！（横屏多 、：） ⌨↓      │ ☺     中/英  空格（两格）    （发送占两排）
///
/// 九键五列靠一边（竖屏占一半宽，横屏 46%），另一边上面三排高是功能键一列和中间那块（都不归触摸层管，
/// 见 PadNineFunctions、PadNineMiddle），最下面一排常用标点横跨这两块。九键在左时整个镜像：功能键一列在最右，
/// 最下面一排 🌐 在最右、⌨↓ 挨着九键，标点顺序不变。键高、键距、最下面一排矮 15% 都照 26 键（PadMetrics）。
/// 9 键数字（PK9 右）：九键那块换成数字小键盘，左列运算符号（上下滑），1–9、0、空格，右列 ⌫ .,: 发送，左下「返回」。
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
        var operatorColumn: CGRect?
        if state.layer == .digits {
            for row in 0..<3 {
                for col in 0..<3 {
                    let digit = String(row * 3 + col + 1)
                    nine("d\(digit)", .symbol(digit), col: col + 1, row: row)
                }
            }
            // 运算符号一直在左列（iPhone 要点「更多」才出来），上下滑看全。
            operatorColumn = cellRect(col: 0, rows: 3)
            nine("layer", .layer(.letters), col: 0, row: 3)
            nine("d0", .symbol("0"), col: 1, row: 3, cols: 2)
            nine("space", .space, col: 3, row: 3)
            nine("delete", .delete, col: 4, row: 0)
            nine("dot", .digitPunct, col: 4, row: 1)
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
                nine("layer", .layer(.digits), col: 0, row: 0)
                nine("symbols", .layer(.numbers), col: 0, row: 1)
                nine("quickWords", .quickWords, col: 0, row: 2)
            }
            // 🌐 在另一边最下面一排，这里照 PK3 放表情。
            nine("emoji", .emoji, col: 0, row: 3)
            nine("chinese", .toggleChinese, col: 1, row: 3)
            nine("space", .space, col: 2, row: 3, cols: 2)
            nine("delete", .delete, col: 4, row: 0)
            nine("emoticon", .emoticon, col: 4, row: 1)
            nine("return", .returnKey, col: 4, row: 2, rows: 2)
        }

        // 另一边最下面一排：🌐 ， 。 ？ ！（横屏多 、 ：） ⌨↓，等宽。九键在左时 🌐 在最右、⌨↓ 挨着九键。
        let chinese = state.chineseMode
        let marks = chinese ? ["，", "。", "？", "！", "、", "："] : [",", ".", "?", "!", "'", ":"]
        let shown = pad.landscape ? marks : Array(marks.prefix(4))
        var bottom: [(String, KeyKind)] = [("globe", .globe)]
        bottom += shown.enumerated().map { ("p-mark\($0.offset)", KeyKind.symbol($0.element)) }
        bottom.append(("dismiss", .dismiss))
        if state.nineOnLeft, bottom.count > 2 {
            let marksOnly = Array(bottom[1..<(bottom.count - 1)])
            bottom = [bottom[bottom.count - 1]] + marksOnly + [bottom[0]]
        }
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

        var result = KeyLayoutResult(keys: keys, pinyinColumn: pinyinColumn, operatorColumn: operatorColumn)
        result.padFunctions = functions
        result.padMiddle = middle
        result.padUpper = CGRect(x: areaX, y: 0, width: areaWidth, height: upper.y + upper.height)
        return result
    }
}
