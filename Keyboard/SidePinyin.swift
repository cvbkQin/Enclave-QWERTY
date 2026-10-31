import SwiftUI

// 拼音显示在侧边（F12，功能对照表「拼音显示：上方一行 / 侧边两种模式」）：
// 九宫格打字时左列上三格合成一格拼音列（展开候选时拉长到 4 行），点 ⌄ 换成拼音格子；
// 全键盘候选栏最左边一颗拼音键，点开弹出切法和纠正读法。

/// 侧边拼音列 / 拼音格子 / 拼音键弹框里的一项。
struct SidePinyinItem: Identifiable, Equatable {
    enum Action: Equatable {
        case reading(String)
        case syllable(String)
        case segmentation(String)
        case unselectWord
    }

    var id: String
    var text: String
    var marked: Set<Int> = []
    var action: Action
    /// 纠正读法：和后面的读法之间画一条细线。
    var corrected = false
    /// 分段选过的词：紫色字。
    var word = false
}

extension KeyboardModel {
    /// 九宫格侧边拼音列的各项：分段选过的词（点了退回）、纠正读法、第一个没定的字的读法和单个字母。
    var sidePinyinItems: [SidePinyinItem] {
        guard showsNineKey, isComposing else { return [] }
        var items: [SidePinyinItem] = []
        let words = selectedWords
        if !words.isEmpty {
            items.append(SidePinyinItem(id: "word", text: words, action: .unselectWord, word: true))
        }
        if let reading = correctedReading {
            items.append(SidePinyinItem(id: "reading", text: reading.text, marked: reading.marked,
                                        action: .reading(reading.text), corrected: true))
        }
        for syllable in pinyinOptions {
            items.append(SidePinyinItem(id: "s." + syllable, text: syllable, action: .syllable(syllable)))
        }
        return items
    }

    /// 全键盘拼音键：现在的切法；切法只有一种、也没有纠正读法时不显示这颗键。
    var pinyinKeyTitle: String? {
        guard pinyinSide, !showsNineKey, isComposing, chineseMode else { return nil }
        let segmentations = pinyinSegmentations
        guard segmentations.count > 1 || correctedReading != nil else { return nil }
        return segmentations.first ?? correctedReading?.text
    }

    /// 纠正读法右边的灰字：改了哪个字母（「按错 u → o」）。
    var correctionNote: String? {
        guard let correction = engine.pendingCorrection else { return nil }
        let typed = Array(correction.typed), fixed = Array(correction.corrected)
        if typed.count == fixed.count {
            let diffs = zip(typed, fixed).filter { $0.0 != $0.1 }
            if diffs.count == 1, let diff = diffs.first {
                return L("按错 \(diff.0) → \(diff.1)", "Typo \(diff.0) → \(diff.1)", "打ち間違い \(diff.0) → \(diff.1)")
            }
            if diffs.count == 2 { return L("按反了", "Swapped", "順番違い") }
        } else if typed.count < fixed.count {
            return L("漏打一个字母", "Missed a letter", "1 文字抜け")
        } else {
            return L("多打一个字母", "Extra letter", "1 文字多い")
        }
        return L("纠正拼写", "Corrected", "修正")
    }

    func performSidePinyin(_ action: SidePinyinItem.Action) {
        switch action {
        case .reading(let text): chooseCorrectedReading(text)
        case .syllable(let syllable): choosePinyin(syllable)
        case .segmentation(let segmentation): chooseSegmentation(segmentation)
        case .unselectWord: unselectLastWord()
        }
        closePinyinPickers()
    }
}

private enum SidePinyinStyle {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
    /// 第一项 / 选中项：浅紫底 + 主色字。
    static let firstFill = dynamic(0xE4E0FC, 0x2E2766)
    static let mainText = dynamic(0x5B4BE8, 0xB4A9FF)
    static let divider = dynamic(0xE2E2E7, 0x3A3A3C)
    static let hint = dynamic(0x8E8E93, 0x8E8E93)
    static let cellHeight: CGFloat = 38
}

/// 一项的字：改过的字母浅紫底主色字（同拼音行）。
private struct SidePinyinLabel: View {
    let item: SidePinyinItem
    var size: CGFloat = 17
    var emphasized = false

    var body: some View {
        var runs: [(text: String, marked: Bool)] = []
        for (offset, char) in item.text.enumerated() {
            let isMarked = item.marked.contains(offset)
            if let last = runs.last, last.marked == isMarked {
                runs[runs.count - 1].text.append(char)
            } else {
                runs.append((String(char), isMarked))
            }
        }
        return HStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                Text(run.text)
                    .font(.system(size: size, weight: emphasized || item.word ? .semibold : .regular))
                    .foregroundStyle(run.marked || emphasized || item.word ? SidePinyinStyle.mainText : Color.primary)
                    .background(run.marked ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PinyinRow.markedFill).padding(.horizontal, -1) : nil)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .truncationMode(.head)
    }
}

/// 九宫格侧边拼音列：竖着排，每项高 38；第一项浅紫底；放不下时上下滑，底部渐隐 + ⌄，点 ⌄ 换成拼音格子。
struct SidePinyinColumn: View {
    @ObservedObject var model: KeyboardModel
    let frame: CGRect

