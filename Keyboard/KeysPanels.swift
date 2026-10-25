import SwiftUI

/// 表情和颜文字面板，铺满按键区；底栏切换两者、返回键盘、删除。
struct SymbolPanel: View {
    @ObservedObject var model: KeyboardModel
    @State private var category = "最近"

    private var isEmoji: Bool { model.keysPanel == .emoji }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    if isEmoji { emojiGrid } else { kaomojiGrid }
                }
                .hidingScrollEdgeEffect()
                .onChange(of: category) { id in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                }
            }
            bottomBar
        }
    }

    private var emojiGrid: some View {
        let recent = RecentEmoji.all
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 0)], spacing: 2,
                         pinnedViews: [.sectionHeaders]) {
            if !recent.isEmpty { section("最近", recent) }
            ForEach(EmojiCatalog.categories) { section($0.id, $0.emoji) }
        }
        .padding(.horizontal, 4)
    }

    private func section(_ title: String, _ emoji: [String]) -> some View {
        Section {
            ForEach(emoji, id: \.self) { item in
                Button { model.pickFromPanel(item) } label: {
                    Text(item).font(.system(size: 30)).frame(width: 40, height: 40)
                }
                .buttonStyle(KeyPressStyle())
            }
        } header: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .id(title)
        }
    }

    private var kaomojiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(Kaomoji.all, id: \.self) { item in
                Button { model.pickFromPanel(item) } label: {
                    KeyCap(fill: KeyStyle.charKey, insetX: 0, insetY: 0) {
                        Text(item).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(Color.primary).padding(.horizontal, 4)
                    }
                    .frame(height: 38)
                }
                .buttonStyle(KeyPressStyle())
            }
        }
        .padding(.horizontal, KeyboardMetrics.keyInsetX)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            FunctionKey(title: model.chineseMode ? "返回" : "ABC") { model.closePanel() }
                .frame(width: 52)
            if isEmoji {
                HStack(spacing: 0) {
                    ForEach(["最近"] + EmojiCatalog.categories.map(\.id), id: \.self) { id in
                        Button { category = id } label: {
                            Image(systemName: EmojiCatalog.categories.first { $0.id == id }?.symbol ?? "clock")
                                .font(.system(size: 14))
                                .foregroundStyle(category == id ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
            Button { model.keysPanel = isEmoji ? .kaomoji : .emoji } label: {
                Text(isEmoji ? "^^" : "😀").font(.system(size: 17)).foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
            }
            RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                .frame(width: 52)
        }
        .frame(height: 46)
    }
}

/// 九宫格「常用」打开的面板（W6）：App 里放到键盘的常用词，一行四格，短词一格、中等两格、长的占整行。
/// 点一个上屏并回到九宫格；底排 返回、空格、⌫、回车，和九宫格底排对齐。
struct QuickWordsPanel: View {
    @ObservedObject var model: KeyboardModel

    private static let gap: CGFloat = 5
    private static let cellHeight: CGFloat = 32
    private static let font = UIFont.systemFont(ofSize: 13.5)
    private static let textPadding: CGFloat = 9
    private static let star = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    /// 词格和底排按键的左右边缘对齐九宫格的键。
    private static let sideInset = KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding

    var body: some View {
        let words = model.quickWords
        GeometryReader { geo in
            let width = geo.size.width - Self.sideInset * 2
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("★").foregroundStyle(Self.star)
                    Text(L("放到键盘的常用词", "Keyboard Words", "キーボードの単語"))
                    Text("\(words.count)").foregroundStyle(Color.secondary.opacity(0.6))
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Self.sideInset + 2)
                .frame(height: 22)
                Group {
                    if words.isEmpty { emptyCard } else { grid(words, width: width) }
                }
                .padding(.horizontal, Self.sideInset)
                .frame(maxHeight: .infinity)
                bottomRow(width: geo.size.width)
                    .frame(height: KeyboardMetrics.nineRowPitch)
                    .padding(.bottom, KeyboardMetrics.nineTopOffset)
            }
        }
    }

    private func grid(_ words: [String], width: CGFloat) -> some View {
        let column = (width - Self.gap * 3) / 4
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(CommonWordStore.keyboardRows(words, column: column, gap: Self.gap, font: Self.font,
                                                           padding: Self.textPadding).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.text) { cell in
                            Button { model.pickQuickWord(cell.text) } label: {
                                Text(cell.text)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, Self.textPadding)
                                    .frame(width: column * CGFloat(cell.span) + Self.gap * CGFloat(cell.span - 1),
                                           height: Self.cellHeight, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KeyStyle.charKey))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(KeyPressStyle())
                        }
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 22)
        }
        .hidingScrollEdgeEffect()
        // 底部 22pt 渐隐，提示还能往下滑。
        .mask(VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 22)
        })
    }

    private var emptyCard: some View {
        VStack(spacing: 5) {
            Text(L("还没有放到键盘的词", "No keyboard words yet", "キーボードの単語はまだありません"))
                .font(.system(size: 15, weight: .semibold))
            Text(L("在 Enclave App 的「常用词 › 键盘」里添加", "Add them in Enclave under My Words › Keyboard.",
                   "Enclave の「ユーザ辞書 › キーボード」で追加できます。"))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyStyle.charKey.opacity(0.6)))
        .padding(.bottom, 4)
    }

    private func bottomRow(width: CGFloat) -> some View {
        let edge = KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding - KeyboardMetrics.nineKeyInsetX
        let column = (width - edge * 2) / 5
        let insetX = KeyboardMetrics.nineKeyInsetX, insetY = KeyboardMetrics.nineKeyInsetY
        return HStack(spacing: 0) {
            Button { model.closePanel() } label: {
                KeyCap(fill: KeyStyle.functionKey, insetX: insetX, insetY: insetY) {
                    Text("返回").font(KeyStyle.functionFont).foregroundStyle(Color.primary)
                }
            }
            .buttonStyle(KeyPressStyle())
            .frame(width: column)
            Button { model.spaceKey() } label: {
                KeyCap(fill: KeyStyle.charKey, insetX: insetX, insetY: insetY) {
                    Text("空格").font(KeyStyle.functionFont).tracking(3).foregroundStyle(Color.primary)
                }
            }
            .buttonStyle(KeyPressStyle())
            .frame(width: column * 2)
            RepeatingKey(systemImage: "delete.left", insetX: insetX, insetY: insetY) { model.deleteKey() }
                .frame(width: column)
            Button { model.returnKey() } label: {
                KeyCap(fill: Brand.returnSoftFill, insetX: insetX, insetY: insetY) {
                    Image(systemName: "return.left").font(KeyStyle.iconFont).foregroundStyle(Brand.deepPurple)
                }
            }
            .buttonStyle(KeyPressStyle())
            .frame(width: column)
        }
        .padding(.horizontal, edge)
    }
}

