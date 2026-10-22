import SwiftUI

/// 按键区：画出按键，上面盖一层 UIKit 触摸层处理手感。
struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let layout = KeyLayout.build(model.layoutState, size: geo.size)
            ZStack(alignment: .topLeading) {
                if model.candidatesExpanded {
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
                    // 字符键按下时的放大气泡（九宫格和系统一样不显示）。
                    if !(model.layer == .letters && model.showsNineKey) {
                        ForEach(layout.keys.filter { model.pressedKeys.contains($0.id) && $0.kind.typesCharacter }) { key in
                            KeyPopup(model: model, key: key, containerWidth: geo.size.width)
                        }
                        .allowsHitTesting(false)
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

    private var highlighted: Bool {
        if case .returnKey = key.kind { return model.returnHighlighted }
        return false
    }

    /// iOS 26 键盘：所有键同色，按下变灰；带气泡的键按下时键帽不变色，气泡代替反馈。
    private func fill(pressed: Bool) -> Color {
        if highlighted { return Color.accentColor.opacity(pressed ? 0.75 : 1) }
        let showsPopup = key.kind.typesCharacter && !(model.showsNineKey && model.layer == .letters)
        return pressed && !showsPopup ? KeyStyle.pressedKey : KeyStyle.charKey
    }

    private var foreground: Color {
        highlighted ? .white : .primary
    }

    @ViewBuilder
    private var label: some View {
        switch key.kind {
        case .letter(let letter):
            Text(model.shift == .off ? letter : letter.uppercased())
                .font(KeyStyle.letterFont)
                .offset(y: -1)
        case .symbol(let symbol):
            Text(symbol).font(KeyStyle.symbolFont)
        case .nine(let digit):
            if digit == "'" {
                // 打拼音时是分词键，平时连按切换标点。
                Text(model.isComposing ? "分词" : ",。?!").font(KeyStyle.functionFont).tracking(model.isComposing ? 0 : 1)
            } else {
                Text(KeyLayout.nineKeyLetters[digit] ?? digit)
                    .font(KeyStyle.nineKeyFont)
                    .tracking(2.2)
            }
        case .shift:
            Image(systemName: model.shift == .locked ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
                .font(KeyStyle.iconFont)
        case .delete:
            Image(systemName: "delete.left").font(KeyStyle.iconFont)
        case .space:
            spaceLabel
        case .returnKey:
            if let title = model.returnTitle {
                Text(title).font(KeyStyle.functionFont)
            } else {
                Image(systemName: "return.left").font(KeyStyle.iconFont)
            }
        case .toggleChinese:
            Text(model.showsNineKey ? "ABC" : (model.chineseMode ? "中" : "英")).font(KeyStyle.functionFont)
        case .globe:
            Image(systemName: "globe").font(KeyStyle.iconFont)
        case .clearComposition:
            Text("重输").font(KeyStyle.functionFont)
        case .layer(let target):
            Text(key.id == "symbols" ? "#@¥" : layerTitle(target)).font(KeyStyle.functionFont)
        }
    }

    /// 和系统一样，空格键平时不写字，只在右下角用小字标出当前语言。
    @ViewBuilder
    private var spaceLabel: some View {
        if let title = model.spaceTitle {
            // 九宫格的「空格」两字之间系统留了较宽的字距。
            Text(title).font(KeyStyle.functionFont).tracking(model.showsNineKey && title == "空格" ? 3 : 0)
        } else {
            Color.clear.overlay(alignment: .bottomTrailing) {
                Text(model.chineseMode ? "拼" : "EN")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .padding(.trailing, 9)
                    .padding(.bottom, 5)
            }
        }
    }

    private func layerTitle(_ target: KeyboardModel.KeyLayer) -> String {
        switch target {
        case .numbers: return "123"
        case .symbols: return "#+="
        case .letters: return model.chineseMode ? "拼音" : "ABC"
        }
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
