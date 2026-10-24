import SwiftUI
import CoreText

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
                    if let column = layout.operatorColumn {
                        OperatorColumn(model: model, frame: column)
                    }
                    // 字符键按下时的放大气泡（九宫格和系统一样不显示；弹出长按备选时也不显示）。
                    if !model.nineGrid {
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
        let showsPopup = key.kind.typesCharacter && !model.nineGrid
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
            if model.layer == .digits {
                Text(symbol).font(.system(size: 24))
            } else if let mark = ChinesePunctMark.Kind(rawValue: symbol) {
                ChinesePunctMark(kind: mark)
            } else if KeyStyle.centeredGlyphCaps.contains(symbol) {
                CenteredGlyph(symbol, size: 20)
            } else {
                Text(KeyStyle.capText(symbol)).font(KeyStyle.capFont(for: symbol))
            }
        case .digitPunct:
            Text(".,:").font(KeyStyle.nineKeyFont).tracking(1)
        case .digitsMore:
            if model.digitsMore {
                Text("返回").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.deepPurple)
            } else {
                Text("更多").font(KeyStyle.nineKeyFont)
            }
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
            // 字号跟着键所在的排法走：数字符号页是全键盘那种底栏，即使从九宫格进来也用全键盘的字号。
            ToggleLabel(chinese: model.showsNineKey || model.chineseMode,
                        size: model.nineGrid ? KeyboardMetrics.nineToggleFontSize : KeyboardMetrics.toggleFontSize)
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
            if model.nineGrid {
                if key.id == "symbols" {
                    SymbolsKeyLabel()
                } else {
                    Text(layerTitle(target)).font(KeyStyle.nineKeyFont).tracking(1)
                }
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
        case .digits: return "123"
        case .letters: return model.chineseMode || model.showsNineKey ? "拼音" : "ABC"
        }
    }
}

/// 「中/英」：当前语言那个字加深，另一个浅灰，斜杠更浅。
/// 两个字用同一个字重，只靠颜色区分：一粗一细时两边看着大小不一样，切换时字形也会跳。
struct ToggleLabel: View {
    var chinese: Bool
    var size: CGFloat

    var body: some View {
        let font = Font.system(size: size, weight: .medium)
        return Text("中").font(font)
            .foregroundColor(chinese ? Brand.toggleActive : Brand.toggleInactive)
        + Text("/").font(font).foregroundColor(Brand.toggleSlash)
        + Text("英").font(font)
            .foregroundColor(chinese ? Brand.toggleInactive : Brand.toggleActive)
    }
}

/// 九宫格第一格的标点「，。?!」：四个符号按设计稿 nine-key-punct-label.svg 一起画，
/// 笔画粗细、点的大小和间距统一，底线和旁边 16pt 的「123」「ABC」对齐。颜色跟着前景色。
struct PunctuationLabel: View {
    /// 设计稿 viewBox 是 (-0.5, 0, 32.5, 18)，底线 y = 15；显示高度 19.5pt。
    private static let scale: CGFloat = 19.5 / 18
    private static let size = CGSize(width: 32.5 * scale, height: 19.5)
    /// 16pt 系统字的底线在行中心下方 (ascender + descender) / 2，图的底线在中心下方 (15 − 9) × scale，差多少挪多少。
    private static let baselineShift: CGFloat = {
        let font = UIFont.systemFont(ofSize: 16)
        return (font.ascender + font.descender) / 2 - (15 - 9) * scale
    }()

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: Self.scale, y: Self.scale)
            context.translateBy(x: 0.5, y: 0)
            func round(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            // ，
            context.fill(dot(1.5, 13.4, 1.5), with: .foreground)
            var tail = Path()
            tail.move(to: CGPoint(x: 2.9, y: 13.6))
            tail.addCurve(to: CGPoint(x: 0.6, y: 17.5), control1: CGPoint(x: 3.0, y: 15.5), control2: CGPoint(x: 2.2, y: 16.8))
            context.stroke(tail, with: .foreground, style: round(1.2))
            // 。
            context.stroke(dot(8.8 + 2.2, 12.85, 2.15), with: .foreground, lineWidth: 1.3)
            // ?
            var question = Path()
            let qx: CGFloat = 17.4
            question.move(to: CGPoint(x: qx + 0.8, y: 6.3))
            question.addCurve(to: CGPoint(x: qx + 3.9, y: 3.2), control1: CGPoint(x: qx + 0.8, y: 4.4), control2: CGPoint(x: qx + 2.1, y: 3.2))
            question.addCurve(to: CGPoint(x: qx + 7, y: 6.1), control1: CGPoint(x: qx + 5.7, y: 3.2), control2: CGPoint(x: qx + 7, y: 4.4))
            question.addCurve(to: CGPoint(x: qx + 4.9, y: 9.1), control1: CGPoint(x: qx + 7, y: 7.7), control2: CGPoint(x: qx + 5.9, y: 8.4))
            question.addCurve(to: CGPoint(x: qx + 3.9, y: 11.1), control1: CGPoint(x: qx + 4.2, y: 9.6), control2: CGPoint(x: qx + 3.9, y: 10.1))
            question.addLine(to: CGPoint(x: qx + 3.9, y: 11.7))
            context.stroke(question, with: .foreground, style: round(1.6))
            context.fill(dot(qx + 3.9, 14, 1.05), with: .foreground)
            // !
            var bang = Path()
            bang.move(to: CGPoint(x: 29.4 + 1.05, y: 3.6))
            bang.addLine(to: CGPoint(x: 29.4 + 1.05, y: 11.2))
            context.stroke(bang, with: .foreground, style: round(1.7))
            context.fill(dot(29.4 + 1.05, 14, 1.05), with: .foreground)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .offset(y: Self.baselineShift)
        .accessibilityLabel("标点")
    }
}

