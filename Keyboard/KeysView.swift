import SwiftUI
import CoreText

/// 按键区：画出按键，上面盖一层 UIKit 触摸层处理手感。
struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let layout = KeyLayout.cachedBuild(model.layoutState, size: geo.size)
            let context = model.keyCapContext
            ZStack(alignment: .topLeading) {
                if let panel = model.keysPanel {
                    Group {
                        switch panel {
                        case .quickWords: QuickWordsPanel(model: model)
                        case .words: WordPanel(model: model).opacity(model.wordPanelFading ? 0 : 1)
                        case .emoji, .kaomoji: SymbolPanel(model: model)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                } else if model.pinyinGridOpen, model.pinyinSide, model.showsNineKey {
                    // 侧边模式点了拼音列的 ⌄：按键区换成拼音格子（F12）。
                    SidePinyinGrid(model: model)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if model.candidatesExpanded {
                    // 拼音在上方一行时那一行展开时也留着，整页候选铺满按键区；
                    // 在侧边（F12）时九宫格左边的拼音列保持住、拉长到 4 行，候选铺在中间三列。
                    let column = model.pinyinSide && model.showsNineKey ? layout.pinyinColumn : nil
                    CandidateGrid(model: model, leading: column?.maxX ?? 0)
                        .frame(width: geo.size.width, height: geo.size.height)
                    if let column {
                        SidePinyinColumn(model: model, frame: CGRect(x: column.minX, y: column.minY,
                                                                     width: column.width, height: column.height / 3 * 4))
                    }
                } else {
                    ForEach(layout.keys) { key in
                        KeyCapCell(presses: model.keyPresses, context: context, key: key)
                            .frame(width: key.visual.width, height: key.visual.height)
                            .offset(x: key.visual.minX, y: key.visual.minY)
                    }
                    KeyTouchLayer(model: model, layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height)
                    if let column = layout.pinyinColumn {
                        SidePinyinColumn(model: model, frame: column)
                    }
                    if let column = layout.operatorColumn {
                        OperatorColumn(model: model, frame: column)
                    }
                    // 字符键按下时的放大气泡（九宫格和系统一样不显示；弹出长按备选时也不显示）。
                    if !model.nineGrid {
                        KeyPopupLayer(presses: model.keyPresses, keys: layout.keys, hiddenKey: model.alternates?.key.id,
                                      uppercase: model.shift != .off, containerWidth: geo.size.width)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                    if let popup = model.alternates {
                        AlternatesView(popup: popup)
                    }
                    if let popup = model.cross {
                        CrossView(model: model, popup: popup)
                    }
                    if let menu = model.layoutMenu {
                        LayoutMenuView(menu: menu)
                    }
                }
            }
        }
        .frame(height: KeyboardMetrics.keysHeight)
    }
}

/// 正被按住的键。和 KeyboardModel 分开：按下、松开只让按键和气泡重画。
final class KeyPresses: ObservableObject {
    @Published var pressed: Set<String> = []
}

/// 画键帽要用到的键盘状态。只有这些值变了才重画键帽，打拼音时候选、拼写变化不牵动按键。
struct KeyCapContext: Equatable {
    var shift: KeyboardModel.ShiftState
    var layer: KeyboardModel.KeyLayer
    var composing: Bool
    var nineGrid: Bool
    var showsNineKey: Bool
    var chineseMode: Bool
    var digitsMore: Bool
    var trackpadActive: Bool
    var spaceTitle: String
    var returnLook: KeyboardModel.ReturnLook
}

extension KeyboardModel {
    var keyCapContext: KeyCapContext {
        KeyCapContext(shift: shift, layer: layer, composing: isComposing, nineGrid: nineGrid, showsNineKey: showsNineKey,
                      chineseMode: chineseMode, digitsMore: digitsMore, trackpadActive: trackpadActive,
                      spaceTitle: spaceTitle, returnLook: returnLook)
    }
}

/// 一个键位：盯着按下状态，键帽本身只在自己按下、松开或 context 变了时重画。
struct KeyCapCell: View {
    @ObservedObject var presses: KeyPresses
    let context: KeyCapContext
    let key: KeySpec

    var body: some View {
        KeyCapView(context: context, key: key, pressed: presses.pressed.contains(key.id))
            .equatable()
    }
}

/// 按下字符键时的放大气泡（九宫格不显示）。
struct KeyPopupLayer: View {
    @ObservedObject var presses: KeyPresses
    let keys: [KeySpec]
    /// 弹出长按备选的那个键不显示气泡。
    let hiddenKey: String?
    let uppercase: Bool
    let containerWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(keys.filter { presses.pressed.contains($0.id) && $0.kind.typesCharacter && $0.id != hiddenKey }) { key in
                KeyPopup(key: key, uppercase: uppercase, containerWidth: containerWidth)
            }
        }
    }
}

