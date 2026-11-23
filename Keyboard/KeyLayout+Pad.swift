import CoreGraphics

/// iPad 全宽键盘的 26 键和数字符号页（PK1、PK2、PK9，照 iPad 原生）。
///
/// 每一排按「格」排：一排 S 格（11 寸 12.8、13 寸 14.6），键宽 w 格，键帽之间隔 gap。
/// 按键区左右已经让开了 edge − gap/2（KeyboardMetrics.sidePadding），所以一格就是 按键区宽 / S，
/// 键帽在自己的格子里四周各缩进 gap/2：两颗键帽之间正好一条缝，最外面的键帽离键盘边正好 edge。
/// 最下面一排矮 15%（PadMetrics.bottomKeyHeight）。触摸范围：第一排往上、最后一排往下一直到按键区边上。
extension KeyLayout {
    struct PadKey {
        let id: String
        let kind: KeyKind
        var units: CGFloat = 1
        /// 往下滑打出的字（11 寸字母上的灰色小字）。
        var flick: String?
    }

    static func padBoard(_ state: State, size: CGSize, pad: PadMetrics) -> KeyLayoutResult {
        let rows = padRows(state, pad: pad)
        let pitch = pad.keyHeight + pad.gap
        var keys: [KeySpec] = []
        for (index, row) in rows.enumerated() {
            let total = row.reduce(0) { $0 + $1.units }
            guard total > 0 else { continue }
            let cell = size.width / total
            let last = index == rows.count - 1
            let y = pad.top - pad.gap / 2 + CGFloat(index) * pitch
            let height = (last ? pad.bottomKeyHeight : pad.keyHeight) + pad.gap
            let touchTop = index == 0 ? 0 : y
            let touchBottom = last ? max(size.height, y + height) : y + height
            var x: CGFloat = 0
            for key in row {
                let width = key.units * cell
                var spec = KeySpec(id: key.id, kind: key.kind,
                                   frame: CGRect(x: x, y: touchTop, width: width, height: touchBottom - touchTop),
                                   visual: CGRect(x: x, y: y, width: width, height: height))
                spec.insetX = pad.gap / 2
                spec.insetY = pad.gap / 2
                spec.flick = key.flick
                keys.append(spec)
                x += width
            }
        }
        return KeyLayoutResult(keys: keys)
    }

    /// 每一排的键（从上往下）。
    static func padRows(_ state: State, pad: PadMetrics) -> [[PadKey]] {
        let chinese = state.chineseMode
        switch state.layer {
        case .letters, .digits:
            // 9 键模式下的英文（PK19）13 寸也照 11 寸排 4 行，和 9 键一样高。
            return pad.wide ? padLetters13(state, chinese: chinese) : padLetters11(state, chinese: chinese)
        case .numbers, .symbols:
            return padSymbolPage(state, chinese: chinese, big: pad.wide)
        }
    }

    // MARK: 字母页

    /// 11 寸（PK1）：
    /// tab   q w e r t y u i o p   ⌫
    /// 中/英  a s d f g h j k l    发送
    /// ⇧     z x c v b n m ，。    ⇧
    /// 🌐 123 ☺   空格   「，。」 123 ⌨↓
    private static func padLetters11(_ state: State, chinese: Bool) -> [[PadKey]] {
        let hints = state.padLetterHints ? padLetterHints(chinese: chinese) : nil
        let letters = letterRows.enumerated().map { row, keys in
            keys.enumerated().map { i, letter in PadKey(id: letter, kind: .letter(letter), flick: hints?[row][i]) }
        }
        // 「，。」本来就画着 ⇧ 出的「！？」，开着下滑时往下滑也打它（和原生一样）。
        var comma = chinese ? PadKey(id: "p-comma", kind: .padSymbol("，", shifted: "！"))
                            : PadKey(id: "p-comma", kind: .padSymbol(",", shifted: "!"))
        var period = chinese ? PadKey(id: "p-period", kind: .padSymbol("。", shifted: "？"))
                             : PadKey(id: "p-period", kind: .padSymbol(".", shifted: "?"))
        if hints != nil {
            comma.flick = chinese ? "！" : "!"
            period.flick = chinese ? "？" : "?"
        }
        return [
            [PadKey(id: "tab", kind: .tab, units: 1.4)] + letters[0] + [PadKey(id: "delete", kind: .delete, units: 1.4)],
            [secondRowKey(state, units: 1.9)] + letters[1] + [PadKey(id: "return", kind: .returnKey, units: 1.9)],
            [PadKey(id: "shift", kind: .shift, units: 1.9)] + letters[2] + [comma, period, PadKey(id: "shift2", kind: .shift, units: 1.9)],
            padBottomRow(state, total: 12.8, side: 1, layer: 1.4, letters: true),
        ]
    }

