import SwiftUI

/// 按键区：画出按键，上面盖一层 UIKit 触摸层处理手感。
struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let layout = KeyLayout.build(model.layoutState, size: geo.size)
            ZStack(alignment: .topLeading) {
                if let panel = model.keysPanel {
                    Group {
                        if panel == .pinyin { PinyinPanel(model: model) } else { SymbolPanel(model: model) }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                } else if model.candidatesExpanded {
                    CandidateGrid(model: model)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ForEach(layout.keys) { key in
                        KeyCapView(model: model, key: key)
                            .frame(width: key.visual.width, height: key.visual.height)
                            .offset(x: key.visual.minX, y: key.visual.minY)
                    }
                    KeyTouchLayer(model: model, layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height)
                    if let column = layout.pinyinColumn {
                        PinyinColumn(model: model, frame: column)
                    }
                    // 字符键按下时的放大气泡（九宫格和系统一样不显示；弹出长按备选时也不显示）。
                    if !(model.layer == .letters && model.showsNineKey) {
                        ForEach(layout.keys.filter {
                            model.pressedKeys.contains($0.id) && $0.kind.typesCharacter && model.alternates?.key.id != $0.id
                        }) { key in
                            KeyPopup(model: model, key: key, containerWidth: geo.size.width)
                        }
                        .allowsHitTesting(false)
                    }
                    if let popup = model.alternates {
                        AlternatesView(popup: popup)
                    }
                    if let popup = model.cross {
                        CrossView(model: model, popup: popup)
                    }
                }
            }
        }
        .frame(height: KeyboardMetrics.keysHeight)
    }
}

/// 一个按键的外观。
struct KeyCapView: View {
    @ObservedObject var model: KeyboardModel
    let key: KeySpec

    var body: some View {
        let pressed = model.pressedKeys.contains(key.id)
        KeyCap(fill: fill(pressed: pressed), insetX: key.insetX, insetY: key.insetY) {
            label
                .foregroundStyle(foreground)
                .opacity(model.trackpadActive ? 0 : 1)
        }
    }

    private var returnLook: KeyboardModel.ReturnLook? {
        if case .returnKey = key.kind { return model.returnLook }
        return nil
    }

    private var highlighted: Bool { returnLook?.solid == true }

    /// iOS 26 键盘：所有键同色，按下变灰；带气泡的键按下时键帽不变色，气泡代替反馈。回车键浅紫或实心紫。
    private func fill(pressed: Bool) -> Color {
        if let look = returnLook {
            return look.solid ? Brand.purple.opacity(pressed ? 0.75 : 1) : Brand.returnSoftFill.opacity(pressed ? 0.7 : 1)
        }
        let showsPopup = key.kind.typesCharacter && !(model.showsNineKey && model.layer == .letters)
        return pressed && !showsPopup ? KeyStyle.pressedKey : KeyStyle.charKey
    }

    private var foreground: Color {
        if let look = returnLook { return look.solid ? .white : Brand.deepPurple }
        return .primary
    }

    @ViewBuilder
    private var label: some View {
        switch key.kind {
        case .letter(let letter):
            Text(model.shift == .off ? letter : letter.uppercased())
                .font(KeyStyle.letterFont)
                .offset(y: -1)
        case .symbol(let symbol):
            Text(KeyStyle.capText(symbol)).font(KeyStyle.capFont(for: symbol))
        case .nine(let digit):
            if digit == "'" {
                // 打拼音时是分词键，平时连按切换标点。
                if model.isComposing {
                    Text("分词").font(KeyStyle.functionFont)
                } else {
                    PunctuationLabel()
                }
            } else {
                Text(KeyLayout.nineKeyLetters[digit] ?? digit)
                    .font(KeyStyle.nineKeyFont)
                    .tracking(1)
            }
        case .shift:
            Image(systemName: model.shift == .locked ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
                .font(KeyStyle.iconFont)
        case .delete:
            Image(systemName: "delete.left").font(KeyStyle.iconFont)
        case .space:
            spaceLabel
        case .returnKey:
            let look = model.returnLook
            if let title = look.title {
                Text(title).font(.system(size: 17, weight: look.bold ? .semibold : .regular))
            } else {
                Image(systemName: "return.left").font(KeyStyle.iconFont)
            }
        case .toggleChinese:
            // 九宫格只用于中文，永远是「中」加深。
            ToggleLabel(chinese: model.showsNineKey || model.chineseMode,
                        size: model.showsNineKey ? KeyboardMetrics.nineToggleFontSize : KeyboardMetrics.toggleFontSize)
        case .globe:
            Image(systemName: "globe").font(KeyStyle.iconFont)
        case .emoticon:
            if model.isComposing {
                Text("重输").font(KeyStyle.functionFont)
            } else {
                // 「^^」字形偏上，往下挪一点视觉上才居中。
                Text("^^").font(KeyStyle.nineKeyFont).tracking(1).offset(y: 4)
            }
        case .emoji:
            Image(systemName: "face.smiling").font(KeyStyle.iconFont)
        case .pickPinyin:
            Text("选拼音").font(KeyStyle.functionFont)
                .opacity(model.isComposing ? 1 : 0.35)
        case .layer(let target):
            if model.showsNineKey && model.layer == .letters {
                Text(key.id == "symbols" ? "#@¥" : layerTitle(target)).font(KeyStyle.nineKeyFont).tracking(1)
            } else {
                Text(key.id == "symbols" ? "#@¥" : layerTitle(target)).font(KeyStyle.functionFont)
            }
        }
    }

    /// 空格键：中文「空格」两字之间留宽字距（九宫格 3pt、全键盘 4pt），英文「space」。
    private var spaceLabel: some View {
        let title = model.spaceTitle
        return Text(title).font(KeyStyle.functionFont)
            .tracking(title == "空格" ? (model.showsNineKey ? 3 : 4) : 0)
    }

    private func layerTitle(_ target: KeyboardModel.KeyLayer) -> String {
        switch target {
        case .numbers: return "123"
        case .symbols: return "#+="
        case .letters: return model.chineseMode ? "拼音" : "ABC"
        }
    }
}

/// 「中/英」：当前语言那个字加深加粗，另一个浅灰，斜杠更浅。
struct ToggleLabel: View {
    var chinese: Bool
    var size: CGFloat

