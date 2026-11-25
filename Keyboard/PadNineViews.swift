import SwiftUI

// iPad 全宽 9 键（PK3、PK4、PK6，11-22 定稿）：按键旁边那一块。按键的位置见 KeyLayout+PadNine。

/// 功能键一列（PK3 ①）：最上面回答卡开关，下面润色 ⌄、问答 ⌄、钉住的风格（多了上下滑、底部渐隐），最下面 ↶ ↷。
/// 九键在右时这一列在最左、靠左对齐；九键在左（PK4）时在最右、靠右对齐，回答卡开关左右镜像。
/// 打字时留在原位、变淡、点不了，键盘不跳；打完一个词恢复（PK3 右 ②）。⌄ 的下拉框往中间弹（KeyboardView）。
struct PadNineFunctions: View {
    @ObservedObject var model: KeyboardModel
    let nineOnLeft: Bool

    private static let fade: CGFloat = 18

    var body: some View {
        // 功能关掉或不能用时，它固定的风格键也不显示（和 AI 栏一样，QE）。
        let pins = model.settings.pinnedStyles.filter {
            model.debugUnblocked || ($0.answer ? model.settings.showsAnswerKey : model.settings.showsPolishKey)
        }
        let alignment: HorizontalAlignment = nineOnLeft ? .trailing : .leading
        let edge: Alignment = nineOnLeft ? .trailing : .leading
        VStack(alignment: alignment, spacing: 8) {
            PadCardToggle(model: model, mirrored: nineOnLeft)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: alignment, spacing: 8) {
                    if model.settings.showsPolishKey || model.debugUnblocked { StyleKey(model: model, row: .prompts) }
                    if model.settings.showsAnswerKey || model.debugUnblocked { StyleKey(model: model, row: .answerStyles) }
                    if model.helpKeyShown { HelpPopKey(model: model) }
                    ForEach(pins, id: \.style.id) { pin in
                        PinnedStyleKey(model: model, style: pin.style, answer: pin.answer)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge)
                // 最后一颗不压在渐隐里。
                .padding(.bottom, Self.fade)
            }
            .hidingScrollEdgeEffect()
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
            UndoRedoPair(model: model, fillWidth: KeyboardMetrics.pad?.landscape == true ? 94 : 86)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: nineOnLeft ? .topTrailing : .topLeading)
        .opacity(model.isComposing ? 0.4 : 1)
        .allowsHitTesting(!model.isComposing)
        .animation(.easeOut(duration: 0.15), value: model.isComposing)
    }
}

/// 回答卡开关（PK15）：▭ 在外侧（靠屏幕边）、箭头在内侧。卡片从键盘上面出来，所以没开时箭头朝上，开着时朝下（收回）；
/// 开着时浅紫底、紫边、紫图标，和 iPhone AI 栏最左边那颗一样。和润色键一样大（竖屏 86×32、横屏 94×36）。
struct PadCardToggle: View {
    @ObservedObject var model: KeyboardModel
    /// 九键在左：功能键一列在最右，▭ 在右边、箭头在左边。
    let mirrored: Bool

