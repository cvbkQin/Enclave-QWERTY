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
                } else if model.candidatesExpanded {
                    // 拼音在上方一行时那一行展开时也留着，整页候选铺满按键区；
                    // 在侧边（F12）时九宫格左边的拼音列保持住、拉长到 4 行，候选铺在中间三列。
                    let column = model.pinyinSide && model.showsNineKey ? layout.pinyinColumn : nil
                    // 和系统键盘一样：从候选栏下面往下拉开，收起时往上卷回去（见 CandidateReveal）。
                    CandidateGrid(model: model, leading: column?.maxX ?? 0)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.modifier(active: CandidateReveal(progress: 0), identity: CandidateReveal(progress: 1)))
                    // 拼音列不跟着卷：按键页那份和这份同一刻换掉，开收途中不会叠出两列。
                    if let column {
                        SidePinyinColumn(model: model, frame: CGRect(x: column.minX, y: column.minY,
                                                                     width: column.width, height: column.height / 3 * 4))
                            .transition(.identity)
                    }
                } else {
                    ForEach(layout.keys) { key in
                        KeyCapCell(presses: model.keyPresses, context: context, key: key)
                            .frame(width: key.visual.width, height: key.visual.height)
                            .offset(x: key.visual.minX, y: key.visual.minY)
                            // 帮回键的外圈画在键外，压在旁边键上面。zIndex 1 会把它抬到下面的触摸层上面，
                            // 键帽自己就接住了点按（0.96_5、0.96_6 点帮回没反应），所以这颗键帽不接触摸，点按还交给触摸层。
                            .zIndex(key.kind == .emoticon ? 1 : 0)
                            .allowsHitTesting(key.kind != .emoticon)
                    }
                    KeyTouchLayer(model: model, layout: layout)
                        .frame(width: geo.size.width, height: geo.size.height)
                    if let column = layout.pinyinColumn {
                        SidePinyinColumn(model: model, frame: column)
                            .transition(.identity)
                    }
                    if let column = layout.operatorColumn {
                        OperatorColumn(model: model, frame: column)
                    }
                    // 横屏九宫格中间那块（LN1）：AI 栏 + 联想 / 候选 / 结果卡。放在长按十字下面，十字伸过来时盖得住。
                    if let middle = layout.middle {
                        LandscapeNineMiddle(model: model)
                            .frame(width: middle.width, height: middle.height)
                            .offset(x: middle.minX, y: middle.minY)
                    }
                    // iPad 全宽 9 键（PK3、PK4）：功能键一列和中间的联想 / 候选。
                    if let rect = layout.padFunctions {
                        PadNineFunctions(model: model, nineOnLeft: model.settings.nineKeySide == .left)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    if let rect = layout.padMiddle {
                        PadNineMiddle(model: model)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                    // 字符键按下时的放大气泡（九宫格和系统一样不显示；弹出长按备选、「，。」键往上划出十字时也不显示）。
                    // iPad 全宽键盘也和原生一样不显示，按下的键变灰。
                    if !model.nineGrid && model.pad == nil {
                        KeyPopupLayer(presses: model.keyPresses, keys: layout.keys, hiddenKey: model.alternates?.key.id ?? model.cross?.key.id,
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
                    if let popup = model.enterCross, let ai = context.returnLook.ai {
                        EnterCrossView(popup: popup, ai: ai)
                    }
                    if let menu = model.layoutMenu {
                        LayoutMenuView(menu: menu)
                    }
                }
            }
        }
        .frame(height: KeyboardMetrics.keysHeight)
        // 「★ 已加到常用语…」「只能粘贴文字」这类小提示：盖在按键区顶上，不挡手指。
        .overlay(alignment: .top) {
            if let toast = model.keysToast {
                KeysToast(text: toast).padding(.top, 4).transition(.opacity).allowsHitTesting(false)
            }
        }
    }
}

