import SwiftUI

/// 表情和颜文字面板，铺满按键区；底栏切换两者、返回键盘、删除。
/// 底栏（EP1、EP2）：高 50，左右 4、间距 6；返回 60×40 ｜ 分类条（放不下横滑，两边 22 渐隐）｜ 表情 / 颜文字切换 44×40 ｜ 删除 60×40。
/// 点分类：面板滚到那一类（0.2 秒），选中马上换；上下滑面板：顶上露出哪一类就选中哪一类，分类条跟着滚到看得见。
/// 表情格子是 UIKit 的 EmojiGrid（只画看得见的几排，bug #39）；颜文字只有几十个，还用 SwiftUI。
/// 「最近」在面板打开时（或表情、颜文字互相切换时）定下来，开着时点了不重排：原来点一下「最近」里的表情它就挪到最前，
/// 后面的往后挤，连点两下第二下会点到别的。新点的下次打开面板再排进去。
struct SymbolPanel: View {
    @ObservedObject var model: KeyboardModel
    /// 底栏选中的分类；nil 是第一个。
    @State private var selected: String?
    /// 各组小标题现在在面板里的位置（不触发重画，选中变了才改 selected）。
    @State private var tracker = SectionTracker()
    /// 点了分类、面板正在滚过去：这期间不按滚动位置改选中（颜文字；表情格子自己管）。
    @State private var jumping = false
    /// 叫表情格子跳到某一类。
    @State private var emojiGrid = EmojiGridHandle()
    /// 打开面板时的「最近」，见上。
    @State private var recentEmoji = RecentEmoji.all
    @State private var recentKaomoji = RecentKaomoji.all

    private var isEmoji: Bool { model.keysPanel == .emoji }

    private struct Tab: Identifiable {
        let id: String
        let title: String
        var symbol: String?
    }

    final class SectionTracker {
        var tops: [String: CGFloat] = [:]
    }

    private static let space = "symbolPanel"

