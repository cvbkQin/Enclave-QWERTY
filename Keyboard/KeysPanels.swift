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

/// 九宫格「常用 / 剪贴板」打开的面板（对齐清单第 62 条，CW2、CW3）：左「常用语 N」、右「剪贴板 N · 清空」，默认各 1/2。
/// 中间分割线按住把手左右拖（见 QuickSplit）：松手在 1/3、1/2、2/3 附近吸附；任一栏小于 1/6 收成竖条，点竖条恢复 1/2；比例记住。
/// 常用语栏：栏头一颗切换钮（标题和内容 → 标题 → 内容），点一条上屏并回到九宫格。剪贴板栏：见 ClipboardList。
/// 底排 返回、空格、⌫、回车，和九宫格底排对齐。
struct QuickWordsPanel: View {
    @ObservedObject var model: KeyboardModel
    /// 正在拖分割线：手指所在的比例（还没吸附）。
    @State private var dragSplit: CGFloat?

    /// 两栏和底排按键的左右边缘对齐九宫格的键。
    private static let sideInset = KeyboardWordsLayout.sideMargin - KeyboardMetrics.sidePadding
    /// 中间分割线那一列的宽（竖线在正中，整列都能按住拖）。
    private static let dividerWidth: CGFloat = 14
    static let headerHeight: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let inner = geo.size.width - Self.sideInset * 2
            let available = inner - Self.dividerWidth
            let split = dragSplit ?? model.quickSplit
            let widths = QuickSplit.widths(split: dragSplit.map { min(max($0, 0.001), 0.999) } ?? split, available: available)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Group {
                        if dragSplit == nil, QuickSplit.collapsedSide(split) == .phrases {
                            strip(L("常用语", "Phrases", "定型文"))
                        } else {
                            PhraseColumn(model: model, fraction: widths.left / inner)
                        }
                    }
                    .frame(width: widths.left)
                    divider(available: available)
                    Group {
                        if dragSplit == nil, QuickSplit.collapsedSide(split) == .clipboard {
                            strip(L("剪贴板", "Clipboard", "クリップボード"))
                        } else {
                            clipboardColumn(leading: Self.sideInset + widths.left + Self.dividerWidth, width: widths.right)
                        }
                    }
                    .frame(width: widths.right)
                    // 长按菜单可以盖到底排上面。
                    .zIndex(model.clipMenu != nil ? 1 : 0)
                }
                .coordinateSpace(name: "quickSplit")
                .padding(.horizontal, Self.sideInset)
                .frame(maxHeight: .infinity)
                .zIndex(model.clipMenu != nil ? 1 : 0)
                bottomRow(width: geo.size.width)
                    .frame(height: KeyboardMetrics.nineRowPitch)
                    .padding(.bottom, KeyboardMetrics.nineTopOffset)
            }
        }
    }

    // MARK: 分割线

    /// 1pt 竖线 + 中间把手（6×34 圆角，次要色 55%）。拖动时竖线和把手变主题紫，把手 8×40 带 4pt 紫色 18% 外圈，上面黑底小气泡写比例。
    private func divider(available: CGFloat) -> some View {
        let dragging = dragSplit != nil
        return ZStack {
            Rectangle()
                .fill(dragging ? Brand.purple : Color(UIColor.separator))
                .frame(width: 1)
                .padding(.vertical, 6)
            Capsule()
                .fill(dragging ? Brand.purple : Color.secondary.opacity(0.55))
                .frame(width: dragging ? 8 : 6, height: dragging ? 40 : 34)
                .padding(dragging ? 4 : 0)
                .background(Capsule().fill(Brand.purple.opacity(dragging ? 0.18 : 0)))
        }
        .frame(width: Self.dividerWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle().inset(by: -6))
        .overlay(alignment: .top) {
            if let dragSplit {
                Text(L("常用 \(QuickSplit.fraction(dragSplit)) · 剪贴板 \(QuickSplit.fraction(1 - dragSplit))",
                       "Phrases \(QuickSplit.fraction(dragSplit)) · Clipboard \(QuickSplit.fraction(1 - dragSplit))",
                       "定型文 \(QuickSplit.fraction(dragSplit)) · クリップ \(QuickSplit.fraction(1 - dragSplit))"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .offset(y: 4)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(2)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("quickSplit"))
                .onChanged { value in
                    model.clipMenu = nil
                    // 竖线在列的正中：手指位置减去半列宽就是左栏的宽。
                    let raw = (value.location.x - Self.dividerWidth / 2) / max(available, 1)
                    dragSplit = min(max(raw, 0), 1)
                }
                .onEnded { _ in
                    guard let raw = dragSplit else { return }
                    let settled = QuickSplit.settle(raw)
                    if settled.snapped { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        dragSplit = nil
                        model.setQuickSplit(settled.split)
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(L("分割线", "Divider", "区切り"))
        .accessibilityValue(L("常用语 \(Int((model.quickSplit * 100).rounded()))%", "Phrases \(Int((model.quickSplit * 100).rounded()))%",
                              "定型文 \(Int((model.quickSplit * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            let steps: [CGFloat] = [0, 1.0 / 3, 0.5, 2.0 / 3, 1]
            let index = steps.firstIndex { abs($0 - model.quickSplit) < 0.01 } ?? 2
            let next = direction == .increment ? min(index + 1, steps.count - 1) : max(index - 1, 0)
            model.setQuickSplit(steps[next])
        }
    }

    /// 收起那一栏：34pt 宽竖条，竖排写栏名；点一下两栏恢复各 1/2。
    private func strip(_ title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.setQuickSplit(QuickSplit.standard) }
        } label: {
            VStack(spacing: 1) {
                ForEach(Array(title.enumerated()), id: \.offset) { _, char in
                    Text(String(char)).font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KeyStyle.charKey.opacity(0.7)))
            .padding(.top, Self.headerHeight)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(L("恢复两栏各一半", "Restores both columns", "2 列に戻す"))
    }

    // MARK: 剪贴板栏

    private func clipboardColumn(leading: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(L("剪贴板", "Clipboard", "クリップボード")).font(.system(size: 14, weight: .semibold))
                if model.hasFullAccess, !model.clipItems.isEmpty {
                    Text("\(model.clipItems.count)").font(.system(size: 13)).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 4)
                if model.hasFullAccess, !model.clipItems.isEmpty {
                    Button { model.tapClearClips() } label: {
                        Text(model.clipClearArmed ? L("确认清空", "Clear all?", "すべて消去？") : L("清空", "Clear", "消去"))
                            .font(.system(size: 13, weight: model.clipClearArmed ? .semibold : .regular))
                            .foregroundStyle(model.clipClearArmed ? Color.red : Color.secondary)
                            .padding(.horizontal, 4)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .lineLimit(1)
            .padding(.leading, 2)
            .frame(height: Self.headerHeight)
            ClipboardList(model: model, leadingRoom: leading, trailingRoom: Self.sideInset)
        }
    }

    // MARK: 底排

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

/// 「常用 / 剪贴板」左栏：常用语（CW3）。栏头「常用语 N」，右边切换钮「⇄ 标题和内容」：栏宽小于 45% 只留 ⇄，小于 20% 不显示。
/// 标题和内容：上行标题（紫色粗体 13）、下行内容（次要色 12.5，一行省略）；没标题的只显示内容（正文色 13.5，最多两行）。
/// 标题：像标签一样一行排多个；没标题的显示内容（次要色）。内容：只显示内容，最多两行。点一条上屏并回到九宫格。
struct PhraseColumn: View {
    @ObservedObject var model: KeyboardModel
    /// 这一栏占整个面板宽的比例。
    var fraction: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(L("常用语", "Phrases", "定型文")).font(.system(size: 14, weight: .semibold))
                if !model.quickPhrases.isEmpty {
                    Text("\(model.quickPhrases.count)").font(.system(size: 13)).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 4)
                if fraction >= 0.2 { displayButton(iconOnly: fraction < 0.45) }
            }
            .lineLimit(1)
            .padding(.leading, 2)
            .frame(height: QuickWordsPanel.headerHeight)
            if model.quickPhrases.isEmpty {
                emptyCard
            } else {
                list
            }
        }
    }

    /// 浅紫底、紫字、⇄ + 当前方式；点一下换下一种（和 App 常用语页共用）。
    private func displayButton(iconOnly: Bool) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { model.cyclePhraseDisplay() } } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .bold))
                if !iconOnly { Text(model.phraseDisplay.name).font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(Brand.deepPurple)
            .padding(.horizontal, iconOnly ? 7 : 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.returnSoftFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(L("显示方式：\(model.phraseDisplay.name)", "Show: \(model.phraseDisplay.name)", "表示：\(model.phraseDisplay.name)"))
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if model.phraseDisplay == .title {
                    PhraseFlow(spacing: 5) {
                        ForEach(model.quickPhrases) { phrase in
                            Button { model.pickQuickWord(phrase.text) } label: {
                                PhraseChip(phrase: phrase, accent: Brand.deepPurple, fill: KeyStyle.charKey)
                            }
                                .buttonStyle(KeyPressStyle())
                        }
                    }
                } else {
                    VStack(spacing: 5) {
                        ForEach(model.quickPhrases) { phrase in
                            Button { model.pickQuickWord(phrase.text) } label: {
                                PhraseCard(phrase: phrase, showsTitle: model.phraseDisplay == .both, accent: Brand.deepPurple, fill: KeyStyle.charKey)
                            }
                            .buttonStyle(KeyPressStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
        .hidingScrollEdgeEffect()
        // 底部 18pt 渐隐，提示还能往下滑。
        .mask(VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
        })
    }

    private var emptyCard: some View {
        VStack(spacing: 5) {
            Text(L("还没有键盘常用语", "No keyboard phrases yet", "キーボードの定型文はまだありません"))
                .font(.system(size: 14, weight: .semibold))
            Text(L("在飞地输入法 App 的 键盘 › 键盘常用语 里添加", "Add them in Enclave under Keyboard › Keyboard Phrases.",
                   "Enclave の キーボード › キーボードの定型文 で追加できます。"))
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyStyle.charKey.opacity(0.6)))
        .padding(.bottom, 4)
    }
}

/// 候选栏上面的拼音行（照 iOS 原生，PY1、PY7）。九宫格只列第一个还没定的字的读法，后面跟这个键的单个字母，
/// 点一项定下这个字的音；全键盘列正在拼的拼音的几种切法，点一个换切法。不加底色、不预选；放不下就左右滑，右边渐隐。
/// 有纠正时（0.94 纠错显示规格 CR1–CR4）列出纠正读法，改过的字母主色字、浅紫底：全键盘作为一种切法并列
/// （拼不成排第一、拼得成排第二）；九宫格放在最前，后面一道细竖线再接第一个字的读法。
struct PinyinRow: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let nine = model.showsNineKey
        let reading = model.correctedReading
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if nine, let reading {
                    item(reading.text, marked: reading.marked) { model.chooseCorrectedReading(reading.text) }
                    Rectangle().fill(Self.dividerColor).frame(width: 1, height: 18).padding(.horizontal, 2)
                }
                ForEach(nine ? model.pinyinOptions : model.pinyinRowSegmentations, id: \.self) { syllable in
                    if !nine, let reading, syllable == reading.text {
                        item(syllable, marked: reading.marked) { model.chooseCorrectedReading(syllable) }
                    } else {
                        item(syllable, marked: []) { nine ? model.choosePinyin(syllable) : model.chooseSegmentation(syllable) }
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 36)
        }
        .hidingScrollEdgeEffect()
        .mask(HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
        })
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
                : UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1) }))
                .frame(height: 1)
        }
    }
}