/// 按键区顶上的深色小胶囊，样子和自由编辑的提示一样。
struct KeysToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Brand.candidateMenuText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Brand.candidateMenuFill))
            .shadow(color: .black.opacity(0.22), radius: 9, y: 6)
            .padding(.horizontal, 12)
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
    /// 双拼时字母键上写韵母小字（SP1）；不写时为 nil。
    var hintScheme: DoublePinyin? = nil
    /// 写哪些小字：固定档总是 .all；「跟着按键变」档按已打的键变（只有这一档会随每次按键重画键帽）。
    var hintPhase: DoublePinyin.HintPhase = .all
    /// 「跟着按键变」里写深一点、排在前面的（练习里老按错的，SP10）。
    var hintWeak: Set<String> = []
}

extension KeyboardModel {
    var keyCapContext: KeyCapContext {
        KeyCapContext(shift: shift, layer: layer, composing: isComposing, nineGrid: nineGrid, showsNineKey: showsNineKey,
                      chineseMode: chineseMode, digitsMore: digitsMore, trackpadActive: trackpadActive,
                      spaceTitle: spaceTitle, returnLook: returnLook, hintScheme: keyHintScheme, hintPhase: keyHintPhase,
                      hintWeak: keyHintPhase == .all ? [] : doublePinyinWeakUnits)
    }

    /// 只在全键盘中文、字母页、没按 shift、键上提示没关时写（全拼、九宫格、英文都不写）。
    private var keyHintScheme: DoublePinyin? {
        guard let doublePinyin, settings.doublePinyinHintMode != .off, chineseMode, !showsNineKey, layer == .letters, shift == .off
        else { return nil }
        return doublePinyin
    }