    var body: some View {
        let open = model.aiExpanded
        let hasNew = model.showsNewResult
        let width: CGFloat = KeyboardMetrics.pad?.landscape == true ? 94 : 86
        Button {
            model.endCoach()
            model.setAIExpanded(!open)
        } label: {
            HStack(spacing: 6) {
                if mirrored { arrow(open) }
                Image(systemName: "rectangle.tophalf.inset.filled")
                    .font(.system(size: 17, weight: .medium))
                if !mirrored { arrow(open) }
            }
            .foregroundStyle(open ? Brand.toggleOpenIcon : (hasNew ? Brand.newResultIcon : Color.primary))
            .frame(width: width, height: KeyboardMetrics.chipHeight)
            .background(Capsule().fill(open ? Brand.toggleOpenFill : KeyStyle.charKey))
            .overlay(Capsule().strokeBorder(Brand.toggleOpenStroke, lineWidth: open ? 1.5 : 0))
            .overlay(alignment: mirrored ? .topLeading : .topTrailing) {
                if hasNew {
                    Circle().fill(Brand.newResultDot)
                        .frame(width: 10, height: 10)
                        .padding(2)
                        .background(Circle().fill(Brand.keyboardBack))
                        .offset(x: mirrored ? -3 : 3, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(open ? L("收起结果", "Hide result", "結果を隠す") : L("展开结果", "Show result", "結果を表示"))
    }

    private func arrow(_ open: Bool) -> some View {
        Image(systemName: open ? "chevron.down" : "chevron.up")
            .font(.system(size: 12, weight: .semibold))
    }
}

/// 中间那块（PK3 ②、PK6）：平时 3 排联想（按宽度排满，格子拉伸到整排），刚弹出还没打字时空着；
/// 打字中 4 排候选，上下滑看更多，不用点 ⌄ 展开。拼音在上方一行时，第一排是拼音（ni hao ｜ ni mi n m），下面 3 排候选；
/// 在侧边时拼音在九键左列，这里 4 排都是候选。在卡片里改结果时（FE3）最上面是「正在修改」那一行。
/// 左列点了 123、#@¥、常用剪贴板时换成运算符号、符号、常用语和剪贴板（PK17、PK18），键盘不变高。
struct PadNineMiddle: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        GeometryReader { geo in
            let font = KeyboardMetrics.pad.map { $0.fontSize - 3 } ?? 20
            let cell: CGFloat = KeyboardMetrics.pad?.landscape == true ? 58 : 52
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            let keyFont = KeyboardMetrics.pad?.fontSize ?? 22
            if model.layer == .digits {
                // 123（PK17 第三张）：一格一个，竖屏一行 4 个、横屏 7 个左右。
                PadMiddleGrid(model: model, items: PadMiddleGrid.operators,
                              columns: max(4, Int(geo.size.width / 66)), fontSize: keyFont)
            } else if model.padMiddle == .symbols, !model.isComposing {
                // #@¥（PK17 第二张、PK18 左）：竖屏一行 5 个、横屏 8 个左右。
                PadMiddleGrid(model: model, items: PadMiddleGrid.symbols,
                              columns: max(5, Int(geo.size.width / 62)), fontSize: (keyFont * 0.92).rounded())
            } else if model.padMiddle == .quick, !model.isComposing {
                PadQuickMiddle(model: model)
            } else if model.isComposing {
                let rowHeight = geo.size.height / 4
                // 拼音那一行和候选在同一张白卡里（PK6），中间一条细线。
                VStack(spacing: 0) {
                    if !model.pinyinSide {
                        PinyinRow(model: model)
                            .frame(height: rowHeight)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                            }
                    } else if let pinyin = model.offFieldPinyin {
                        // 输入框不认标记文字（NM2）时拼音没处显示：候选上面加一行灰色拼音。
                        OffFieldPinyinText(text: pinyin, size: 15)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 24)
                    }
                    LandscapeWordPanel(model: model, words: model.displayWords(model.candidates), composing: true,
                                       rowHeight: rowHeight, fontSize: font, minimumCell: cell)
                }
                .background(shape.fill(KeyStyle.charKey))
                .clipShape(shape)
            } else {
                VStack(spacing: 6) {
                    if model.target == .card {
                        CardEditHint(model: model, inset: 0)
                            .frame(height: KeyboardMetrics.chipHeight + 8)
                    }
                    LandscapeWordPanel(model: model, words: model.showsPredictions ? model.displayWords(model.predictions) : [],
                                       composing: false, rowHeight: geo.size.height / 3, fontSize: font, minimumCell: cell)
                }
            }
        }
    }
}

/// iPad 9 键中间那块一格一个（PK17、PK18）：#@¥ 的符号、123 的运算符号。白卡、细线分格，露出 3 行多一点，
/// 上下滑看更多，最下面渐隐。点一个上屏，这块不收（再点左列那颗、或者按九键打字才回到联想）。
struct PadMiddleGrid: View {
    @ObservedObject var model: KeyboardModel
    let items: [String]
    let columns: Int
    let fontSize: CGFloat