/// 九宫格左列的「#@¥」：三个字符各占 13pt 宽的格子，@ 缩到 14.5pt 并上移 1pt，三个看起来一样大。
struct SymbolsKeyLabel: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("#").font(KeyStyle.nineKeyFont).frame(width: 13)
            Text("@").font(.system(size: 14.5)).offset(y: -1).frame(width: 13)
            Text("¥").font(KeyStyle.nineKeyFont).frame(width: 13)
        }
    }
}

/// 中文符号页的 ，。、 照设计稿 cn-comma / cn-period / cn-dun.svg 画在 24×24 的框里，放在键正中。
/// 三个符号上下对齐，底端落在同一行 ?! . 的底线上（键中心往下约 7pt）。颜色跟着前景色。
struct ChinesePunctMark: View {
    enum Kind: String { case comma = "，", period = "。", dun = "、" }
    let kind: Kind

    var body: some View {
        Canvas { context, _ in
            let round = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            switch kind {
            case .period:
                context.stroke(Path(ellipseIn: CGRect(x: 12 - 1.62, y: 17.05 - 1.62, width: 3.24, height: 3.24)),
                               with: .foreground, lineWidth: 1.15)
            case .comma:
                context.fill(Path(ellipseIn: CGRect(x: 11.55 - 1.3, y: 16.15 - 1.3, width: 2.6, height: 2.6)), with: .foreground)
                var tail = Path()
                tail.move(to: CGPoint(x: 12.8, y: 16.3))
                tail.addCurve(to: CGPoint(x: 11.05, y: 19.05),
                              control1: CGPoint(x: 12.9, y: 17.55), control2: CGPoint(x: 12.35, y: 18.45))
                context.stroke(tail, with: .foreground, style: round)
            case .dun:
                var stroke = Path()
                stroke.move(to: CGPoint(x: 10.95, y: 15.6))
                stroke.addCurve(to: CGPoint(x: 13.05, y: 18.5),
                                control1: CGPoint(x: 11.85, y: 16.2), control2: CGPoint(x: 12.55, y: 17.1))
                var style = round
                style.lineWidth = 1.5
                context.stroke(stroke, with: .foreground, style: style)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(kind.rawValue)
    }
}

/// 全角标点的字形偏在字框左下角，直接用 Text 排出来会散。这里取 PingFang SC 的字形外框，
/// 把外框中心画到图的中心，再按 drop 往下偏。模板图，颜色跟着前景色。
struct CenteredGlyph: View {
    let image: UIImage

    init(_ character: String, size: CGFloat, drop: CGFloat = 0, box: CGFloat? = nil) {
        image = Self.render(character, size: size, drop: drop, box: box ?? size)
    }

    var body: some View { Image(uiImage: image) }

    private static var cache: [String: UIImage] = [:]

    private static func render(_ character: String, size: CGFloat, drop: CGFloat, box: CGFloat) -> UIImage {
        let key = "\(character)|\(size)|\(drop)|\(box)"
        if let cached = cache[key] { return cached }
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
        var chars = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
        let canvas = CGSize(width: box, height: size)
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            guard let glyph = glyphs.first, let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return }
            var bounds = CGRect.zero
            var glyphCopy = glyph
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphCopy, &bounds, 1)
            let cg = context.cgContext
            // 字形坐标 y 向上：翻转后把外框中心移到画布中心，再往下偏 drop。
            cg.translateBy(x: canvas.width / 2 - bounds.midX, y: canvas.height / 2 + bounds.midY + drop)
            cg.scaleBy(x: 1, y: -1)
            cg.addPath(path)
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillPath()
        }.withRenderingMode(.alwaysTemplate)
        cache[key] = image
        return image
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