    /// 「跟着按键变」：分段选过的字后面的键两两配对，最后单下一个键就是该按韵母。
    private var keyHintPhase: DoublePinyin.HintPhase {
        guard settings.doublePinyinHintMode == .dynamic, keyHintScheme != nil else { return .all }
        if practiceActive { return practiceContextPhase }
        guard isComposing else { return .initial }
        return DoublePinyin.hintPhase(raw: engine.rawInput, from: engine.selections.last?.end ?? 0)
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
        if let ai = returnLook?.ai {
            // 回答卡展开、焦点在识意框：三段式识意（第 70 条）。
            EnterAskKey(ai: ai, pressed: pressed)
                .opacity(context.trackpadActive ? 0 : 1)
                .padding(.horizontal, key.insetX)
                .padding(.vertical, key.insetY)
                .contentShape(Rectangle())
        } else {
            KeyCap(fill: fill(pressed: pressed), insetX: key.insetX, insetY: key.insetY) {
                label
                    .foregroundStyle(foreground)
                    .opacity(context.trackpadActive ? 0 : 1)
            }
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
        let showsPopup = key.kind.typesCharacter && !context.nineGrid && KeyboardMetrics.pad == nil
        // iPad 全宽键盘的功能键是灰底（PK1），按下和 ⇧ 打开时变白，和原生一样。
        if KeyboardMetrics.pad != nil, key.kind.isPadFunction {
            let lit = pressed || (key.kind == .shift && context.shift != .off)
            return lit ? KeyStyle.charKey : KeyStyle.padFunctionKey
        }
        if pressed && !showsPopup { return KeyStyle.pressedKey }
        // 「跟着按键变」拼不上的键：键底往键盘底色压一点（SP7 约 30%）。
        return dimmed ? KeyStyle.charKey.opacity(0.7) : KeyStyle.charKey
    }

    /// 双拼「跟着按键变」该按韵母时，和前一个键拼不上的字母键（SP7）。
    private var dimmed: Bool {
        guard case .letter(let letter) = key.kind, let scheme = context.hintScheme, let char = letter.first else { return false }
        return !scheme.keyFits(char, in: context.hintPhase)
    }

    private var foreground: Color {
        if let look = returnLook { return look.solid ? .white : Brand.deepPurple }
        return .primary
    }

    @ViewBuilder
    private var label: some View {
        switch key.kind {
        case .letter(let letter):
            // 开着双拼提示时所有字母键一个排法（字母贴下边），没有韵母小字的键（小鹤、自然码的 a、e）上面空着，
            // 不再单独居中放大，免得和别的键对不齐（11-16 用户反馈）。
            if let scheme = context.hintScheme {
                DoublePinyinKeyLabel(letter: letter, lines: scheme.hints(for: context.hintPhase)[Character(letter)] ?? [], dimmed: dimmed,
                                     weak: context.hintWeak)
            } else {
                Text(context.shift == .off ? letter : letter.uppercased())
                    .font(KeyStyle.letterFont)
                    .offset(y: -1)
            }
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
        case .quickPunct(let chinese):
            QuickPunctLabel(chinese: chinese)
        case .padSymbol(let base, let shifted):
            PadSymbolLabel(base: base, shifted: shifted)
        case .tab:
            Image(systemName: "arrow.right.to.line").font(KeyStyle.iconFont)
        case .dismiss:
            Image(systemName: "keyboard.chevron.compact.down").font(KeyStyle.iconFont)
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
                Text(title).font(.system(size: KeyboardMetrics.pad?.functionFontSize ?? 17, weight: look.bold ? .semibold : .regular))
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
            QuickKeyLabel()
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
        // iPad 的数字符号页（PK9）回字母写 ABC，和原生一样。
        // iPad 9 键数字页（PK9 右）左下是「返回」。
        case .letters:
            if KeyboardMetrics.pad != nil { return context.nineGrid ? "返回" : "ABC" }
            // iPad 浮动 9 键数字页（PK14）左下也是「返回」。
            if KeyboardMetrics.floating && context.nineGrid { return "返回" }
            return context.chineseMode || context.showsNineKey ? "拼音" : "ABC"
        }
    }
}

extension KeyKind {
    /// iPad 全宽键盘上灰底的功能键（PK1 --fn）。空格、回车、「，。」和字符键是白的。
    var isPadFunction: Bool {
        switch self {
        // 9 键（PK3）的「常用」「^^」也是灰的。
        case .tab, .delete, .toggleChinese, .shift, .globe, .layer, .emoji, .dismiss, .quickWords, .emoticon: return true
        default: return false
        }
    }
}

/// iPad 的标点、数字键（PK2）：上面灰色小字是按 ⇧ 出的，下面是平时打的。全角 ，。、：； 画成居中的字形（CenteredGlyph），
/// 视觉上在键帽正中，不偏左下（11-22 cvbk「注意里面文字的大小居中（视觉上）」）。
struct PadSymbolLabel: View {
    let base: String
    let shifted: String

    private static let centered: Set<String> = ["，", "。", "、", "：", "；", "‘", "“"]

