import SwiftUI

/// 表情和颜文字面板，铺满按键区；底栏切换两者、返回键盘、删除。
struct SymbolPanel: View {
    @ObservedObject var model: KeyboardModel
    @State private var category = "最近"
    /// 正在长按选肤色（见 EmojiSkinPicker）。
    @State private var skin: SkinPick?

    /// 表情区的坐标系，选肤色的弹层按它摆。
    static let space = "emojiPanel"

    private var isEmoji: Bool { model.keysPanel == .emoji }
    private var haptics: Bool { model.settings.keyHaptics && model.hasFullAccess }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        if isEmoji { emojiGrid(width: geo.size.width) } else { kaomojiGrid }
                    }
                    .hidingScrollEdgeEffect()
                    // 弹层打开时，面板不跟着手指上下滚。
                    .scrollDisabled(skin != nil)
                    .onChange(of: category) { id in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .overlay(alignment: .topLeading) { skinLayer }
            }
            .coordinateSpace(name: Self.space)
            bottomBar
        }
        .onChange(of: model.keysPanel) { _ in skin = nil }
    }

    private func emojiGrid(width: CGFloat) -> some View {
        // 「最近」存的是原型，按原型去重（老版本存过带肤色的也对回原型）。
        var seen = Set<String>()
        let recent = RecentEmoji.all.filter { seen.insert(EmojiCatalog.lookup[$0]?.emoji ?? $0).inserted }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 0)], spacing: 2,
                         pinnedViews: [.sectionHeaders]) {
            if !recent.isEmpty {
                section("最近", recent.map { EmojiCatalog.lookup[$0] ?? EmojiCatalog.Item(emoji: $0, tones: []) }, width: width)
            }
            ForEach(EmojiCatalog.categories) { section($0.id, $0.items, width: width) }
        }
        .padding(.horizontal, 4)
    }

    private func section(_ title: String, _ items: [EmojiCatalog.Item], width: CGFloat) -> some View {
        Section {
            ForEach(items, id: \.emoji) { item in
                if item.hasTones {
                    EmojiCell(emoji: EmojiSkin.shown(item), badge: true, active: skin?.item == item,
                              tap: { model.pickFromPanel(EmojiSkin.shown(item), recent: item.emoji) },
                              begin: { beginSkin(item, cell: $0, width: width) },
                              move: moveSkin, end: endSkin)
                } else {
                    Button { model.pickFromPanel(item.emoji) } label: {
                        Text(item.emoji).font(.system(size: 30)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(KeyPressStyle())
                }
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

    // MARK: 选肤色

    @ViewBuilder private var skinLayer: some View {
        if let pick = skin {
            if pick.item.isPair {
                ZStack(alignment: .topLeading) {
                    // 点面板外面：关掉，不上屏，不记。
                    Color.black.opacity(0.001).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { skin = nil }
                    PairSkinPanel(pick: pick, choose: { left, right in
                        skin?.left = left
                        skin?.right = right
                        if haptics { UISelectionFeedbackGenerator().selectionChanged() }
                    }, commit: { emoji in
                        commitSkin(pick.item, emoji)
                    })
                    .offset(x: pick.frame.minX, y: pick.frame.minY)
                }
            } else {
                SingleSkinBar(pick: pick)
                    .offset(x: pick.frame.minX, y: pick.frame.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func beginSkin(_ item: EmojiCatalog.Item, cell: CGRect, width: CGFloat) {
        guard skin?.item != item else { return }
        let shown = EmojiSkin.shown(item)
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if item.isPair {
            // 再长按：两排预选上次的肤色。
            let code = item.tones.first { $0.emoji == shown }?.code
            let (frame, above) = SkinPickLayout.place(size: SkinPickLayout.pairSize, cell: cell,
                                                      centerX: SkinPickLayout.pairSize.width / 2, width: width)
            skin = SkinPick(item: item, cell: cell, frame: frame, above: above, index: nil,
                            left: code.flatMap { $0.first?.wholeNumberValue },
                            right: code.flatMap { $0.last?.wholeNumberValue })
        } else {
            // 一开始高亮当前那格，正对手指上方。
            let index = item.tones.prefix(5).firstIndex { $0.emoji == shown }.map { $0 + 1 } ?? 0
            let (frame, above) = SkinPickLayout.place(size: SkinPickLayout.singleSize, cell: cell,
                                                      centerX: SkinPickLayout.singleCenter(index), width: width)
            skin = SkinPick(item: item, cell: cell, frame: frame, above: above, index: index)
        }
    }

    private func moveSkin(_ point: CGPoint) {
        guard let pick = skin, !pick.item.isPair else { return }
        let index = SkinPickLayout.singleIndex(at: point, in: pick.frame)
        guard index != pick.index else { return }
        skin?.index = index
        if index != nil, haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// 松手：单人上屏高亮那个（滑出去了就只关弹层）；两人面板松手不收。
    private func endSkin() {
        guard let pick = skin, !pick.item.isPair else { return }
        if let index = pick.index, index < pick.choices.count {
            commitSkin(pick.item, pick.choices[index])
        } else {
            skin = nil
        }
    }

    private func commitSkin(_ item: EmojiCatalog.Item, _ emoji: String) {
        EmojiSkin.remember(item, emoji)
        model.pickFromPanel(emoji, recent: item.emoji)
        skin = nil
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
        if !model.showsNineKey, let scheme = model.doublePinyin {
            doublePinyinBody(scheme)
        } else {
            optionsBody
        }
    }

    /// 双拼（SP1、SP6）：整串拼音照旧显示全拼（ni hao），放在一颗浅键帽里，点了上屏全拼字母（nihao）；旁边灰色等宽小字是按的键（nihc），
    /// 最右边写方案名。双拼没有别的切法。拼不成音节的两个键在全拼和按键里都标红（键上提示关掉、或也认全拼时不标）（双拼调研 P1）。
    private func doublePinyinBody(_ scheme: DoublePinyin) -> some View {
        let raw = model.engine.rawInput
        let from = model.engine.selections.last?.end ?? 0
        let groups = DoublePinyin.pairs(in: raw, from: from)
        // 首选换成了纠正后的词（SP9）：全拼写纠正后的、改过的音节浅紫底；按键里换掉的键浅紫底，后面灰字「v 改成 c」。不再标红。
        let correction = from == 0 ? model.engine.pendingCorrection.flatMap { $0.place == 1 && $0.typed == raw ? $0 : nil } : nil
        let reading = correction != nil ? model.correctedReading : nil
        let marks = model.settings.doublePinyinHintMode != .off && !model.doublePinyinMixFull && reading == nil
        let bad = Set(groups.filter { marks && $0.keys.count == 2 && !scheme.isSyllableCode($0.keys) }.flatMap { Array($0.range) })
        let fixedKeys = correction.map(Self.typedChangedKeys) ?? []
        return HStack(spacing: 10) {
            Button { model.commitFullPinyin() } label: {
                HStack(spacing: 3) {
                    if let reading {
                        label(reading.text.replacingOccurrences(of: "'", with: " "), marked: reading.marked)
                    } else {
                        fullPinyin(scheme, raw: raw, groups: groups, bad: bad, segmented: from > 0)
                    }
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(SidePinyinStyle.hint)
                }
                .lineLimit(1)
            }
            .buttonStyle(FullPinyinKeyStyle())
            .disabled(!model.canCommitFullPinyin)
            .accessibilityHint(L("上屏全拼", "Insert the full pinyin", "ピンインをそのまま入力"))
            if !raw.isEmpty {
                marked(Array(raw), bad: reading == nil ? bad : fixedKeys, fixed: reading != nil)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(KeyStyle.pressedKey.opacity(0.5)))
                if reading != nil, let note = model.doublePinyinCorrectionNote {
                    Text(note).font(.system(size: 12)).foregroundStyle(SidePinyinStyle.hint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if model.showsFullPinyinTip {
                // 第一次在双拼下组字时说一次（SP6 ①）。键盘画不到输入框上面，气泡放在这一行右边。
                Text(L("点拼音，直接上屏字母 \(model.fullPinyinText)", "Tap the pinyin to insert \(model.fullPinyinText)", "ピンインをタップで \(model.fullPinyinText) を入力"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .onTapGesture { model.showsFullPinyinTip = false }
            } else {
                Text(scheme.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { bottomLine }
    }

    /// 全拼：平时就是引擎的拼写；有拼不成的键对、又没分段选过时，按键对自己拼（拼得成的换成全拼，拼不成的照写按键标红：ni bz）。
    @ViewBuilder
    private func fullPinyin(_ scheme: DoublePinyin, raw: String, groups: [(range: Range<Int>, keys: String)],
                            bad: Set<Int>, segmented: Bool) -> some View {
        if bad.isEmpty || segmented {
            Text(model.composition).font(.system(size: 17))
        } else {
            HStack(spacing: 4) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if bad.contains(group.range.lowerBound) {
                        marked(Array(group.keys), bad: Set(0..<group.keys.count))
                    } else {
                        Text(scheme.readings[group.keys] ?? group.keys)
                    }
                }
            }
            .font(.system(size: 17))
        }
    }

    /// 纠正时原样按的键里被换掉、按反、多按的那几个（SP9）。
    static func typedChangedKeys(_ correction: PendingCorrection) -> Set<Int> {
        let typed = correction.typed.count, fixed = correction.corrected.count
        let range = KeyboardModel.changedKeys(correction)
        let upper = min(typed, max(range.lowerBound, typed - (fixed - range.upperBound)))
        return Set(range.lowerBound..<max(range.lowerBound, upper))
    }

    /// 一串字，bad 里的位置用红字浅红底（SP6 ③）；fixed 时是纠错换过的键，主色字浅紫底（SP9）。
    private func marked(_ chars: [Character], bad: Set<Int>, fixed: Bool = false) -> some View {
        var runs: [(text: String, bad: Bool)] = []
        for (index, char) in chars.enumerated() {
            let isBad = bad.contains(index)
            if let last = runs.last, last.bad == isBad {
                runs[runs.count - 1].text.append(char)
            } else {
                runs.append((String(char), isBad))
            }
        }
        return HStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                if run.bad {
                    Text(run.text)
                        .foregroundStyle(fixed ? Self.markedText : Self.badPairText)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fixed ? Self.markedFill : Self.badPairFill))
                } else {
                    Text(run.text)
                }
            }
        }
    }

    static let badPairText = SidePinyinStyle.dynamic(0xE5484D, 0xFF6B6B)
    static let badPairFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 107 / 255, blue: 107 / 255, alpha: 0.16)
        : UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 0.12) })

    private var bottomLine: some View {
        Rectangle().fill(Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
            : UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1) }))
            .frame(height: 1)
    }

    private var optionsBody: some View {
        let nine = model.showsNineKey
        let reading = model.correctedReading
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // 输入框不认标记文字（NM1）：整串拼音放在最左边，后面一道竖线再接平时的拼音选项。
                if let pinyin = model.offFieldPinyin {
                    OffFieldPinyinText(text: pinyin)
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                    Rectangle().fill(Self.dividerColor).frame(width: 1, height: 18).padding(.horizontal, 2)
                }
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
            .background(ImmediateTouches())
        }
        .hidingScrollEdgeEffect()
        .mask(HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
        })
        .overlay(alignment: .bottom) { bottomLine }
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
        .buttonStyle(PinyinPressStyle())
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
    /// 按下时字后面的浅色底，和候选栏长按时那块一样（黑 8% / 白 16%）。
    static let pressedFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.08) })
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
                                    y: Self.menuY(row: rect, listHeight: geo.size.height,
                                                  height: ClipMenu.height(help: ClipMenu.showsHelp(model, item))))
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

    static func menuY(row: CGRect, listHeight: CGFloat, height: CGFloat) -> CGFloat {
        let top = menuAreaTop
        let bottom = menuAreaBottom(listHeight: listHeight) - height
        let below = row.maxY + 6
        let preferred = below <= bottom ? below : row.minY - height - 6
        return min(max(preferred, top), max(bottom, top))
    }

    /// 44 高、浅紫底、1.5pt 主色虚线框、剪贴板图标 + 主色 15 粗。
    /// 问答能用时右边一颗绿色「帮回」（T16）：点左边粘贴，点「帮回」直接写回复；两种都会把这条存进记录。
    private var promptRow: some View {
        HStack(spacing: 6) {
            Button { model.pasteNewClipboard() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 15, weight: .semibold))
                    Text(L("有新复制的内容，点一下粘贴", "New copied text. Tap to paste", "新しくコピーした内容があります。タップで貼り付け"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Brand.deepPurple)
                .padding(.leading, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
        }
        .padding(.trailing, 12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.returnSoftFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Brand.purple, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
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

/// 长按剪贴板一条弹出的菜单（CB2）：粘贴 / 帮回这条（绿，帮回并入润色）/ 加到常用语 ★ / 复制 / 删除（红）。
struct ClipMenu: View {
    static let width: CGFloat = 200

    static func height(help: Bool) -> CGFloat { CGFloat(help ? 5 : 4) * 40 + 9 + 12 }

    /// 「帮回这条」：润色接口能用，单号、链接、纯数字、邮箱这类不出。
    static func showsHelp(_ model: KeyboardModel, _ item: ClipItem) -> Bool {
        model.helpReplyAvailable && HelpReply.suits(item.text)
    }

    @ObservedObject var model: KeyboardModel
    let item: ClipItem

    var body: some View {
        VStack(spacing: 0) {
            option(L("粘贴", "Paste", "貼り付け"), action: .paste)
            if Self.showsHelp(model, item) { helpOption }
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

    /// 用当前润色风格回这条（本机存好的这条，不读剪贴板）。
    private var helpOption: some View {
        Button { model.helpFromClip(item) } label: {
            HStack(spacing: 6) {
                Text(L("帮回这条", "Help Reply to This", "この内容に返信")).font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                HelpIcon(size: 16)
            }
            .foregroundStyle(HelpStyle.softText)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// 拼音行一项按下：字变淡（和候选栏按下一样 45%），后面一块圆角 6 的浅色底（比字左右各宽 6，上下离行边 4）。
/// 以前用 KeyPressStyle（只调亮度），浅色模式下黑字调暗看不出来，点了不知道点到没有（11-13 真机录屏）。
private struct PinyinPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PinyinRow.pressedFill)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
    }
}

/// 把外面那层滚动视图的「按住一会儿才算按下」关掉（和候选栏 CandidateStripView 一样），快点一下也马上显示按下的样子；左右滑照样能滚。
private struct ImmediateTouches: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Probe: UIView {
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView { scroll.delaysContentTouches = false; return }
                view = current.superview
            }
        }
    }
}

/// 双拼拼写栏里可点的全拼（SP6）：白底圆角 8、高 28 的浅键帽；按下浅紫底、主色字和 1.5 描边。
struct FullPinyinKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(pressed ? SidePinyinStyle.mainText : Color.primary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(pressed ? SidePinyinStyle.firstFill : KeyStyle.charKey))
            .overlay {
                if pressed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SidePinyinStyle.mainText, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
    }
}