extension PinyinRow {
    private func item(_ text: String, marked: Set<Int>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // 每项左右 14、最窄 44（单字母 h、g、i 也好点中），点击区占满整行高。
            label(text, marked: marked)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
    }

    /// 改过的字母连成几段，每段主色字、浅紫底（圆角 4，底往两边各出 1，字距不变）。
    private func label(_ text: String, marked: Set<Int>) -> some View {
        var runs: [(text: String, marked: Bool)] = []
        for (offset, char) in text.enumerated() {
            let isMarked = marked.contains(offset)
            if let last = runs.last, last.marked == isMarked {
                runs[runs.count - 1].text.append(char)
            } else {
                runs.append((String(char), isMarked))
            }
        }
        return HStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                Text(run.text).font(.system(size: 17))
                    .foregroundStyle(run.marked ? Self.markedText : Color.primary)
                    .background(run.marked ? RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Self.markedFill).padding(.horizontal, -1) : nil)
            }
        }
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
    static let markedText = dynamic(0x5B4BE8, 0xB4A9FF)
    static let markedFill = dynamic(0xE4E0FC, 0x2E2766)
    static let dividerColor = dynamic(0xAEAEB2, 0x8E8E93)
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

/// 「常用 / 剪贴板」右栏（B1，CB1–CB3，对齐清单第 62 条）。最上面「有新复制的内容，点一下粘贴」（只有新内容时出现，点了才读剪贴板）；
/// 下面每条一张按键底色卡片，右上角灰色时间，点一下插入、面板不关；长按 0.45 秒弹菜单：粘贴 / 加到常用语 / 复制 / 删除。
/// 没开完全访问时读不了剪贴板，换成说明卡。
struct ClipboardList: View {
    @ObservedObject var model: KeyboardModel
    /// 这一栏左边、右边到键盘边还有多宽：长按菜单比栏宽时往左伸，不出键盘。
    var leadingRoom: CGFloat = 0
    var trailingRoom: CGFloat = 0