    var body: some View {
        let size = KeyboardMetrics.pad?.fontSize ?? 22
        VStack(spacing: 1) {
            glyph(shifted, size: (size * 0.55).rounded())
                .foregroundStyle(.secondary)
            glyph(base, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(base)
    }

    @ViewBuilder
    private func glyph(_ text: String, size: CGFloat) -> some View {
        if Self.centered.contains(text) {
            CenteredGlyph(text, size: size)
        } else {
            Text(text == "……" ? "…" : text).font(.system(size: size))
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

/// 全键盘空格旁的「，。」键（PU2）：大字逗号居中偏下，左上角小灰字句号，提示可以往上划。英文时是「,」和「.」。
struct QuickPunctLabel: View {
    let chinese: Bool

    var body: some View {
        // 横屏键只有 32 高，小字往里收一点，不贴键帽上沿。
        let landscape = KeyboardMetrics.landscape
        if let pad = KeyboardMetrics.pad {
            // iPad（PK1）：「，」在键帽正中，「。」小字在左上。
            ZStack {
                if chinese {
                    CenteredGlyph("，", size: pad.fontSize)
                } else {
                    Text(",").font(KeyStyle.symbolFont)
                }
                CenteredGlyph(QuickPunct.up(chinese: chinese), size: (pad.fontSize * 0.5).rounded())
                    .foregroundStyle(.secondary)
                    .offset(x: -(pad.fontSize * 0.45).rounded(), y: -(pad.fontSize * 0.5).rounded())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chinese ? "，。" : ",.")
        } else {
            ZStack {
                if chinese {
                    ChinesePunctMark(kind: .comma)
                } else {
                    Text(",").font(KeyStyle.symbolFont)
                }
                CenteredGlyph(QuickPunct.up(chinese: chinese), size: landscape ? 10 : 11)
                    .foregroundStyle(.secondary)
                    .offset(x: -9, y: landscape ? -8 : -11)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chinese ? "，。" : ",.")
        }
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
        case .quickPunct(let chinese): return QuickPunct.tap(chinese: chinese)
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

/// 展开整页候选的开收：像卷帘一样从顶上往下露出来（收起时往上卷回去），内容跟着往下滑一小段、淡入。
/// 只在点候选栏箭头时带动画（KeyboardView 里 withAnimation），选词、打字时收起直接切换。
struct CandidateReveal: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: -18 * (1 - progress))
            .opacity(Double(min(1, progress * 1.6)))
            .mask(alignment: .top) {
                GeometryReader { geo in
                    Rectangle().frame(height: geo.size.height * progress + 18 * (1 - progress))
                }
            }
    }
}

/// 候选词展开后铺满按键区，和系统键盘一样可以上下滑着挑。
/// 每格最小 64pt；长词按字数占两三格甚至整行，不截断成省略号（排法见 CandidateRows）。
/// iPad 全宽 26 键（PK5 中）：候选放在一张白底圆角卡里，和按键一样离边；一格最小 86（11 寸横屏一行 12 个、竖屏 8 个），
/// 一排的高度把按键区分成字母页那么多排（11 寸 4 排、13 寸 5 排），排间细线；右边一列 ⌫、重输、确认，和功能键一样灰底。
struct CandidateGrid: View {
    @ObservedObject var model: KeyboardModel
    /// 左边让给九宫格拼音栏的宽度。
    var leading: CGFloat = 0

    var body: some View {
        let pad = KeyboardMetrics.pad
        let half = (pad?.gap ?? 0) / 2
        let fontSize = pad.map { $0.fontSize - 2 } ?? CandidateRows.fontSize
        let shape = RoundedRectangle(cornerRadius: pad == nil ? 0 : KeyStyle.cornerRadius, style: .continuous)
        HStack(alignment: .top, spacing: 0) {
            GeometryReader { geo in
                let rowHeight = pad.map { geo.size.height / CGFloat($0.rows) } ?? 46
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(CandidateRows.rows(model.displayWords(model.candidates), width: geo.size.width,
                                                   minimumCell: pad == nil ? (KeyboardMetrics.floating ? 50 : 64) : 86,
                                                   fontSize: fontSize)) { row in
                            HStack(spacing: 0) {
                                ForEach(row.cells, id: \.index) { cell in
                                    Button { model.selectCandidate(cell.index) } label: {
                                        Text(cell.word)
                                            .font(.system(size: fontSize))
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                            .padding(.horizontal, CandidateRows.padding)
                                            .frame(width: cell.width)
                                            .frame(minHeight: rowHeight)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(KeyPressStyle())
                                }
                                Spacer(minLength: 0)
                            }
                            .overlay(alignment: .bottom) {
                                if pad != nil { Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5) }
                            }
                        }
                    }
                }
            }
            .background(shape.fill(pad == nil ? Color.clear : KeyStyle.charKey))
            .clipShape(shape)
            .padding(half)
            .padding(.leading, leading)
            .frame(maxWidth: .infinity)
            .hidingScrollEdgeEffect()
            // 候选换了（补全、选拼音）时格子直接换，不跟着开收的动画一格格飞（会看到字往别的格子挪）。
            .transaction { $0.animation = nil }
            // 平时只取了第一屏候选（30 个，够铺满第一屏），展开整页时补全；放到展开动画之后再取，取的时候主线程要等引擎，
            // 放在出现的那一下会卡住动画、连点箭头也像没反应。展开着选拼音、分段选词后候选换了，也再补全。
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak model] in
                    guard let model, model.candidatesExpanded else { return }
                    model.loadMoreCandidates()
                }
            }
            .onChange(of: model.composition) { _ in model.loadMoreCandidates() }
            if let pad {
                padSideColumn(pad)
            } else {
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
        // iPad：上下和按键一样离边（按键格子从 top − gap/2 起，键帽再缩进半条缝）。
        .padding(.top, pad.map { $0.top - $0.gap / 2 } ?? 0)
        .padding(.bottom, pad.map { $0.bottom - $0.gap / 2 } ?? 0)
    }

    /// iPad 右边一列（PK5 中）：⌫、重输、确认（把字母原样上屏，浅紫底紫字，和打字中的回车一样），三颗一样高。
    private func padSideColumn(_ pad: PadMetrics) -> some View {
        let half = pad.gap / 2
        return VStack(spacing: 0) {
            RepeatingKey(systemImage: "delete.left", insetX: half, insetY: half, fill: KeyStyle.padFunctionKey) { model.deleteKey() }
                .frame(maxHeight: .infinity)
            Button { model.clearComposition() } label: {
                KeyCap(fill: KeyStyle.padFunctionKey, insetX: half, insetY: half) {
                    Text("重输").font(KeyStyle.functionFont).foregroundStyle(Color.primary)
                }
            }
            .buttonStyle(KeyPressStyle())
            .frame(maxHeight: .infinity)
            Button { if model.isComposing { model.returnKey() } } label: {
                KeyCap(fill: Brand.returnSoftFill, insetX: half, insetY: half) {
                    Text("确认").font(KeyStyle.functionFont).foregroundStyle(Brand.deepPurple)
                }
            }
            .buttonStyle(KeyPressStyle())
            .frame(maxHeight: .infinity)
        }
        .frame(width: pad.landscape ? 120 : 96)
        .frame(maxHeight: .infinity)
    }
}


/// 展开候选的排法：先按一格 64pt 算出一行几格，每个词按自己的宽度占整数格，放不下就换行；
/// 换行前把这一行按比例拉宽到撑满（最后一行不拉，靠左）。
enum CandidateRows {
    static let fontSize: CGFloat = 20
    static let padding: CGFloat = 6
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