/// 九宫格打拼音时左列的音节栏，和系统一样上下滑动，点一个定下这一段的拼音。
struct PinyinColumn: View {
    @ObservedObject var model: KeyboardModel
    let frame: CGRect

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(model.pinyinOptions, id: \.self) { syllable in
                    Button { model.choosePinyin(syllable) } label: {
                        Text(syllable).font(.system(size: 17)).foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, minHeight: KeyboardMetrics.pinyinCellHeight).contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                }
            }
        }
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous).fill(KeyStyle.charKey))
        .clipShape(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous))
        .padding(.horizontal, KeyboardMetrics.nineKeyInsetX)
        .padding(.vertical, KeyboardMetrics.nineKeyInsetY)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}

/// 九宫格数字键盘点「更多」后左列的运算符，和拼音栏一样上下滑动，第一个浅紫高亮。
struct OperatorColumn: View {
    @ObservedObject var model: KeyboardModel
    let frame: CGRect

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(KeyLayout.operators.enumerated()), id: \.offset) { index, symbol in
                    Button { model.typeSymbol(symbol) } label: {
                        Text(symbol).font(.system(size: 20))
                            .foregroundStyle(index == 0 ? Brand.deepPurple : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: KeyboardMetrics.pinyinCellHeight)
                            .background(index == 0 ? Brand.returnSoftFill : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                }
            }
        }
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous).fill(KeyStyle.charKey))
        .clipShape(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous))
        .padding(.horizontal, KeyboardMetrics.nineKeyInsetX)
        .padding(.vertical, KeyboardMetrics.nineKeyInsetY)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}

/// 九宫格长按的十字：中间浅灰显示原键帽，四周白底圆角带阴影，选中那格内缩 4pt 填紫色、白字。
struct CrossView: View {
    @ObservedObject var model: KeyboardModel
    let popup: CrossPopup

    var body: some View {
        ZStack(alignment: .topLeading) {
            let outer = CrossPopup.Direction.allCases.filter { popup.options[$0] != nil }
            // 外圈先画一层带阴影的白底，四格连成一个十字。
            ForEach(outer, id: \.self) { direction in
                cell(popup.frame(for: direction)) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyStyle.charKey)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                }
            }
            cell(popup.center) {
                Rectangle().fill(Brand.crossCenterFill)
                    .overlay(centerLabel.foregroundStyle(Color.primary))
            }
            ForEach(outer, id: \.self) { direction in
                let selected = popup.selected == direction
                cell(popup.frame(for: direction)) {
                    ZStack {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.purple).padding(4)
                        }
                        Text(popup.options[direction] ?? "")
                            .font(.system(size: 26))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cell<Content: View>(_ frame: CGRect, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if popup.key.kind == .digitPunct {
            Text(".,:").font(KeyStyle.nineKeyFont).tracking(1)
        } else if case .nine(let digit) = popup.key.kind, digit != "'" {
            Text(KeyLayout.nineKeyLetters[digit] ?? digit).font(KeyStyle.nineKeyFont).tracking(1)
        } else {
            PunctuationLabel()
        }
    }
}

/// 长按弹出的备选条，选中的那格是蓝底白字。
struct AlternatesView: View {
    let popup: AlternatesPopup

    var body: some View {
        let frame = popup.frame
        HStack(spacing: 0) {
            ForEach(Array(popup.options.enumerated()), id: \.offset) { index, option in
                Text(option)
                    .font(.system(size: 22))
                    .foregroundStyle(index == popup.selected ? Color.white : Color.primary)
                    .frame(width: AlternatesPopup.cellWidth, height: AlternatesPopup.height - 8)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == popup.selected ? Brand.purple : Color.clear))
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyStyle.charKey)
            .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1))
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }
}