    var body: some View {
        let emojiSections = isEmoji ? EmojiPanelSection.sections(recent: recentEmoji) : []
        let kaomojiGroups = isEmoji ? [] : Self.kaomojiGroups(recent: recentKaomoji)
        let tabs: [Tab] = isEmoji
            ? emojiSections.map { Tab(id: $0.id, title: $0.title, symbol: $0.symbol) }
            : kaomojiGroups.map { Tab(id: $0.id, title: Kaomoji.title($0.id)) }
        let order = tabs.map(\.id)
        let current = selected.flatMap { order.contains($0) ? $0 : nil } ?? order.first
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if isEmoji {
                    EmojiGrid(sections: emojiSections, handle: emojiGrid, onPick: { model.pickFromPanel($0) }) { id in
                        if id != (selected ?? order.first) { selected = id }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        kaomojiGrid(kaomojiGroups, order: order)
                    }
                    .hidingScrollEdgeEffect()
                    .coordinateSpace(name: Self.space)
                }
                bottomBar(tabs: tabs, current: current) { id in
                    selected = id
                    if isEmoji {
                        emojiGrid.view?.jump(to: id)
                        return
                    }
                    jumping = true
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { jumping = false }
                }
            }
            // 表情和颜文字互相切换：选中回到第一组，面板回到顶上，「最近」重新读。
            .onChange(of: model.keysPanel) { _ in
                selected = nil
                tracker.tops = [:]
                recentEmoji = RecentEmoji.all
                recentKaomoji = RecentKaomoji.all
                if let first = order.first { proxy.scrollTo(first, anchor: .top) }
            }
        }
    }

    // MARK: 颜文字

    /// 有用过的颜文字时前面加「最近」（最多 8 个）。
    private static func kaomojiGroups(recent: [String]) -> [Kaomoji.Mood] {
        return (recent.isEmpty ? [] : [Kaomoji.Mood(id: "最近", items: recent)]) + Kaomoji.groups
    }

    /// 一行 4 个，每组上面一行小标题（同表情）。太长的缩小字号放进一格，不换行。iPad（PK10）一行 6 个，格子高 46、字 17。
    private func kaomojiGrid(_ groups: [Kaomoji.Mood], order: [String]) -> some View {
        let pad = KeyboardMetrics.pad != nil
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: pad ? 8 : 6), count: pad ? 6 : 4), spacing: pad ? 8 : 6,
                  pinnedViews: [.sectionHeaders]) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items, id: \.self) { item in
                        Button { model.pickFromPanel(item) } label: {
                            KeyCap(fill: KeyStyle.charKey, insetX: 0, insetY: 0) {
                                Text(item).font(.system(size: pad ? 17 : 15)).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(Color.primary).padding(.horizontal, 4)
                            }
                            .frame(height: pad ? 46 : 38)
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                } header: {
                    header(group.id, title: Kaomoji.title(group.id), order: order)
                }
            }
        }
        .padding(.horizontal, KeyboardMetrics.keyInsetX)
    }

    // MARK: 小标题、跟着滑动选中

    private func header(_ id: String, title: String, order: [String]) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .background(GeometryReader { geo in
                let top = geo.frame(in: .named(Self.space)).minY
                Color.clear
                    .onAppear { note(id, top: top, order: order) }
                    .onChange(of: top) { note(id, top: $0, order: order) }
                    .onDisappear { tracker.tops[id] = nil }
            })
            .id(id)
    }

    /// 顶上露出的是哪一组：已经滑到顶（离顶不到 4）的小标题里最靠下的那个；一个都没到顶就是第一组。
    private func note(_ id: String, top: CGFloat, order: [String]) {
        tracker.tops[id] = top
        guard !jumping else { return }
        let reached = tracker.tops.filter { $0.value <= 4 }
        let now = reached.max { a, b in
            a.value != b.value ? a.value < b.value : (order.firstIndex(of: a.key) ?? 0) < (order.firstIndex(of: b.key) ?? 0)
        }?.key ?? order.first
        if let now, now != (selected ?? order.first) { selected = now }
    }

    // MARK: 底栏

    @ViewBuilder
    private func bottomBar(tabs: [Tab], current: String?, jump: @escaping (String) -> Void) -> some View {
        if let pad = KeyboardMetrics.pad {
            padBottomBar(pad, tabs: tabs, current: current, jump: jump)
        } else {
            phoneBottomBar(tabs: tabs, current: current, jump: jump)
        }
    }

    /// iPad（PK10 ②，11-22 cvbk「下面的选项明显没适配ipad的显示空间，按键太小」）：🌐、返回、表情 / 颜文字切换、⌫、收起键盘
    /// 和键盘最下面一排的功能键一样大；中间一整条放分类，平均分满，不用横滑，选中那格白底紫字。
    private func padBottomBar(_ pad: PadMetrics, tabs: [Tab], current: String?, jump: @escaping (String) -> Void) -> some View {
        PadPanelBar(pad: pad) { cell in
            PadGlobeKey(model: model).frame(width: cell * 1.2)
            PadPanelKey(label: model.chineseMode ? L("返回", "Back", "戻る") : "ABC", action: { model.closePanel() }) {
                Text(model.chineseMode ? "返回" : "ABC").font(KeyStyle.functionFont)
            }
            .frame(width: cell * 1.4)
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    let on = tab.id == current
                    Button { jump(tab.id) } label: {
                        Group {
                            if let symbol = tab.symbol {
                                Image(systemName: symbol).font(.system(size: 20))
                            } else {
                                Text(tab.title).font(.system(size: 15, weight: on ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .foregroundStyle(on ? Brand.purpleText : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                            .fill(on ? KeyStyle.charKey : Color.clear))
                        .padding(.vertical, pad.gap / 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, pad.gap / 2)
            .frame(maxWidth: .infinity)
            PadPanelKey(label: isEmoji ? L("颜文字", "Kaomoji", "顔文字") : L("表情", "Emoji", "絵文字"),
                        action: { model.keysPanel = isEmoji ? .kaomoji : .emoji }) {
                Text(isEmoji ? "^^" : "😀").font(KeyStyle.functionFont)
            }
            .frame(width: cell)
            RepeatingKey(systemImage: "delete.left", insetX: pad.gap / 2, insetY: pad.gap / 2, fill: KeyStyle.padFunctionKey) {
                model.deleteKey()
            }
            .frame(width: cell * 1.4)
            PadDismissKey(model: model).frame(width: cell * 1.2)
        }
    }

    private func phoneBottomBar(tabs: [Tab], current: String?, jump: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            panelKey(width: 60, label: model.chineseMode ? L("返回", "Back", "戻る") : "ABC", action: { model.closePanel() }) {
                Text(model.chineseMode ? "返回" : "ABC").font(.system(size: 17))
            }
            // 选中换了（点的、滑出来的）：分类条滚到能看全这一格。
            AIKeyStrip(fadeWidth: 22, reveal: current.map { AnyHashable("tab-" + $0) }) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        Button { jump(tab.id) } label: { tabLabel(tab, on: tab.id == current) }
                            .buttonStyle(KeyPressStyle())
                            .accessibilityLabel(tab.title)
                            .accessibilityAddTraits(tab.id == current ? .isSelected : [])
                            .id("tab-" + tab.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            panelKey(width: 44, label: isEmoji ? L("颜文字", "Kaomoji", "顔文字") : L("表情", "Emoji", "絵文字"),
                     action: { model.keysPanel = isEmoji ? .kaomoji : .emoji }) {
                Text(isEmoji ? "^^" : "😀").font(.system(size: 17))
            }
            // 按住连删，同原来。
            RepeatingKey(systemImage: "delete.left", insetX: 0, insetY: 0) { model.deleteKey() }
                .frame(width: 60, height: 40)
        }
        .padding(.horizontal, 4)
        .frame(height: 50)
    }

    /// 返回、切换：功能键底色，按下和别的功能键一样变深（KeyPressStyle）。
    private func panelKey<Label: View>(width: CGFloat, label: String, action: @escaping () -> Void,
                                       @ViewBuilder content: () -> Label) -> some View {
        Button(action: action) {
            KeyCap(fill: KeyStyle.functionKey, insetX: 0, insetY: 0) {
                content().foregroundStyle(Color.primary)
            }
            .frame(width: width, height: 40)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(label)
    }

    /// 表情：40×34、图标 20pt；颜文字：文字 15、左右 12、高 32。没选中灰色，选中浅紫底、主色（颜文字 600 粗），圆角 9。
    private func tabLabel(_ tab: Tab, on: Bool) -> some View {
        Group {
            if let symbol = tab.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 34)
            } else {
                Text(tab.title)
                    .font(.system(size: 15, weight: on ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 32)
            }
        }
        .foregroundStyle(on ? Brand.purpleText : Color.secondary)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Brand.panelTabFill : Color.clear))
        .contentShape(Rectangle())
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
    private static var sideInset: CGFloat { KeyboardWordsLayout.sideMargin - KeyboardMetrics.sidePadding }
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
                            strip(L("剪贴板", "Clipboard", "クリップボード"), dot: model.clipboardDotShown)
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
                if let pad = KeyboardMetrics.pad {
                    padBottomRow(pad)
                } else {
                    bottomRow(width: geo.size.width)
                        .frame(height: KeyboardMetrics.nineRowPitch)
                        .padding(.bottom, KeyboardMetrics.nineTopOffset)
                }
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
    /// 剪贴板一栏收起时不读剪贴板：有新复制的内容（只看 changeCount）右上角一个 7pt 主色圆点，点开恢复后才读（T97）。
    private func strip(_ title: String, dot: Bool = false) -> some View {
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
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle().fill(ClipboardList.badgeFill).frame(width: 7, height: 7).padding(5)
                        .accessibilityHidden(true)
                }
            }
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

    /// iPad（PK10 ③）：🌐、返回、空格、⌫、发送、收起键盘，和键盘最下面一排一样高。
    private func padBottomRow(_ pad: PadMetrics) -> some View {
        PadPanelBar(pad: pad) { cell in
            PadGlobeKey(model: model).frame(width: cell * 1.2)
            PadPanelKey(label: L("返回", "Back", "戻る"), action: { model.closePanel() }) {
                Text("返回").font(KeyStyle.functionFont)
            }
            .frame(width: cell * 1.4)
            PadPanelKey(fill: KeyStyle.charKey, label: L("空格", "Space", "スペース"), action: { model.spaceKey() }) {
                Text("空格").font(KeyStyle.functionFont).tracking(3)
            }
            .frame(maxWidth: .infinity)
            RepeatingKey(systemImage: "delete.left", insetX: pad.gap / 2, insetY: pad.gap / 2, fill: KeyStyle.padFunctionKey) {
                model.deleteKey()
            }
            .frame(width: cell * 1.4)
            PadPanelKey(fill: Brand.returnSoftFill, label: L("发送", "Send", "送信"), action: { model.returnKey() }) {
                Image(systemName: "return.left").font(KeyStyle.iconFont).foregroundStyle(Brand.deepPurple)
            }
            .frame(width: cell * 1.9)
            PadDismissKey(model: model).frame(width: cell * 1.2)
        }
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

/// 「常用 / 剪贴板」左栏：常用语（CW3）。栏头「常用语 N」，右边切换钮「⇄ 标题和内容」：栏宽小于 45% 只留 ⇄，小于 20% 不显示。
/// 标题和内容：上行标题（紫色粗体 13）、下行内容（次要色 12.5，一行省略）；没标题的只显示内容（正文色 13.5，最多两行）。
/// 标题：像标签一样一行排多个；没标题的显示内容（次要色）。内容：只显示内容，最多两行。点一条上屏并回到九宫格。
struct PhraseColumn: View {
    @ObservedObject var model: KeyboardModel
    /// 这一栏占整个面板宽的比例。
    var fraction: CGFloat
    /// iPad 9 键中间那块（PK17）上面已经有「常用语 / 剪贴板」两个标签，不再要栏头。
    var showsHeader = true
    /// 栏宽到这么宽时卡片排两列（面板 540；iPad 9 键中间那块横屏就排两列，PK17）。
    var twoColumnWidth: CGFloat = 540
    /// 这一栏多宽：iPad 上够宽（540 以上）时卡片排两列（PK10 ③，一次看 6 条）。
    @State private var columnWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
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
            }
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
                } else if KeyboardMetrics.pad != nil, columnWidth >= twoColumnWidth {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                        ForEach(model.quickPhrases) { phrase in
                            Button { model.pickQuickWord(phrase.text) } label: {
                                PhraseCard(phrase: phrase, showsTitle: model.phraseDisplay == .both, accent: Brand.deepPurple, fill: KeyStyle.charKey)
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
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { columnWidth = geo.size.width }
                    .onChange(of: geo.size.width) { columnWidth = $0 }
            })
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

/// 九宫格长按的十字（全键盘「，。」往上划也用它）：灰托盘、白色小按钮，选中变紫（第 88 条）。
struct CrossView: View {
    @ObservedObject var model: KeyboardModel
    let popup: CrossPopup

    private var isPad: Bool { KeyboardMetrics.pad != nil }

    /// 托盘式（对齐清单第 88 条，design/popup-style 第 3 节）：一块十字形灰托盘（1pt 描边、阴影），
    /// 有选项的方向放一颗白色小按钮，选中变紫；中间不放按钮，只写灰色小字的按键名，意思是滑回来松手就取消。
    var body: some View {
        let outline = popup.trayOutline
        let xs = outline.map(\.x), ys = outline.map(\.y)
        let bounds = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                            width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
        let tray = CrossTrayShape(points: outline.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) },
                                  outer: isPad ? 14 : 12, inner: isPad ? 7 : 6)
        ZStack(alignment: .topLeading) {
            tray.fill(Brand.crossTray)
                .shadow(color: Brand.popupShadow, radius: 7, x: 0, y: 5)
                .overlay(tray.stroke(Brand.crossTrayStroke, lineWidth: 1))
                .frame(width: bounds.width, height: bounds.height)
                .offset(x: bounds.minX, y: bounds.minY)
            cell(popup.center) {
                centerLabel
                    .font(.system(size: isPad ? 15 : 13))
                    .foregroundStyle(Brand.crossCenterText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ForEach(CrossPopup.Direction.allCases.filter { popup.options[$0] != nil }, id: \.self) { direction in
                let selected = popup.selected == direction
                let button = RoundedRectangle(cornerRadius: isPad ? 10 : 8, style: .continuous)
                cell(popup.frame(for: direction)) {
                    ZStack {
                        // 底下一条 1pt 暗边，像按键的影子；选中时去掉。
                        if !selected { button.fill(Brand.crossButtonEdge).offset(y: 1) }
                        button.fill(selected ? Brand.purple : Brand.crossButton)
                        Text(popup.options[direction] ?? "")
                            .font(.system(size: isPad ? 26 : (KeyboardMetrics.landscape ? 18 : 22)))
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

    private var centerLabel: Text {
        switch popup.key.kind {
        case .digitPunct: return Text(".,:")
        case .quickPunct(let chinese): return Text(chinese ? "，。" : ",.")
        case .nine(let digit) where digit != "'": return Text(KeyLayout.nineKeyLetters[digit] ?? digit)
        default: return Text("，。?!")
        }
    }
}

/// 十字托盘的外形：CrossTray 算出的多边形，外角 outer、里角 inner 圆角。
struct CrossTrayShape: Shape {
    let points: [CGPoint]
    let outer: CGFloat
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CrossTray.path(points.map { CGPoint(x: $0.x + rect.minX, y: $0.y + rect.minY) }, outer: outer, inner: inner))
    }
}

/// 长按弹出的备选条（对齐清单第 88 条，design/popup-style PS1 ②）：一整块底板（浅色白、深色 #6C6C71，比按键亮一档），
/// 1pt 描边、较深的阴影，左右比格子多留 4（iPad 5）；格子之间 1pt 细线，挨着选中那格的不画。选中那格紫底白字。
struct AlternatesView: View {
    let popup: AlternatesPopup

    private var isPad: Bool { KeyboardMetrics.pad != nil }

    var body: some View {
        let frame = popup.frame
        let cell = AlternatesPopup.cellWidth
        let side: CGFloat = isPad ? 5 : 4
        let radius: CGFloat = isPad ? 14 : 12
        let lineInset: CGFloat = isPad ? 12 : 9
        let board = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // 细线 i 在第 i 格和第 i+1 格之间。
        let dividers = popup.options.indices.dropLast().filter { $0 != popup.selected - 1 && $0 != popup.selected }
        ZStack(alignment: .topLeading) {
            board.fill(Brand.popupBoard)
                .shadow(color: Brand.popupShadow, radius: 7, x: 0, y: 5)
                .overlay(board.strokeBorder(Brand.popupBoardStroke, lineWidth: 1))
                .frame(width: frame.width + side * 2, height: frame.height)
            ForEach(dividers, id: \.self) { index in
                Rectangle().fill(Brand.popupDivider)
                    .frame(width: 1, height: frame.height - lineInset * 2)
                    .offset(x: side + cell * CGFloat(index + 1) - 0.5, y: lineInset)
            }
            HStack(spacing: 0) {
                ForEach(Array(popup.options.enumerated()), id: \.offset) { index, option in
                    Text(option)
                        .font(.system(size: isPad ? 26 : 22))
                        .foregroundStyle(index == popup.selected ? Color.white : Color.primary)
                        .frame(width: cell, height: AlternatesPopup.height - 8)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == popup.selected ? Brand.purple : Color.clear))
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: side)
        }
        .offset(x: frame.minX - side, y: frame.minY)
        .allowsHitTesting(false)
    }
}

/// 「常用 / 剪贴板」右栏（B1，CB1–CB3，对齐清单第 62 条；T97 CA1）。这一栏露出来时有新复制的文字就存成第一条（不粘贴），
/// 上次离开面板以后存进来的标「新」。最上面的虚线行只在两种情况出现：像密码或验证码（不存，点了才读、上屏）；记录关着（点了只粘贴）。
/// 每条一张按键底色卡片，右上角灰色时间，点一下插入、面板不关；长按 0.45 秒弹菜单：粘贴 / 加到常用语 / 复制 / 删除。
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

    /// 「新」标记、竖条圆点的主色：浅色 #5B4BE8，深色 #8B7CF6。
    static let badgeFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255, alpha: 1)
        : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })

    /// 最上面那一行：像密码或验证码时（记录开着），或记录关着时。
    private var showsPrompt: Bool {
        model.clipboardHasNew && (model.clipboardSensitive || !ClipboardHistory.isEnabled)
    }

    var body: some View {
        Group {
            if !model.hasFullAccess {
                fullAccessCard
            } else {
                content
            }
        }
        // 露出来以后才读，不压在面板弹出前。
        .onAppear { DispatchQueue.main.async { model.clipboardColumnShown() } }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if model.clipItems.isEmpty {
                VStack(spacing: 6) {
                    if showsPrompt { promptRow }
                    Spacer(minLength: 0)
                    Text(L("还没有剪贴板记录", "No clipboard history yet", "クリップボードの履歴はまだありません"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("在别的 App 复制文字，再点开这里就会存下来", "Copy text in another app, then open this to keep it",
                           "ほかのアプリでコピーしてからここを開くと保存されます"))
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

    private var footnote: String {
        ClipboardHistory.isEnabled
            ? L("只存在本机 · 最多 \(ClipboardHistory.maxItems) 条 · 24 小时后自动删除 · 长按可加到常用语",
                "Only on this iPhone · up to \(ClipboardHistory.maxItems) · deleted after 24 hours · long-press to add to phrases",
                "この iPhone のみ · 最大 \(ClipboardHistory.maxItems) 件 · 24 時間後に自動削除 · 長押しで定型文に追加")
            : L("剪贴板记录已关闭：粘贴后不保存（App › 键盘 里可以打开）",
                "Clipboard history is off: pasted text isn't kept (turn it on in the app under Keyboard)",
                "クリップボード履歴はオフです：貼り付けたテキストは保存しません（アプリの キーボード でオン）")
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if showsPrompt { promptRow }
                ForEach(model.clipItems) { item in
                    row(item, fresh: ClipboardHistory.isNew(item, since: model.clipNewAfter))
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

    /// 浅紫底、1.5pt 主色虚线框、圆角 9。
    /// 像密码或验证码（CA1 ③）：锁图标 + 两行「点一下粘贴」（14 粗）「密码或验证码，不存记录」（11.5），点了才读、上屏，不存。
    /// 记录关着：原来的一行「有新复制的内容，点一下粘贴」，点了只粘贴。
    private var promptRow: some View {
        let sensitive = model.clipboardSensitive && ClipboardHistory.isEnabled
        return HStack(spacing: 6) {
            Button { model.pasteNewClipboard(save: !sensitive) } label: {
                HStack(spacing: 8) {
                    Image(systemName: sensitive ? "lock" : "doc.on.clipboard").font(.system(size: 15, weight: .semibold))
                    if sensitive {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("点一下粘贴", "Tap to paste", "タップで貼り付け"))
                                .font(.system(size: 14, weight: .semibold))
                            Text(L("密码或验证码，不存记录", "Looks like a password or code, not saved", "パスワードや確認コードは保存しません"))
                                .font(.system(size: 11.5))
                                .opacity(0.8)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    } else {
                        Text(L("有新复制的内容，点一下粘贴", "New copied text. Tap to paste", "新しくコピーした内容があります。タップで貼り付け"))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
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
            if fresh {
                // 「新」：16 高、圆角 5、主色底白字 10.5 粗；下面一行时间（11pt 深紫）。
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("新", "New", "新着"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Self.badgeFill))
                    Text(ClipboardHistory.age(item.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.deepPurple)
                }
                .padding(.top, 1)
            } else {
                Text(ClipboardHistory.age(item.date))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 2)
            }
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
            Text(L("设置 › 通用 › 键盘 › 键盘 › \(Loc.nameInSettings) › 允许完全访问。打开后，默认只在你点开剪贴板时才读剪贴板。",
                   "Settings › General › Keyboard › Keyboards › \(Loc.nameInSettings) › Allow Full Access. By default, the clipboard is read only when you open it here.",
                   "設定 › 一般 › キーボード › キーボード › \(Loc.nameInSettings) › フルアクセスを許可。オンにしても、初期設定ではここを開いたときだけ読み取ります。"))
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


// MARK: - iPad 面板底栏（PK10）

/// iPad 表情、颜文字、常用语和剪贴板面板的底栏：和键盘最下面一排一样高（竖屏 43、横屏 49）、一样离边，
/// 键帽之间一条缝；content 拿到「一格」的宽（按键区宽 / 12.8，和 11 寸 26 键一样），按几格排。
struct PadPanelBar<Content: View>: View {
    let pad: PadMetrics
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) { content(geo.size.width / 12.8) }
        }
        .frame(height: pad.bottomKeyHeight + pad.gap)
        .padding(.bottom, pad.bottom - pad.gap / 2)
    }
}

/// 面板底栏的一颗键：默认功能键灰底，键帽四周缩进半条缝。
struct PadPanelKey<Label: View>: View {
    var fill: Color = KeyStyle.padFunctionKey
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Label

    var body: some View {
        let half = (KeyboardMetrics.pad?.gap ?? 8) / 2
        Button(action: action) {
            KeyCap(fill: fill, insetX: half, insetY: half) {
                content().foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(label)
    }
}

/// 🌐：系统的键盘列表要 UIKit 接触摸（NextKeyboardButton），外面画成功能键。
struct PadGlobeKey: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let half = (KeyboardMetrics.pad?.gap ?? 8) / 2
        KeyCap(fill: KeyStyle.padFunctionKey, insetX: half, insetY: half) {
            NextKeyboardButton(controller: model.controller)
        }
        .accessibilityLabel(L("下一个键盘", "Next keyboard", "次のキーボード"))
    }
}

/// 收起键盘（和键盘右下角那颗一样，正在打的拼音原样留下）。
struct PadDismissKey: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        PadPanelKey(label: L("收起键盘", "Hide keyboard", "キーボードを閉じる"), action: { model.perform(.dismiss) }) {
            Image(systemName: "keyboard.chevron.compact.down").font(KeyStyle.iconFont)
        }
    }
}