    /// #@¥：中文标点在前，再是常用符号，内容和 iPhone 两页符号一样（PK17 第二张）。
    static let symbols = ["，", "。", "？", "！", "、", "：", "；", "“", "”", "（", "）", "《", "》", "…", "—", "·", "～",
                          "@", "#", "%", "&", "*", "+", "=", "-", "/", "＼", "|", "_", "<", ">", "【", "】", "{", "}",
                          "¥", "$", "€", "£", "^", "•", "‘", "’"]
    /// 123：运算符号和跟着数字打的符号（PK17 第三张）。
    static let operators = ["+", "−", "×", "÷", "=", "%", ".", ",", ":", "/", "-", "(", ")", "¥", "$", "€", "°", "~",
                            "#", "@", "^", "√", "π", "±"]

    /// 全角标点画在视觉正中（照 PadSymbolLabel）。
    private static let centered: Set<String> = ["，", "。", "、", "：", "；", "‘", "’", "“", "”", "（", "）"]
    private static let fade: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        GeometryReader { geo in
            let width = geo.size.width / CGFloat(max(columns, 1))
            // 露出 3 行，再露一点第 4 行，看得出还能往下滑。
            let rowHeight = geo.size.height / 3.35
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 0), count: max(columns, 1)), spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button {
                            model.keyFeedback(for: .symbol(item))
                            model.perform(.symbol(item))
                        } label: {
                            glyph(item)
                                .foregroundStyle(Color.primary)
                                .frame(width: width, height: rowHeight)
                                .overlay(alignment: .trailing) {
                                    if index % columns < columns - 1 {
                                        Rectangle().fill(Color(UIColor.separator)).frame(width: 0.5)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                        .accessibilityLabel(item)
                    }
                }
                .padding(.bottom, Self.fade)
            }
            .hidingScrollEdgeEffect()
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
        }
        .background(shape.fill(KeyStyle.charKey))
        .clipShape(shape)
    }

    @ViewBuilder
    private func glyph(_ text: String) -> some View {
        if Self.centered.contains(text) {
            CenteredGlyph(text, size: fontSize)
        } else {
            Text(text).font(.system(size: fontSize))
        }
    }
}

/// iPad 9 键中间那块的常用语和剪贴板（PK17 第四张、PK18 右）：上面两个标签「常用语 / 剪贴板」（高 32），
/// 下面一条一条，横屏常用语排两列。点常用语上屏；剪贴板点一条粘贴、长按菜单，都照 iPhone 的「常用 / 剪贴板」面板。
/// 9 键时不再开盖住整个键盘的面板。
struct PadQuickMiddle: View {
    @ObservedObject var model: KeyboardModel
    @State private var clipboard = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tab(L("常用语", "Phrases", "定型文"), selected: !clipboard) { clipboard = false }
                tab(L("剪贴板", "Clipboard", "クリップボード"), selected: clipboard) { clipboard = true }
                Spacer(minLength: 4)
                trailing
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: 32)
            Group {
                if clipboard {
                    ClipboardList(model: model)
                } else {
                    PhraseColumn(model: model, fraction: 1, showsHeader: false, twoColumnWidth: 420)
                }
            }
            .padding(.top, 4)
            .frame(maxHeight: .infinity)
        }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            model.clipMenu = nil
            action()
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(selected ? Brand.toggleOpenIcon : Color.secondary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(selected ? Brand.toggleOpenFill : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 右边：常用语写几条；剪贴板写几条，有记录时多一个「清空」（点两下才清，和 iPhone 一样）。
    @ViewBuilder
    private var trailing: some View {
        if clipboard {
            if model.hasFullAccess, !model.clipItems.isEmpty {
                Text(L("\(model.clipItems.count) 条", "\(model.clipItems.count)", "\(model.clipItems.count) 件"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.secondary)
                Button { model.tapClearClips() } label: {
                    Text(model.clipClearArmed ? L("确认清空", "Clear all?", "すべて消去？") : L("清空", "Clear", "消去"))
                        .font(.system(size: 12.5, weight: model.clipClearArmed ? .semibold : .regular))
                        .foregroundStyle(model.clipClearArmed ? Color.red : Color.secondary)
                        .padding(.horizontal, 4)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if !model.quickPhrases.isEmpty {
            Text(L("\(model.quickPhrases.count) 条", "\(model.quickPhrases.count)", "\(model.quickPhrases.count) 件"))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.secondary)
        }
    }
}