    /// 11 寸字母上的灰色小字（PK1，照 iPad 原生）：第一排数字，下面两排符号；中文模式是中文的 ¥（）‘“；：。
    static func padLetterHints(chinese: Bool) -> [[String]] {
        [digits,
         chinese ? ["@", "#", "¥", "&", "*", "（", "）", "‘", "“"] : ["@", "#", "$", "&", "*", "(", ")", "'", "\""],
         chinese ? ["%", "-", "+", "=", "/", "；", "："] : ["%", "-", "+", "=", "/", ";", ":"]]
    }

    /// 13 寸（PK2）：多一排数字，标点各有自己的键。中文时直接出中文标点，键帽上灰色小字是按 ⇧ 出的。
    /// ·  1 2 3 4 5 6 7 8 9 0 - =  ⌫
    /// tab  q w e r t y u i o p 【 】 、
    /// 中/英 a s d f g h j k l ； ‘  发送
    /// ⇧     z x c v b n m ， 。 /    ⇧
    /// 🌐 123 ☺    空格    「，。」 123 ⌨↓
    private static func padLetters13(_ state: State, chinese: Bool) -> [[PadKey]] {
        let letters = letterRows.map { $0.map { PadKey(id: $0, kind: .letter($0)) } }
        func punct(_ id: String, _ cn: (String, String), _ en: (String, String)) -> PadKey {
            let pair = chinese ? cn : en
            return PadKey(id: id, kind: .padSymbol(pair.0, shifted: pair.1))
        }
        return [
            padNumberRow(chinese: chinese),
            [PadKey(id: "tab", kind: .tab, units: 1.6)] + letters[0]
                + [punct("p-lbracket", ("【", "「"), ("[", "{")), punct("p-rbracket", ("】", "」"), ("]", "}")),
                   punct("p-backslash", ("、", "｜"), ("\\", "|"))],
            [secondRowKey(state, units: 1.9)] + letters[1]
                + [punct("p-semicolon", ("；", "："), (";", ":")), punct("p-quote", ("‘", "“"), ("'", "\"")),
                   PadKey(id: "return", kind: .returnKey, units: 1.7)],
            [PadKey(id: "shift", kind: .shift, units: 2.3)] + letters[2]
                + [punct("p-comma", ("，", "《"), (",", "<")), punct("p-period", ("。", "》"), (".", ">")),
                   punct("p-slash", ("/", "？"), ("/", "?")), PadKey(id: "shift2", kind: .shift, units: 2.3)],
            padBottomRow(state, total: 14.6, side: 1.2, layer: 1.6, letters: true),
        ]
    }

    /// 13 寸最上面的数字行：· 1–0 - = ⌫，按 ⇧ 出上面的灰色小字。
    private static func padNumberRow(chinese: Bool) -> [PadKey] {
        let shifted = chinese ? ["！", "@", "#", "¥", "%", "……", "&", "*", "（", "）"]
                              : ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"]
        var row = [PadKey(id: "p-grave", kind: chinese ? .padSymbol("·", shifted: "～") : .padSymbol("`", shifted: "~"))]
        for (i, digit) in digits.enumerated() {
            row.append(PadKey(id: "p-\(digit)", kind: .padSymbol(digit, shifted: shifted[i])))
        }
        row.append(PadKey(id: "p-minus", kind: chinese ? .padSymbol("-", shifted: "——") : .padSymbol("-", shifted: "_")))
        row.append(PadKey(id: "p-equal", kind: .padSymbol("=", shifted: "+")))
        row.append(PadKey(id: "delete", kind: .delete, units: 1.6))
        return row
    }

    /// 第二排最左：「中/英」放在原生大写锁定的位置。只用英文时没有中文可切，这里放一颗 ⇧。
    /// 9 键模式下的英文（PK20、PK21，11-23 cvbk 选）：中/英挪到最下面一排和九键对位置，这里换成「常用 剪贴板」，
    /// 点了打开常用语和剪贴板面板（盖住按键区，键盘不变高）。
    private static func secondRowKey(_ state: State, units: CGFloat) -> PadKey {
        if state.englishOnly { return PadKey(id: "shift3", kind: .shift, units: units) }
        if state.nineEnglish { return PadKey(id: "quickWords", kind: .quickWords, units: units) }
        return PadKey(id: "chinese", kind: .toggleChinese, units: units)
    }