/// 一个按键的外观。
struct KeyCapView: View, Equatable {
    let context: KeyCapContext
    let key: KeySpec
    let pressed: Bool

    var body: some View {
        KeyCap(fill: fill(pressed: pressed), insetX: key.insetX, insetY: key.insetY) {
            label
                .foregroundStyle(foreground)
                .opacity(context.trackpadActive ? 0 : 1)
        }
    }

    private var returnLook: KeyboardModel.ReturnLook? {
        if case .returnKey = key.kind { return context.returnLook }
        return nil
    }

    private var highlighted: Bool { returnLook?.solid == true }

    /// iOS 26 键盘：所有键同色，按下变灰；带气泡的键按下时键帽不变色，气泡代替反馈。回车键浅紫或实心紫。
    private func fill(pressed: Bool) -> Color {
        if let look = returnLook {
            return look.solid ? Brand.purple.opacity(pressed ? 0.75 : 1) : Brand.returnSoftFill.opacity(pressed ? 0.7 : 1)
        }
        let showsPopup = key.kind.typesCharacter && !context.nineGrid
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
            Text(context.shift == .off ? letter : letter.uppercased())
                .font(KeyStyle.letterFont)
                .offset(y: -1)
        case .symbol(let symbol):
            if context.layer == .digits {
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
            if context.digitsMore {
                Text("返回").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.deepPurple)
            } else {
                Text("更多").font(KeyStyle.nineKeyFont)
            }
        case .nine(let digit):
            if digit == "'" {
                // 打拼音时是分词键，平时连按切换标点。
                if context.composing {
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
            Image(systemName: context.shift == .locked ? "capslock.fill" : (context.shift == .on ? "shift.fill" : "shift"))
                .font(KeyStyle.iconFont)
        case .delete:
            Image(systemName: "delete.left").font(KeyStyle.iconFont)
        case .space:
            spaceLabel
        case .returnKey:
            let look = context.returnLook
            if let title = look.title {
                Text(title).font(.system(size: 17, weight: look.bold ? .semibold : .regular))
            } else {
                Image(systemName: "return.left").font(KeyStyle.iconFont)
            }
        case .toggleChinese:
            // 九宫格只用于中文，永远是「中」加深。
            // 字号跟着键所在的排法走：数字符号页是全键盘那种底栏，即使从九宫格进来也用全键盘的字号。
            ToggleLabel(chinese: context.showsNineKey || context.chineseMode,
                        size: context.nineGrid ? KeyboardMetrics.nineToggleFontSize : KeyboardMetrics.toggleFontSize)
        case .globe:
            Image(systemName: "globe").font(KeyStyle.iconFont)
        case .emoticon:
            if context.composing {
                Text("重输").font(KeyStyle.functionFont)
            } else {
                // 「^^」字形偏上，往下挪一点视觉上才居中。
                Text("^^").font(KeyStyle.nineKeyFont).tracking(1).offset(y: 4)
            }
        case .emoji:
            Image(systemName: "face.smiling").font(KeyStyle.iconFont)
        case .quickWords:
            Text("常用").font(KeyStyle.nineKeyFont).tracking(1)
        case .layer(let target):
            if context.nineGrid {
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
        let title = context.spaceTitle
        return Text(title).font(KeyStyle.functionFont)
            .tracking(title == "空格" ? (context.showsNineKey ? 3 : 4) : 0)
    }

    private func layerTitle(_ target: KeyboardModel.KeyLayer) -> String {
        switch target {
        case .numbers: return "123"
        case .symbols: return "#+="
        case .digits: return "123"
        case .letters: return context.chineseMode || context.showsNineKey ? "拼音" : "ABC"
        }
    }
}

/// 「中/英」：当前语言那个字加深，另一个浅灰，斜杠更浅。
/// 两个字用同一个字重，只靠颜色区分：一粗一细时两边看着大小不一样，切换时字形也会跳。
struct ToggleLabel: View {
    var chinese: Bool
    var size: CGFloat

    var body: some View {
        // 斜杠往「中」挪 1pt、「英」跟着挪 0.5pt（左右间距 2/2 → 1/2.5），抵消斜杠倾斜后看着偏「英」。
        let font = Font.system(size: size, weight: .medium)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("中").font(font)
                .foregroundColor(chinese ? Brand.toggleActive : Brand.toggleInactive)
            Text("/").font(font).foregroundColor(Brand.toggleSlash)
                .padding(.leading, -1)
            Text("英").font(font)
                .foregroundColor(chinese ? Brand.toggleInactive : Brand.toggleActive)
                .padding(.leading, 0.5)
        }
    }
}

/// 九宫格第一格的标点「，。?!」：四个符号按设计稿 nine-key-punct-label.svg 一起画，
/// 笔画粗细、点的大小和间距统一，底线和旁边 16pt 的「123」「ABC」对齐。
/// 画成 Shape、颜色跟着前景色：之前用 Canvas，在别的 App 里打开键盘时整个画不出来（键帽空白）。
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
        GlyphPieces(pieces: PunctuationShape.pieces, transform: CGAffineTransform(scaleX: Self.scale, y: Self.scale).translatedBy(x: 0.5, y: 0))
            .frame(width: Self.size.width, height: Self.size.height)
            .offset(y: Self.baselineShift)
            .accessibilityLabel("标点")
    }
}

