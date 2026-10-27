import NaturalLanguage
import SwiftUI

/// 分词面板拆出来的一块：词或标点，按原文顺序。
struct WordToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let punctuation: Bool
    /// 拉丁字母的词：拼起来时和前一个英文词之间加空格。
    let latin: Bool

    /// 用系统分词（NLTokenizer）拆，英文按词；词和词中间的标点各成一块，空白丢掉。
    static func split(_ text: String) -> [WordToken] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var pieces: [(String, Bool)] = []
        var cursor = text.startIndex
        func addGap(_ gap: Substring) {
            for char in gap where !char.isWhitespace { pieces.append((String(char), true)) }
        }
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            addGap(text[cursor..<range.lowerBound])
            pieces.append((String(text[range]), false))
            cursor = range.upperBound
            return true
        }
        addGap(text[cursor...])
        return pieces.enumerated().map { index, piece in
            WordToken(id: index, text: piece.0, punctuation: piece.1,
                      latin: !piece.1 && piece.0.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) })
        }
    }

    /// 按原顺序拼起来，中间不加空格，两个英文词之间加一个空格。
    static func join(_ tokens: [WordToken]) -> String {
        var out = ""
        var previousLatin = false
        for token in tokens {
            if token.latin && previousLatin { out += " " }
            out += token.text
            previousLatin = token.latin
        }
        return out
    }
}

/// 长按结果卡打开的分词面板（BB1–BB4）：盖住按键区，直角框里是提示行、词块、底栏。
/// 点一下选中，按住横着划连续选（划过的浅紫描边，松手变选中），划回来取消；竖着划是滚动。
struct WordPanel: View {
    @ObservedObject var model: KeyboardModel
    @State private var tokens: [WordToken] = []
    @State private var selected: Set<Int> = []
    /// 正在横着划：起点那块决定是选还是取消，划过的块 id。
    @State private var sweep: (adding: Bool, ids: Set<Int>)?
    @State private var sweepStart: Int?
    @State private var frames: [Int: CGRect] = [:]
    @State private var scrolled = false

    private static let space = "wordPanel"

