import SwiftUI

/// 按键区：26 键（字母、数字、符号三层）或九宫格，布局参照 iOS 自带键盘。
/// 每个按键占一个「格子」，格子之间没有空隙，按键的间隙也算在格子里。
struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let digits = "1234567890".map(String.init)

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 10
            if model.layer == .letters && model.showsNineKey {
                NineKeyView(model: model, width: geo.size.width)
            } else {
                VStack(spacing: 0) {
                    switch model.layer {
                    case .letters: letterRows(unit: unit)
                    case .numbers: symbolRows(numberSymbols, switchTitle: "#+=", switchTo: .symbols, unit: unit)
                    case .symbols: symbolRows(moreSymbols, switchTitle: "123", switchTo: .numbers, unit: unit)
                    }
                    bottomRow(unit: unit)
                }
            }
        }
        .frame(height: KeyboardMetrics.keysHeight)
    }

    // MARK: - 字母

    @ViewBuilder
    private func letterRows(unit: CGFloat) -> some View {
        let rows = Self.letterRows
        row { ForEach(rows[0], id: \.self) { letterKey($0).frame(width: unit) } }
        row { ForEach(rows[1], id: \.self) { letterKey($0).frame(width: unit) } }
        row {
            FunctionKey(systemImage: shiftIcon, highlighted: false) { model.shiftKey() }
                .frame(width: unit * 1.5)
            ForEach(rows[2], id: \.self) { letterKey($0).frame(width: unit) }
            RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                .frame(width: unit * 1.5)
        }
    }

    private var shiftIcon: String {
        switch model.shift {
        case .off: return "shift"
        case .on: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }

    private func letterKey(_ letter: String) -> some View {
        CharKey(title: model.shift == .off ? letter : letter.uppercased()) { model.typeLetter(letter) }
    }

    // MARK: - 数字和符号

    private var numberSymbols: [[String]] {
        model.chineseMode
            ? [Self.digits, ["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"], ["。", "，", "、", "？", "！", "."]]
            : [Self.digits, ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
    }

    private var moreSymbols: [[String]] {
        [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
         ["_", "\\", "|", "~", "<", ">", "€", "£", "•", "…"],
         ["·", "《", "》", "‘", "’"]]
    }

    @ViewBuilder
    private func symbolRows(_ rows: [[String]], switchTitle: String, switchTo: KeyboardModel.KeyLayer, unit: CGFloat) -> some View {
        row { ForEach(rows[0], id: \.self) { symbolKey($0).frame(width: unit) } }
        row { ForEach(rows[1], id: \.self) { symbolKey($0).frame(width: unit) } }
        row {
            FunctionKey(title: switchTitle) { model.switchLayer(switchTo) }
                .frame(width: unit * 1.5)
            ForEach(rows[2], id: \.self) { symbolKey($0).frame(width: unit * 7 / CGFloat(rows[2].count)) }
            RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                .frame(width: unit * 1.5)
        }
    }

    private func symbolKey(_ symbol: String) -> some View {
        CharKey(title: symbol, font: .system(size: 21)) { model.typeSymbol(symbol) }
    }

    // MARK: - 底栏

    private func bottomRow(unit: CGFloat) -> some View {
        row {
            KeyboardBottomKeys(model: model, unit: unit)
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .frame(height: KeyboardMetrics.slotHeight)
    }
}

/// 底栏：123、（地球）、中/英、空格、换行。九宫格用自己的底栏。
struct KeyboardBottomKeys: View {
    @ObservedObject var model: KeyboardModel
    var unit: CGFloat

    var body: some View {
        let side = unit * 1.25
        FunctionKey(title: model.layer == .letters ? "123" : (model.chineseMode ? "拼音" : "ABC")) {
            model.switchLayer(model.layer == .letters ? .numbers : .letters)
        }
        .frame(width: side)
        if model.needsGlobeKey {
            KeyCap(fill: KeyStyle.functionKey) {
                NextKeyboardButton(controller: model.controller)
            }
            .frame(width: side)
        }
        FunctionKey(title: model.chineseMode ? "中" : "英") { model.toggleChinese() }
            .frame(width: side)
        CharKey(title: model.spaceTitle, font: KeyStyle.functionFont) { model.spaceKey() }
        FunctionKey(title: model.returnTitle, highlighted: model.returnHighlighted) { model.returnKey() }
            .frame(width: unit * 2.5)
    }
}

extension KeyboardModel {
    var spaceTitle: String {
        if isComposing { return "选定" }
        if !chineseMode { return "space" }
        // 词库没部署或没开完全访问时，中文模式也只能直接打字母。
        return pinyinReady ? "空格" : "空格（拼音未就绪）"
    }

    var returnTitle: String {
        if isComposing { return "确认" }
        return target == .instruction ? "执行" : (chineseMode ? "换行" : "return")
    }

    var returnHighlighted: Bool { target == .instruction && !isComposing }
}