    /// 最下面一排：🌐 123 ☺ 空格（「，。」）123 ⌨↓。「，。」键宽一格，从空格里让出来，跟着设置放空格左边或右边；
    /// 只在字母页有（数字符号页的第一个 123 是 ABC，回字母）。
    /// 9 键模式下的英文（PK20、PK21，11-23 cvbk「在空格的部和9键对应的位置做个中英切换按钮」）：从空格里再让出一颗中/英，
    /// 和 123 一样宽，手不用挪就点得到九键那颗的位置：
    /// - 九键在右：放在空格右头（🌐 123 ☺ 空格 中/英 「，。」 123 ⌨↓）；
    /// - 九键在左：放在 🌐 右边原来 123 的位置，123、☺ 往右让（🌐 中/英 123 ☺ 空格 「，。」 123 ⌨↓）。
    /// 数字符号页的最下面一排也和字母页一样，有「，。」和这颗中/英。
    private static func padBottomRow(_ state: State, total: CGFloat, side: CGFloat, layer: CGFloat, letters: Bool) -> [PadKey] {
        let target: KeyboardModel.KeyLayer = letters ? .numbers : .letters
        let punct = letters || state.nineEnglish ? state.quickPunct : nil
        let punctKey = PadKey(id: "quickPunct", kind: .quickPunct(chinese: state.chineseMode))
        let toggle = state.nineEnglish ? PadKey(id: "chinese", kind: .toggleChinese, units: layer) : nil
        let fixed = side * 2 + layer * 3 + (punct == nil ? 0 : 1) + (toggle == nil ? 0 : layer)
        let space = PadKey(id: "space", kind: .space, units: total - fixed)
        var row = [PadKey(id: "globe", kind: .globe, units: side)]
        if let toggle, state.nineOnLeft { row.append(toggle) }
        row += [PadKey(id: "layer", kind: .layer(target), units: layer),
                PadKey(id: "emoji", kind: .emoji, units: side)]
        let spaceGroup = [space] + (state.nineOnLeft ? [] : [toggle].compactMap { $0 })
        switch punct {
        case .left?: row += [punctKey] + spaceGroup
        case .right?: row += spaceGroup + [punctKey]
        case nil: row += spaceGroup
        }
        row += [PadKey(id: "layer2", kind: .layer(target), units: layer), PadKey(id: "dismiss", kind: .dismiss, units: layer)]
        return row
    }

    // MARK: 数字和符号页（PK9）

    /// 11 寸照 iPad 原生，123 层：
    /// tab  1 2 3 4 5 6 7 8 9 0  ⌫
    /// 中/英 - / ： ； （ ） ¥ @ “ 发送
    /// #+=  。 ， 、 ？ ！ … ～ · ‘ #+=
    /// 🌐 ABC ☺     空格     ABC ⌨↓
    /// #+= 层第一行换成【】｛｝# % ^ * + =，左右两颗换回 123。
    /// 13 寸第一行是字母页那排数字（本来就有，123 层只放符号）；#+= 层第一行多放三个（中文「 」&，英文 ` & @）。
    private static func padSymbolPage(_ state: State, chinese: Bool, big: Bool) -> [[PadKey]] {
        let symbols = state.layer == .symbols
        let rows = padSymbolRows(chinese: chinese, symbols: symbols)
        func keys(_ row: Int) -> [PadKey] {
            rows[row].enumerated().map { PadKey(id: "s\(row)-\($0.offset)", kind: .symbol($0.element)) }
        }
        let switchTarget: KeyboardModel.KeyLayer = symbols ? .numbers : .symbols
        let language = state.englishOnly ? PadKey(id: "abc", kind: .layer(.letters), units: 1.9) : secondRowKey(state, units: 1.9)
        let first: [PadKey]
        if big {
            if symbols {
                // 第二排已经有 _ — ＼，这里放这一页别处没有的。
                let extra: [String] = chinese ? ["「", "」", "&"] : ["`", "&", "@"]
                let extraKeys = extra.enumerated().map { PadKey(id: "s0-x\($0.offset)", kind: .symbol($0.element)) }
                first = keys(0) + extraKeys + [PadKey(id: "delete", kind: .delete, units: 1.6)]
            } else {
                first = padNumberRow(chinese: chinese)
            }
        } else {
            first = [PadKey(id: "tab", kind: .tab, units: 1.4)] + keys(0) + [PadKey(id: "delete", kind: .delete, units: 1.4)]
        }
        return [
            first,
            [language] + keys(1) + [PadKey(id: "return", kind: .returnKey, units: 1.9)],
            [PadKey(id: "layer3", kind: .layer(switchTarget), units: 1.9)] + keys(2)
                + [PadKey(id: "layer4", kind: .layer(switchTarget), units: 1.9)],
            big ? padBottomRow(state, total: 14.6, side: 1.2, layer: 1.6, letters: false)
                : padBottomRow(state, total: 12.8, side: 1, layer: 1.4, letters: false),
        ]
    }

    /// 数字符号页的三排符号（第一排 10 个，第二、三排各 9 个）。
    static func padSymbolRows(chinese: Bool, symbols: Bool) -> [[String]] {
        switch (chinese, symbols) {
        case (true, false):
            return [digits, ["-", "/", "：", "；", "（", "）", "¥", "@", "“"], ["。", "，", "、", "？", "！", "…", "～", "·", "‘"]]
        case (true, true):
            return [["【", "】", "｛", "｝", "#", "%", "^", "*", "+", "="], ["_", "—", "＼", "｜", "《", "》", "€", "$", "”"],
                    ["。", "，", "、", "？", "！", "…", "～", "·", "’"]]
        case (false, false):
            return [digits, ["-", "/", ":", ";", "(", ")", "$", "&", "@"], [".", ",", "?", "!", "'", "\"", "…", "~", "`"]]
        case (false, true):
            return [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥"],
                    [".", ",", "?", "!", "'", "•", "§", "°", "\""]]
        }
    }
}