    private struct RowAnchors: PreferenceKey {
        static var defaultValue: [UUID: Anchor<CGRect>] = [:]
        static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
            value.merge(nextValue()) { $1 }
        }
    }

    var body: some View {
        if !model.hasFullAccess {
            fullAccessCard
        } else {
            VStack(spacing: 0) {
                if model.clipItems.isEmpty {
                    VStack(spacing: 6) {
                        if model.clipboardHasNew { promptRow }
                        Spacer(minLength: 0)
                        Text(L("还没有剪贴板记录", "No clipboard history yet", "クリップボードの履歴はまだありません"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(L("在别的 App 复制文字后，这里会提示你粘贴", "Copy text in another app and you'll be offered to paste it here.",
                               "ほかのアプリでテキストをコピーすると、ここに貼り付けの案内が出ます"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                } else {
                    list.zIndex(1)
                }
                // 两栏后地方小了：只在记录关着时提示一句。
                if !ClipboardHistory.isEnabled {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private var footnote: String {
        ClipboardHistory.isEnabled
            ? L("只存在本机 · 最多 20 条 · 24 小时后自动删除 · 长按可加到常用语",
                "Only on this iPhone · up to 20 · deleted after 24 hours · long-press to add to phrases",
                "この iPhone のみ · 最大 20 件 · 24 時間後に自動削除 · 長押しで定型文に追加")
            : L("剪贴板记录已关闭：粘贴后不保存（App › 键盘 里可以打开）",
                "Clipboard history is off: pasted text isn't kept (turn it on in the app under Keyboard)",
                "クリップボード履歴はオフです：貼り付けたテキストは保存しません（アプリの キーボード でオン）")
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if model.clipboardHasNew { promptRow }
                ForEach(Array(model.clipItems.enumerated()), id: \.element.id) { index, item in
                    row(item, fresh: index == 0 && Date().timeIntervalSince(item.date) < 60)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
        .hidingScrollEdgeEffect()
        .mask(VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
        })
        .overlayPreferenceValue(RowAnchors.self) { anchors in
            GeometryReader { geo in
                if let id = model.clipMenu, let anchor = anchors[id], let item = model.clipItems.first(where: { $0.id == id }) {
                    let rect = geo[anchor]
                    ZStack(alignment: .topLeading) {
                        // 点菜单外面只收起菜单：挡住整块按键区（标签栏、脚注、底排、AI 栏），不点到底下的东西。
                        Color.black.opacity(0.001)
                            .frame(width: leadingRoom + geo.size.width + trailingRoom + 40,
                                   height: Self.menuAreaBottom(listHeight: geo.size.height) - Self.menuAreaTop)
                            .offset(x: -leadingRoom - 20, y: Self.menuAreaTop)
                            .onTapGesture { model.clipMenu = nil }
                        ClipMenu(model: model, item: item)
                            .offset(x: min(max(rect.minX + 40, -leadingRoom), geo.size.width + trailingRoom - ClipMenu.width),
                                    y: Self.menuY(row: rect, listHeight: geo.size.height))
                    }
                }
            }
        }
    }

    /// 菜单的上边（列表坐标）。能放下就在这条下面（可以盖住脚注和底排），放不下就在上面；
    /// 往上最多盖到标签栏和 AI 栏，不伸出键盘顶（键盘画不到外面，会被截掉）。
    static var menuAreaTop: CGFloat { -(QuickWordsPanel.headerHeight + KeyboardMetrics.topRow) }

    static func menuAreaBottom(listHeight: CGFloat) -> CGFloat {
        listHeight + KeyboardMetrics.nineRowPitch + KeyboardMetrics.nineTopOffset
    }

    static func menuY(row: CGRect, listHeight: CGFloat) -> CGFloat {
        let top = menuAreaTop
        let bottom = menuAreaBottom(listHeight: listHeight) - ClipMenu.height
        let below = row.maxY + 6
        let preferred = below <= bottom ? below : row.minY - ClipMenu.height - 6
        return min(max(preferred, top), max(bottom, top))
    }

    /// 44 高、浅紫底、1.5pt 主色虚线框、剪贴板图标 + 主色 15 粗。
    private var promptRow: some View {
        Button { model.pasteNewClipboard() } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 15, weight: .semibold))
                Text(L("有新复制的内容，点一下粘贴", "New copied text. Tap to paste", "新しくコピーした内容があります。タップで貼り付け"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Brand.deepPurple)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.returnSoftFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Brand.purple, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
    }

    private func row(_ item: ClipItem, fresh: Bool) -> some View {
        let menuOpen = model.clipMenu == item.id
        return HStack(alignment: .top, spacing: 8) {
            Text(item.text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ClipboardHistory.age(item.date))
                .font(.system(size: 11.5))
                .foregroundStyle(fresh ? Brand.deepPurple : Color.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fresh ? Brand.returnSoftFill : KeyStyle.charKey))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Brand.purple, lineWidth: menuOpen ? 1.5 : 0))
        .contentShape(Rectangle())
        .onTapGesture { model.pasteClip(item) }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.clipMenu = item.id
        }
        .anchorPreference(key: RowAnchors.self, value: .bounds) { [item.id: $0] }
    }

    /// 没开完全访问（CB3 右）。
    private var fullAccessCard: some View {
        VStack(spacing: 8) {
            Text(L("剪贴板要先打开「允许完全访问」", "Clipboard needs Full Access", "クリップボードには「フルアクセスを許可」が必要です"))
                .font(.system(size: 15, weight: .semibold))
            Text(L("设置 › 通用 › 键盘 › 键盘 › 飞地输入法 › 允许完全访问。打开后只在你点粘贴时才读剪贴板。",
                   "Settings › General › Keyboard › Keyboards › Enclave › Allow Full Access. The clipboard is read only when you tap paste.",
                   "設定 › 一般 › キーボード › キーボード › Enclave › フルアクセスを許可。オンにしても、貼り付けをタップしたときだけ読み取ります。"))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey))
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
    }
}

/// 长按剪贴板一条弹出的菜单（CB2）：粘贴 / 加到常用语 ★ / 复制 / 删除（红）。
struct ClipMenu: View {
    static let width: CGFloat = 200
    static let height: CGFloat = 4 * 40 + 9 + 12

    @ObservedObject var model: KeyboardModel
    let item: ClipItem

    var body: some View {
        VStack(spacing: 0) {
            option(L("粘贴", "Paste", "貼り付け"), action: .paste)
            option(L("加到常用语", "Add to phrases", "定型文に追加"), action: .addToPhrases, star: true)
            option(L("复制", "Copy", "コピー"), action: .copy)
            Divider().padding(.vertical, 4).padding(.horizontal, 8)
            option(L("删除", "Delete", "削除"), action: .delete, destructive: true)
        }
        .padding(6)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey))
        .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.22), radius: 12, y: 8)
    }

    private func option(_ title: String, action: KeyboardModel.ClipAction, star: Bool = false, destructive: Bool = false) -> some View {
        Button { model.performClipAction(action, item: item) } label: {
            HStack {
                Text(title).font(.system(size: 15, weight: star ? .semibold : .regular))
                Spacer(minLength: 4)
                if star { Text("★").font(.system(size: 14)) }
            }
            .foregroundStyle(destructive ? Color.red : (star ? Brand.deepPurple : Color.primary))
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(star ? Brand.returnSoftFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