    /// minimumCell、fontSize：iPad 上格子和字都大一点（展开候选 86、9 键中间那块 52 / 58），量字宽用同一个字号。
    static func rows(_ words: [String], width: CGFloat, minimumCell: CGFloat = 64, fontSize: CGFloat = CandidateRows.fontSize) -> [Row] {
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
            let span = min(columns, max(1, Int(ceil(textWidth(word, fontSize: fontSize) / unit))))
            if used + span > columns { flush(stretch: true) }
            pending.append((index, word, span))
            used += span
        }
        flush(stretch: false)
        return rows
    }

    private static func textWidth(_ word: String, fontSize: CGFloat) -> CGFloat {
        let key = fontSize == Self.fontSize ? word : "\(fontSize)|\(word)"
        if let cached = widthCache[key] { return cached }
        if widthCache.count > 1000 { widthCache.removeAll() }
        let font = UIFont.systemFont(ofSize: fontSize)
        let width = ceil((word as NSString).size(withAttributes: [.font: font]).width) + padding * 2
        widthCache[key] = width
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

/// 九宫格左列「常 用 / 剪贴板」（对齐清单第 62 条，CW1 方案 a）：两行同字号 14.5pt、同颜色；
/// 「常 用」两字两端对齐到和「剪贴板」一样宽（3 个字宽），两行整体在键里居中，行高 1.25。剪贴板有新内容不再出紫点。
struct QuickKeyLabel: View {
    private static let size: CGFloat = 14.5

    var body: some View {
        VStack(spacing: Self.size * 0.25 - 2) {
            HStack(spacing: 0) {
                Text("常")
                Spacer(minLength: 0)
                Text("用")
            }
            .frame(width: Self.size * 3)
            Text("剪贴板")
        }
        .font(.system(size: Self.size))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("常用和剪贴板", "Phrases and clipboard", "定型文とクリップボード"))
    }
}

/// 双拼键上的提示（SP2 样式 A）：韵母小字在键帽上方居中，离顶 3pt，最多两行；zh/ch/sh 主题紫、加粗，排第一行。
/// 有小字的键字母缩小一点、贴下边，和小字不挤。按下时的气泡只放大字母（KeyPopup 不变）。
struct DoublePinyinKeyLabel: View {
    let letter: String
    let lines: [String]
    /// 「跟着按键变」拼不上的键：字母透明度 28%（SP7）。
    var dimmed = false
    /// 练习里老按错的韵母（和 zh / ch / sh）：排在前面、字深一点（SP10）。
    var weak: Set<String> = []

