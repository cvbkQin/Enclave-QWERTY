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

/// 「选拼音」打开的整页音节，选一个回到键盘。
struct PinyinPanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 0)], spacing: 0) {
                    ForEach(model.pinyinOptions, id: \.self) { syllable in
                        Button { model.choosePinyin(syllable) } label: {
                            Text(syllable).font(.system(size: 19)).foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .hidingScrollEdgeEffect()
            VStack(spacing: 0) {
                FunctionKey(title: "返回") { model.closePanel() }.frame(height: KeyboardMetrics.slotHeight)
                RepeatingKey(systemImage: "delete.left") { model.deleteKey() }.frame(height: KeyboardMetrics.slotHeight)
                FunctionKey(title: "重输") { model.clearComposition() }.frame(height: KeyboardMetrics.slotHeight)
                Spacer(minLength: 0)
            }
            .frame(width: 64)
        }
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
                            .frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
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
                        .fill(index == popup.selected ? Color.accentColor : Color.clear))
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyStyle.charKey)
            .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1))
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }
}