    var body: some View {
        VStack(spacing: 8) {
            hintRow
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear.preference(key: WordScrollOffset.self, value: geo.frame(in: .named(Self.space + "scroll")).minY)
                    }
                    .frame(height: 0)
                    WordFlow(spacing: 6, lineSpacing: 7) {
                        ForEach(tokens) { token in chip(token) }
                    }
                    .coordinateSpace(name: Self.space)
                    .onPreferenceChange(WordFrames.self) { frames = $0 }
                    .simultaneousGesture(sweepGesture)
                    .padding(.bottom, 14)
                }
            }
            .coordinateSpace(name: Self.space + "scroll")
            .onPreferenceChange(WordScrollOffset.self) { scrolled = $0 < -1 }
            .overlay(alignment: .top) { fade(top: true).opacity(scrolled ? 1 : 0) }
            .overlay(alignment: .bottom) { fade(top: false) }
            bottomBar
        }
        .padding(8)
        .background(Rectangle().fill(Brand.wordPanelFill))
        .overlay(Rectangle().strokeBorder(Brand.wordPanelStroke, lineWidth: 1))
        .onAppear { tokens = WordToken.split(model.wordPanelText) }
    }

    private var hintRow: some View {
        HStack {
            Text(selected.isEmpty
                 ? L("点选，或按住横着划选；竖着划是滚动", "Tap or drag sideways to select; swipe up and down to scroll", "タップか横になぞって選択、縦はスクロール")
                 : L("已选 \(selected.count) 个", "\(selected.count) selected", "\(selected.count) 個選択"))
            Spacer(minLength: 8)
            Text(L("长按结果卡打开", "Long-press the result to open", "結果を長押しで開く"))
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func fade(top: Bool) -> some View {
        LinearGradient(colors: [Brand.wordPanelFill, Brand.wordPanelFill.opacity(0)],
                       startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            .frame(height: top ? 18 : 22)
            .allowsHitTesting(false)
    }

    private func isOn(_ id: Int) -> Bool {
        if let sweep, sweep.ids.contains(id) { return sweep.adding }
        return selected.contains(id)
    }

    private func chip(_ token: WordToken) -> some View {
        let on = isOn(token.id)
        let swept = sweep?.ids.contains(token.id) == true && !selected.contains(token.id) && sweep?.adding == true
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Text(token.text)
            .font(.system(size: 18))
            .foregroundStyle(on ? Color.white : (token.punctuation ? Color.secondary : Color.primary))
            .lineLimit(1)
            .padding(.horizontal, token.punctuation ? 7 : 11)
            .frame(minWidth: token.punctuation ? 26 : 36)
            .frame(height: 36)
            .background(shape.fill(on && !swept ? Brand.purple : KeyStyle.charKey))
            .overlay(shape.strokeBorder(Brand.rowStroke, lineWidth: swept ? 1.5 : 0))
            .overlay(swept ? shape.fill(Brand.rowStroke.opacity(0.15)) : nil)
            .background(GeometryReader { geo in
                Color.clear.preference(key: WordFrames.self, value: [token.id: geo.frame(in: .named(Self.space))])
            })
            .onTapGesture { toggle(token.id) }
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        model.keyFeedback(for: .space)
    }

    private func token(at point: CGPoint) -> Int? {
        frames.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
    }

    /// 横着划连续选：从起点那块到手指所在那块（按原文顺序），划回来就缩回去；竖着划交给滚动。
    private var sweepGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if sweep == nil {
                    guard abs(value.translation.width) > abs(value.translation.height),
                          let start = token(at: value.startLocation) else { return }
                    sweepStart = start
                    sweep = (!selected.contains(start), [start])
                }
                guard let start = sweepStart, let current = token(at: value.location) else { return }
                let ids = Set(min(start, current)...max(start, current))
                if ids != sweep?.ids { sweep?.ids = ids }
            }
            .onEnded { _ in
                if let sweep {
                    if sweep.adding { selected.formUnion(sweep.ids) } else { selected.subtract(sweep.ids) }
                }
                sweep = nil
                sweepStart = nil
            }
    }

    private var chosenText: String {
        WordToken.join(tokens.filter { selected.contains($0.id) })
    }

    private var bottomBar: some View {
        GeometryReader { geo in
            // 插入、复制一样大；「全选」和「×」一样大，宽度比 1.5 : 1。
            let gap: CGFloat = 6
            let unit = (geo.size.width - gap * 3) / 5
            let empty = selected.isEmpty
            let all = !tokens.isEmpty && selected.count == tokens.count
            HStack(spacing: gap) {
                barButton(L("插入", "Insert", "挿入"), fill: AnyShapeStyle(LinearGradient(colors: Brand.gradient, startPoint: .leading, endPoint: .trailing)),
                          text: .white, width: unit * 1.5, enabled: !empty) { model.insertWords(chosenText) }
                barButton(L("复制", "Copy", "コピー"), fill: AnyShapeStyle(LinearGradient(colors: Brand.copyGradient, startPoint: .leading, endPoint: .trailing)),
                          text: .white, width: unit * 1.5, enabled: !empty) { model.copyWords(chosenText) }
                barButton(all ? L("全不选", "None", "全解除") : L("全选", "All", "全選択"), fill: AnyShapeStyle(KeyStyle.charKey),
                          text: .primary, width: unit, enabled: !tokens.isEmpty) {
                    selected = all ? [] : Set(tokens.map(\.id))
                }
                barButton("", icon: "xmark", fill: AnyShapeStyle(KeyStyle.charKey), text: .primary, width: unit, enabled: true) {
                    model.closePanel()
                }
                .accessibilityLabel(L("关闭", "Close", "閉じる"))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 40)
    }

    private func barButton(_ title: String, icon: String? = nil, fill: AnyShapeStyle, text: Color, width: CGFloat,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                } else {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(text)
            .frame(width: width, height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct WordFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct WordScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 词块从左往右排，排满换行。
private struct WordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                let fitted = min(size.width, bounds.width)
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                                      proposal: ProposedViewSize(width: fitted, height: size.height))
            }
        }
    }

    private struct Row { var items: [(Int, CGFloat)] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if !row.items.isEmpty && row.width + spacing + w > width {
                rows.append(row)
                row = Row(y: row.y + row.height + lineSpacing)
            }
            row.items.append((index, row.items.isEmpty ? 0 : row.width + spacing))
            row.width = row.items.count == 1 ? w : row.width + spacing + w
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
