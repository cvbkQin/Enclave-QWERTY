import SwiftUI

/// 26 键键盘区：字母、数字、符号三层，加底栏。
struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    private let spacing: CGFloat = 6
    private let rowHeight: CGFloat = 44

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let digits = "1234567890".map(String.init)

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - spacing * 9) / 10
            VStack(spacing: 8) {
                switch model.layer {
                case .letters: letterRows(unit: unit)
                case .numbers: symbolRows(numberSymbols, switchTitle: "#+=", switchTo: .symbols, unit: unit)
                case .symbols: symbolRows(moreSymbols, switchTitle: "123", switchTo: .numbers, unit: unit)
                }
                bottomRow(unit: unit)
            }
        }
        .frame(height: rowHeight * 4 + 8 * 3)
    }

    // MARK: - 字母

    @ViewBuilder
    private func letterRows(unit: CGFloat) -> some View {
        let rows = Self.letterRows
        row { ForEach(rows[0], id: \.self) { letterKey($0) } }
        row { ForEach(rows[1], id: \.self) { letterKey($0) } }
            .padding(.horizontal, (unit + spacing) / 2)
        row {
            FunctionKey(systemImage: shiftIcon, highlighted: model.shift != .off) { model.shiftKey() }
                .frame(width: unit * 1.35)
            Spacer(minLength: 0)
            ForEach(rows[2], id: \.self) { letterKey($0).frame(width: unit) }
            Spacer(minLength: 0)
            RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                .frame(width: unit * 1.35)
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
        row { ForEach(rows[0], id: \.self) { symbolKey($0) } }
        row { ForEach(rows[1], id: \.self) { symbolKey($0) } }
        row {
            FunctionKey(title: switchTitle) { model.switchLayer(switchTo) }
                .frame(width: unit * 1.35)
            Spacer(minLength: 0)
            ForEach(rows[2], id: \.self) { symbolKey($0).frame(width: unit * 1.3) }
            Spacer(minLength: 0)
            RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                .frame(width: unit * 1.35)
        }
    }

    private func symbolKey(_ symbol: String) -> some View {
        CharKey(title: symbol) { model.typeSymbol(symbol) }
    }

    // MARK: - 底栏

    private func bottomRow(unit: CGFloat) -> some View {
        row {
            FunctionKey(title: model.layer == .letters ? "123" : "ABC") {
                model.switchLayer(model.layer == .letters ? .numbers : .letters)
            }
            .frame(width: unit * 1.35)
            if model.needsGlobeKey {
                NextKeyboardButton(controller: model.controller)
                    .frame(width: unit * 1.1)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray3)))
            }
            VoiceKey(model: model)
                .frame(width: unit * 1.1)
            CharKey(title: model.isComposing ? "选定" : (model.chineseMode ? "空格" : "space")) { model.spaceKey() }
            FunctionKey(title: model.chineseMode ? "中" : "英") { model.toggleChinese() }
                .frame(width: unit * 1.1)
            FunctionKey(title: returnTitle, highlighted: model.target == .instruction && !model.isComposing) { model.returnKey() }
                .frame(width: unit * 1.9)
        }
    }

    private var returnTitle: String {
        if model.isComposing { return "确认" }
        return model.target == .instruction ? "执行" : (model.chineseMode ? "换行" : "return")
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: spacing) { content() }
            .frame(height: rowHeight)
    }
}

/// 🎤 键：短按说内容，长按说要求；录音中再按一下结束。
struct VoiceKey: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let recording = model.voiceState == .recording
        let busy = model.voiceState == .transcribing
        Image(systemName: recording ? "stop.fill" : (busy ? "ellipsis" : "mic"))
            .font(.body)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(recording ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 6).fill(recording ? Color.red : Color(.systemGray3)))
            .contentShape(Rectangle())
            .onTapGesture {
                if recording {
                    model.voiceTapped(model.voiceMode)
                } else if !busy {
                    model.voiceTapped(.content)
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !recording, !busy else { return }
                model.voiceTapped(.instruction)
            }
    }
}

/// 字符键：白底。
struct CharKey: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.primary)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 功能键：灰底，可高亮。
struct FunctionKey: View {
    var title: String?
    var systemImage: String?
    var highlighted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(title ?? "") }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Color.accentColor : Color(.systemGray3)))
            .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 按下时稍微变暗。
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