    /// 小字和字母都挂在键上（overlay），不撑键的高度：以前是 VStack，两行小字的键（s、k、l、x、v）比键高，
    /// 竖屏往下伸出来、和别的键对不齐（T18，IMG_2005）；横屏键只有 29 高，撑得更多，整排错位、互相压住（IMG_2006）。
    /// 按键高 43（横屏 32）排：竖屏两行时小字小一号；横屏只留一行小字。
    var body: some View {
        let style = Self.style(lines: shownLines.count, landscape: KeyboardMetrics.landscape)
        Color.clear
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(shownLines, id: \.self) { line in
                        let initial = ["zh", "ch", "sh"].contains(line)
                        let isWeak = weak.contains(line)
                        Text(line)
                            .font(.system(size: style.hintSize, weight: initial || isWeak ? .bold : .medium))
                            .foregroundStyle(initial ? Brand.purpleText : isWeak ? Color.primary : Color.secondary)
                            .frame(height: style.hintLine)
                    }
                }
                .padding(.top, style.top)
            }
            .overlay(alignment: .bottom) {
                Text(letter)
                    .font(.system(size: style.letterSize))
                    .opacity(dimmed ? 0.28 : 1)
                    .padding(.bottom, style.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Style {
        var hintSize: CGFloat, hintLine: CGFloat, top: CGFloat, letterSize: CGFloat, bottom: CGFloat
    }

    /// 字母大小、离底边的距离每个键都一样（同一排对得齐）；只有小字的排法看行数。
    /// 竖屏键高 43：字母 21 离底 2.5，基线约在 36，l、k 的头顶约 21。一行小字 3 + 8.6；两行小一号 2 + 8×2 = 18，不碰字母。
    /// 横屏键高 32（LN2）：照竖屏字母 19 贴下边、离底 1.5，头顶约 12；两行小字放不下，只留一行 1.5 + 7.5。
    private static func style(lines: Int, landscape: Bool) -> Style {
        if landscape { return Style(hintSize: 7, hintLine: 7.5, top: 1.5, letterSize: 19, bottom: 1.5) }
        if lines >= 2 { return Style(hintSize: 7.5, hintLine: 8, top: 2, letterSize: 21, bottom: 2.5) }
        return Style(hintSize: 8, hintLine: 8.6, top: 3, letterSize: 21, bottom: 2.5)
    }

    private var shownLines: [String] {
        let limit = KeyboardMetrics.landscape ? 1 : 2
        guard !weak.isEmpty else { return Array(lines.prefix(limit)) }
        return Array((lines.filter { weak.contains($0) } + lines.filter { !weak.contains($0) }).prefix(limit))
    }
}