    var body: some View {
        Text("中").font(.system(size: size, weight: chinese ? .semibold : .regular))
            .foregroundColor(chinese ? Brand.toggleActive : Brand.toggleInactive)
        + Text("/").font(.system(size: size)).foregroundColor(Brand.toggleSlash)
        + Text("英").font(.system(size: size, weight: chinese ? .regular : .semibold))
            .foregroundColor(chinese ? Brand.toggleInactive : Brand.toggleActive)
    }
}

/// 九宫格第一格的标点，照原生写成「,｡?!」：逗号半角，句号用半角圈，字距 1pt。
/// 全角「，。」的字形偏在左下角，排在一起会显得散。
struct PunctuationLabel: View {
    var body: some View {
        Text(",｡?!").font(KeyStyle.nineKeyFont).tracking(1)
    }
}

/// 按下字符键时键上方的放大气泡，形状和系统键盘一样：上面一个大圆角块，下面连着按键本身。
struct KeyPopup: View {
    @ObservedObject var model: KeyboardModel
    let key: KeySpec
    let containerWidth: CGFloat

    var body: some View {
        let cap = key.cap
        let bubbleWidth = cap.width + 22
        var bubbleX = cap.midX - bubbleWidth / 2
        bubbleX = min(max(bubbleX, 0), containerWidth - bubbleWidth)
        // 第一行上方空间有限，气泡不超出键盘顶部太多。
        let bubbleHeight: CGFloat = 54
        let bubble = CGRect(x: bubbleX, y: cap.minY - bubbleHeight + 4, width: bubbleWidth, height: bubbleHeight)
        return ZStack(alignment: .topLeading) {
            PopupShape(bubble: bubble, cap: cap)
                .fill(KeyStyle.charKey)
                .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
            Text(text)
                .font(.system(size: 34))
                .foregroundStyle(Color.primary)
                .frame(width: bubble.width, height: bubble.height - 6)
                .offset(x: bubble.minX, y: bubble.minY)
        }
    }

    private var text: String {
        switch key.kind {
        case .letter(let letter): return model.shift == .off ? letter : letter.uppercased()
        case .symbol(let symbol): return symbol
        default: return ""
        }
    }
}

struct PopupShape: Shape {
    let bubble: CGRect
    let cap: CGRect

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 10
        let capR: CGFloat = KeyStyle.cornerRadius
        let neckTop = bubble.maxY - 4
        var p = Path()
        p.move(to: CGPoint(x: cap.minX + capR, y: cap.maxY))
        p.addQuadCurve(to: CGPoint(x: cap.minX, y: cap.maxY - capR), control: CGPoint(x: cap.minX, y: cap.maxY))
        p.addLine(to: CGPoint(x: cap.minX, y: cap.minY + 6))
        p.addCurve(to: CGPoint(x: bubble.minX, y: neckTop - 6),
                   control1: CGPoint(x: cap.minX, y: cap.minY - 4),
                   control2: CGPoint(x: bubble.minX, y: neckTop + 2))
        p.addLine(to: CGPoint(x: bubble.minX, y: bubble.minY + r))
        p.addQuadCurve(to: CGPoint(x: bubble.minX + r, y: bubble.minY), control: CGPoint(x: bubble.minX, y: bubble.minY))
        p.addLine(to: CGPoint(x: bubble.maxX - r, y: bubble.minY))
        p.addQuadCurve(to: CGPoint(x: bubble.maxX, y: bubble.minY + r), control: CGPoint(x: bubble.maxX, y: bubble.minY))
        p.addLine(to: CGPoint(x: bubble.maxX, y: neckTop - 6))
        p.addCurve(to: CGPoint(x: cap.maxX, y: cap.minY + 6),
                   control1: CGPoint(x: bubble.maxX, y: neckTop + 2),
                   control2: CGPoint(x: cap.maxX, y: cap.minY - 4))
        p.addLine(to: CGPoint(x: cap.maxX, y: cap.maxY - capR))
        p.addQuadCurve(to: CGPoint(x: cap.maxX - capR, y: cap.maxY), control: CGPoint(x: cap.maxX, y: cap.maxY))
        p.closeSubpath()
        return p
    }
}

/// 候选词展开后铺满按键区，和系统键盘一样可以上下滑着挑。
struct CandidateGrid: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 0)], spacing: 0) {
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, word in
                        Button { model.selectCandidate(index) } label: {
                            Text(word)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .hidingScrollEdgeEffect()
            VStack(spacing: 0) {
                FunctionKey(systemImage: "chevron.up") { model.candidatesExpanded = false }
                    .frame(height: KeyboardMetrics.slotHeight)
                RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                    .frame(height: KeyboardMetrics.slotHeight)
                FunctionKey(title: "重输") { model.clearComposition() }
                    .frame(height: KeyboardMetrics.slotHeight)
                Spacer(minLength: 0)
            }
            .frame(width: 64)
        }
    }
}