/// 笔画都转成轮廓（strokedPath），每一笔单独填色，重叠处不会因为绕向相反而镂空。
private struct GlyphPieces: View {
    let pieces: [Path]
    var transform: CGAffineTransform = .identity

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pieces.indices, id: \.self) { index in
                PieceShape(path: pieces[index].applying(transform))
            }
        }
    }
}

private struct PieceShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

private func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

private func roundStroke(_ path: Path, _ width: CGFloat) -> Path {
    path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

private enum PunctuationShape {
    static let pieces: [Path] = {
        var pieces: [Path] = []
        // ，
        pieces.append(dot(1.5, 13.4, 1.5))
        var tail = Path()
        tail.move(to: CGPoint(x: 2.9, y: 13.6))
        tail.addCurve(to: CGPoint(x: 0.6, y: 17.5), control1: CGPoint(x: 3.0, y: 15.5), control2: CGPoint(x: 2.2, y: 16.8))
        pieces.append(roundStroke(tail, 1.2))
        // 。
        pieces.append(dot(8.8 + 2.2, 12.85, 2.15).strokedPath(StrokeStyle(lineWidth: 1.3)))
        // ?
        var question = Path()
        let qx: CGFloat = 17.4
        question.move(to: CGPoint(x: qx + 0.8, y: 6.3))
        question.addCurve(to: CGPoint(x: qx + 3.9, y: 3.2), control1: CGPoint(x: qx + 0.8, y: 4.4), control2: CGPoint(x: qx + 2.1, y: 3.2))
        question.addCurve(to: CGPoint(x: qx + 7, y: 6.1), control1: CGPoint(x: qx + 5.7, y: 3.2), control2: CGPoint(x: qx + 7, y: 4.4))
        question.addCurve(to: CGPoint(x: qx + 4.9, y: 9.1), control1: CGPoint(x: qx + 7, y: 7.7), control2: CGPoint(x: qx + 5.9, y: 8.4))
        question.addCurve(to: CGPoint(x: qx + 3.9, y: 11.1), control1: CGPoint(x: qx + 4.2, y: 9.6), control2: CGPoint(x: qx + 3.9, y: 10.1))
        question.addLine(to: CGPoint(x: qx + 3.9, y: 11.7))
        pieces.append(roundStroke(question, 1.6))
        pieces.append(dot(qx + 3.9, 14, 1.05))
        // !
        var bang = Path()
        bang.move(to: CGPoint(x: 29.4 + 1.05, y: 3.6))
        bang.addLine(to: CGPoint(x: 29.4 + 1.05, y: 11.2))
        pieces.append(roundStroke(bang, 1.7))
        pieces.append(dot(29.4 + 1.05, 14, 1.05))
        return pieces
    }()
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
/// 三个符号上下对齐，底端落在同一行 ?! . 的底线上（键中心往下约 7pt）。和九宫格标点一样画成 Shape，颜色跟着前景色。
struct ChinesePunctMark: View {
    enum Kind: String { case comma = "，", period = "。", dun = "、" }
    let kind: Kind

    var body: some View {
        GlyphPieces(pieces: ChinesePunctShape.pieces(kind))
            .frame(width: 24, height: 24)
            .accessibilityLabel(kind.rawValue)
    }
}

private enum ChinesePunctShape {
    static func pieces(_ kind: ChinesePunctMark.Kind) -> [Path] {
        var pieces: [Path] = []
        switch kind {
        case .period:
            pieces.append(Path(ellipseIn: CGRect(x: 12 - 1.62, y: 17.05 - 1.62, width: 3.24, height: 3.24))
                .strokedPath(StrokeStyle(lineWidth: 1.15)))
        case .comma:
            pieces.append(Path(ellipseIn: CGRect(x: 11.55 - 1.3, y: 16.15 - 1.3, width: 2.6, height: 2.6)))
            var tail = Path()
            tail.move(to: CGPoint(x: 12.8, y: 16.3))
            tail.addCurve(to: CGPoint(x: 11.05, y: 19.05),
                          control1: CGPoint(x: 12.9, y: 17.55), control2: CGPoint(x: 12.35, y: 18.45))
            pieces.append(roundStroke(tail, 1.2))
        case .dun:
            var stroke = Path()
            stroke.move(to: CGPoint(x: 10.95, y: 15.6))
            stroke.addCurve(to: CGPoint(x: 13.05, y: 18.5),
                            control1: CGPoint(x: 11.85, y: 16.2), control2: CGPoint(x: 12.55, y: 17.1))
            pieces.append(roundStroke(stroke, 1.5))
        }
        return pieces
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
    let key: KeySpec
    let uppercase: Bool
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
        case .letter(let letter): return uppercase ? letter.uppercased() : letter
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
/// 每格最小 64pt；长词按字数占两三格甚至整行，不截断成省略号（排法见 CandidateRows）。
struct CandidateGrid: View {
    @ObservedObject var model: KeyboardModel
    /// 左边让给九宫格拼音栏的宽度。
    var leading: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(CandidateRows.rows(model.candidates, width: geo.size.width)) { row in
                            HStack(spacing: 0) {
                                ForEach(row.cells, id: \.index) { cell in
                                    Button { model.selectCandidate(cell.index) } label: {
                                        Text(cell.word)
                                            .font(.system(size: CandidateRows.fontSize))
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .padding(.horizontal, CandidateRows.padding)
                                            .frame(width: cell.width)
                                            .frame(minHeight: 46)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(KeyPressStyle())
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(.leading, leading)
            .frame(maxWidth: .infinity)
            .hidingScrollEdgeEffect()
            // 平时只取了第一屏候选，展开整页时补全；展开着选拼音、分段选词后候选换了，也再补全。
            .onAppear { model.loadMoreCandidates() }
            .onChange(of: model.composition) { _ in model.loadMoreCandidates() }
            // 收起用候选栏右边的箭头；这里只放退格和重输，上下平分整列。
            VStack(spacing: 0) {
                RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                    .frame(maxHeight: .infinity)
                FunctionKey(title: "重输") { model.clearComposition() }
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 64)
            .frame(maxHeight: .infinity)
        }
    }
}


/// 展开候选的排法：先按一格 64pt 算出一行几格，每个词按自己的宽度占整数格，放不下就换行；
/// 换行前把这一行按比例拉宽到撑满（最后一行不拉，靠左）。
enum CandidateRows {
    static let fontSize: CGFloat = 20
    static let padding: CGFloat = 6
    private static let minimumCell: CGFloat = 64
    private static let font = UIFont.systemFont(ofSize: fontSize)
    private static var widthCache: [String: CGFloat] = [:]

    struct Cell {
        let index: Int
        let word: String
        let width: CGFloat
    }

    struct Row: Identifiable {
        let id: Int
        let cells: [Cell]
    }

    static func rows(_ words: [String], width: CGFloat) -> [Row] {
        guard width > 0 else { return [] }
        let columns = max(1, Int(width / minimumCell))
        let unit = width / CGFloat(columns)
        var rows: [Row] = []
        var pending: [(index: Int, word: String, span: Int)] = []
        var used = 0
        func flush(stretch: Bool) {
            guard !pending.isEmpty else { return }
            let scale = stretch ? CGFloat(columns) / CGFloat(used) : 1
            rows.append(Row(id: pending[0].index, cells: pending.map {
                Cell(index: $0.index, word: $0.word, width: floor(CGFloat($0.span) * unit * scale))
            }))
            pending = []
            used = 0
        }
        for (index, word) in words.enumerated() {
            let span = min(columns, max(1, Int(ceil(textWidth(word) / unit))))
            if used + span > columns { flush(stretch: true) }
            pending.append((index, word, span))
            used += span
        }
        flush(stretch: false)
        return rows
    }

    private static func textWidth(_ word: String) -> CGFloat {
        if let cached = widthCache[word] { return cached }
        if widthCache.count > 1000 { widthCache.removeAll() }
        let width = ceil((word as NSString).size(withAttributes: [.font: font]).width) + padding * 2
        widthCache[word] = width
        return width
    }
}

/// 长按「中/英」的拼音布局菜单（P11）：白底圆角 12、柔和投影；选中项淡紫底深紫字加勾；按住的键描紫边。
struct LayoutMenuView: View {
    let menu: LayoutMenuPopup

    var body: some View {
        let frame = menu.frame
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255), lineWidth: 2)
                .frame(width: menu.key.cap.width, height: menu.key.cap.height)
                .offset(x: menu.key.cap.minX, y: menu.key.cap.minY)
            VStack(alignment: .leading, spacing: 0) {
                title(L("拼音布局", "Pinyin layout", "ピンインの配列"))
                ForEach(0..<2, id: \.self) { row($0) }
                Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                    .padding(.vertical, (LayoutMenuPopup.dividerHeight - 0.5) / 2)
                    .padding(.horizontal, 4)
                title(L("拼音显示", "Pinyin display", "ピンインの表示"))
                ForEach(2..<4, id: \.self) { row($0) }
            }
            .padding(LayoutMenuPopup.padding)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.panelFill)
                .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18), radius: 12, y: 8))
            .offset(x: frame.minX, y: frame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
            .padding(.leading, 10)
            .frame(height: LayoutMenuPopup.titleHeight, alignment: .center)
    }

    private func row(_ index: Int) -> some View {
        let option = LayoutMenuPopup.options[index]
        let selected = menu.isChecked(option)
        let name: String
        switch option {
        case .layout(let layout): name = layout == .nineKey ? L("九宫格", "10-key", "10キー") : L("全键盘", "QWERTY", "QWERTY")
        case .display(let display): name = display.title
        }
        return HStack {
            Text(name).font(.system(size: 15, weight: selected ? .semibold : .regular))
            Spacer()
            if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)) }
        }
        .foregroundStyle(selected ? Brand.deepPurple : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: LayoutMenuPopup.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Brand.returnSoftFill : Color.clear))
    }
}