    var body: some View {
        let items = model.sidePinyinItems
        let overflow = CGFloat(items.count) * SidePinyinStyle.cellHeight > frame.height - KeyboardMetrics.nineKeyInsetY * 2
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { model.performSidePinyin(item.action) } label: {
                        SidePinyinLabel(item: item, emphasized: index == 0 && !item.word)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: SidePinyinStyle.cellHeight)
                            .background(index == 0 && !item.word ? SidePinyinStyle.firstFill : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    if item.corrected || item.word {
                        Rectangle().fill(SidePinyinStyle.divider).frame(height: 1).padding(.horizontal, 12)
                    }
                }
                if overflow { Color.clear.frame(height: 30) }
            }
        }
        .hidingScrollEdgeEffect()
        .overlay(alignment: .bottom) {
            if overflow {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [KeyStyle.charKey.opacity(0), KeyStyle.charKey], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    Button { model.pinyinGridOpen = true } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SidePinyinStyle.hint)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                }
                .frame(height: 30)
            }
        }
        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous).fill(KeyStyle.charKey))
        .clipShape(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous))
        .padding(.horizontal, KeyboardMetrics.nineKeyInsetX)
        .padding(.vertical, KeyboardMetrics.nineKeyInsetY)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}

/// 九宫格侧边模式点 ⌄：按键区换成拼音格子，一行 4 格、格高 46；最后一行「⌃ 收起」「⌫ 删一个字母」。
struct SidePinyinGrid: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let items = model.sidePinyinItems
        let gap = KeyboardMetrics.nineRowGap
        VStack(spacing: 0) {
            HStack {
                Text(L("选拼音 · 先定第一个字", "Pick pinyin · first character", "ピンインを選ぶ · 最初の字から"))
                Spacer()
                if items.contains(where: { $0.corrected }) {
                    Text(L("改过的字母浅紫标出", "Fixed letters in purple", "直した文字は紫"))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(SidePinyinStyle.hint)
            .padding(.horizontal, 6)
            .frame(height: 24)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { model.performSidePinyin(item.action) } label: {
                            SidePinyinLabel(item: item, emphasized: index == 0 && !item.word)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                                    .fill(index == 0 && !item.word ? SidePinyinStyle.firstFill : KeyStyle.charKey))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
                .padding(.horizontal, KeyboardMetrics.nineKeyInsetX)
            }
            .hidingScrollEdgeEffect()
            HStack(spacing: gap) {
                Button { model.pinyinGridOpen = false } label: {
                    Label(L("收起", "Close", "閉じる"), systemImage: "chevron.up")
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous).fill(KeyStyle.charKey))
                }
                .buttonStyle(KeyPressStyle())
                Button { model.deleteKey() } label: {
                    Label(L("删一个字母", "Delete a letter", "1 文字削除"), systemImage: "delete.left")
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous).fill(KeyStyle.charKey))
                }
                .buttonStyle(KeyPressStyle())
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
            .font(.system(size: 16))
            .foregroundStyle(SidePinyinStyle.hint)
            .padding(.horizontal, KeyboardMetrics.nineKeyInsetX)
            .padding(.top, gap)
            .padding(.bottom, KeyboardMetrics.nineKeyInsetY)
        }
        .padding(.horizontal, KeyboardMetrics.nineSideMargin - KeyboardMetrics.sidePadding - KeyboardMetrics.nineKeyInsetX)
    }
}

/// 全键盘侧边模式：候选栏最左边的拼音键，高 32、圆角 9；打开弹框时浅紫底主色字。
struct PinyinKey: View {
    @ObservedObject var model: KeyboardModel
    let title: String

    var body: some View {
        let open = model.pinyinPopoverOpen
        Button { model.pinyinPopoverOpen.toggle() } label: {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 16, weight: open ? .semibold : .regular))
                    .foregroundStyle(open ? SidePinyinStyle.mainText : Color.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12))
                    .foregroundStyle(open ? SidePinyinStyle.mainText : SidePinyinStyle.hint)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(open ? SidePinyinStyle.firstFill : KeyStyle.charKey))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(maxWidth: 150)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 拼音键弹框：「切法」列出所有切法（现在的 ✓），有纠正读法时再一组「纠正」，右边灰字写改了哪个字母。宽 230、圆角 13、每项高 38。
struct PinyinKeyPopover: View {
    @ObservedObject var model: KeyboardModel

    static let width: CGFloat = 230

    var body: some View {
        let segmentations = model.pinyinSegmentations
        let reading = model.correctedReading
        VStack(alignment: .leading, spacing: 0) {
            if !segmentations.isEmpty {
                header(L("切法", "Splits", "区切り"))
                ForEach(Array(segmentations.enumerated()), id: \.element) { index, option in
                    row(SidePinyinItem(id: option, text: option, action: .segmentation(option)), selected: index == 0, note: nil)
                }
            }
            if let reading {
                header(L("纠正", "Correction", "修正"))
                row(SidePinyinItem(id: "reading", text: reading.text, marked: reading.marked, action: .reading(reading.text)),
                    selected: false, note: model.correctionNote)
            }
        }
        .padding(6)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Brand.panelFill)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18), radius: 12, y: 6))
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(SidePinyinStyle.hint)
            .padding(.horizontal, 10)
            .frame(height: 24, alignment: .bottomLeading)
    }

    private func row(_ item: SidePinyinItem, selected: Bool, note: String?) -> some View {
        Button { model.performSidePinyin(item.action) } label: {
            HStack {
                SidePinyinLabel(item: item, emphasized: selected)
                Spacer(minLength: 8)
                if let note { Text(note).font(.system(size: 12)).foregroundStyle(SidePinyinStyle.hint) }
                if selected { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(SidePinyinStyle.mainText) }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? SidePinyinStyle.firstFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
    }
}
