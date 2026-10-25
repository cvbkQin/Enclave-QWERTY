import SwiftUI

/// 键盘常用语：九宫格「常用」面板里点着输入的词句，比如邮箱、地址、信用代码。
/// 和常用词分开存：不用拼音，也不进候选，只按用户排的顺序显示在面板里。
@MainActor
final class KeyboardPhrasesModel: ObservableObject {
    @Published var phrases = CommonWordStore.keyboardTexts {
        didSet { if phrases != oldValue { CommonWordStore.keyboardTexts = phrases } }
    }

    func reload() { phrases = CommonWordStore.keyboardTexts }

    /// 新加的排在最后；已经有的不重复加。
    func add(_ text: String) {
        if !phrases.contains(text) { phrases.append(text) }
    }

    /// 改成已经有的另一条时，两条并成一条。
    func replace(_ old: String, with text: String) {
        guard let index = phrases.firstIndex(of: old), old != text else { return }
        if phrases.contains(text) { phrases.remove(at: index) } else { phrases[index] = text }
    }

    func delete(_ text: String) { phrases.removeAll { $0 == text } }

    func move(from source: IndexSet, to destination: Int) {
        phrases.move(fromOffsets: source, toOffset: destination)
    }
}

/// 键盘常用语页（W8）：拖 ≡ 排序、点一行编辑、左滑删除、＋ 添加，下面预览键盘里的样子。
struct KeyboardPhrasesView: View {
    @StateObject private var model = KeyboardPhrasesModel()
    @State private var adding = false
    /// 正在编辑的那一条。
    @State private var editing: Phrase?

    struct Phrase: Identifiable {
        let text: String
        var id: String { text }
    }

    var body: some View {
        List {
            Section {
                if model.phrases.isEmpty {
                    Text(L("还没有常用语。点「添加」加一条，比如邮箱、地址、公司税号。", "No phrases yet. Tap Add for things like your email, address or company ID.", "まだありません。「追加」でメールアドレスや住所などを入れてください。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.phrases, id: \.self) { text in
                    HStack(spacing: 12) {
                        Button { editing = Phrase(text: text) } label: {
                            Text(text)
                                .font(.system(size: 16))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: 0xC7C7CC))
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.delete(text) } label: { Label(L("删除", "Delete", "削除"), systemImage: "trash") }
                            .tint(.red)
                    }
                }
                .onMove(perform: model.move)
                Button { adding = true } label: {
                    Label(L("添加", "Add", "追加"), systemImage: "plus")
                        .foregroundStyle(AppColor.purple)
                }
            } footer: {
                Text(L("在键盘九宫格左边点「常用」，点一下就输入，不用打拼音。按住右边的 ≡ 上下拖动排顺序，左滑删除，点一下编辑。",
                       "Tap 常用 on the left of the 9-key keyboard, then tap a phrase to enter it. No pinyin needed. Touch and hold ≡ to reorder, swipe left to delete, tap to edit.",
                       "9 キーの左にある「常用」から、タップするだけで入力できます。≡ を長押しして並べ替え、左にスワイプで削除、タップで編集。"))
            }
            if !model.phrases.isEmpty {
                Section {
                    KeyboardWordsPreview(texts: model.phrases)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(L("键盘里的样子", "On the keyboard", "キーボードでの表示"))
                } footer: {
                    Text(L("一行四格：短词一格，邮箱这类两格，地址和长句占一整行。", "Four per row: short words take one cell, emails two, addresses and sentences a full row.", "1 行 4 マス：短い語は 1 マス、メールアドレスなどは 2 マス、住所や長い文は 1 行。"))
                }
            }
        }
        .environment(\.defaultMinListHeaderHeight, 6)
        .tint(AppColor.purple)
        .navigationTitle(L("键盘常用语", "Keyboard Phrases", "キーボードの定型文"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            PhraseEditor(original: nil) { model.add($0) } onDelete: {}
        }
        .sheet(item: $editing) { phrase in
            PhraseEditor(original: phrase.text) { model.replace(phrase.text, with: $0) } onDelete: { model.delete(phrase.text) }
        }
        .onAppear { model.reload() }
    }
}

/// 添加 / 编辑一条常用语：只有一栏，什么字都行。
private struct PhraseEditor: View {
    let original: String?
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(original: String?, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: original ?? "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("比如：邮箱、地址、税号", "e.g. email, address, company ID", "例：メールアドレス、住所"), text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                } footer: {
                    Text(L("中文、英文、数字都可以，不用填拼音。", "Any text works. No pinyin needed.", "どんな文字でも登録できます。ピンインは不要です。"))
                }
                if !trimmed.isEmpty {
                    Section(L("键盘里的样子", "On the keyboard", "キーボードでの表示")) {
                        KeyboardWordsPreview(texts: [trimmed])
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if original != nil {
                    Section {
                        Button(L("删除这条", "Delete", "削除"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(original == nil ? L("添加常用语", "Add Phrase", "定型文を追加") : L("编辑常用语", "Edit Phrase", "定型文を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消", "Cancel", "キャンセル")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存", "Save", "保存")) {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .tint(AppColor.purple)
            .onAppear { if original == nil { focused = true } }
        }
    }
}

/// 「键盘里的样子」：灰底 #DCDEE4。按键盘的实际宽度分好行（和键盘面板一致），再按比例缩小画。
private struct KeyboardWordsPreview: View {
    let texts: [String]

    private static let padding: CGFloat = 8
    private static let maxRows = 4

    var body: some View {
        let gridWidth = UIScreen.main.bounds.width - KeyboardWordsLayout.sideMargin * 2
        let rows = Array(KeyboardWordsLayout.rows(texts, gridWidth: gridWidth).prefix(Self.maxRows))
        // 行高按列表行的宽度估（分组列表两边各留 20），实际宽度用 GeometryReader 量。
        let estimatedScale: CGFloat = (UIScreen.main.bounds.width - 40 - Self.padding * 2) / gridWidth
        let rowCount = CGFloat(rows.count)
        let rowsHeight: CGFloat = rowCount * KeyboardWordsLayout.cellHeight + (rowCount - 1) * KeyboardWordsLayout.gap
        let height: CGFloat = rowsHeight * estimatedScale + Self.padding * 2
        GeometryReader { geo in
            let inner: CGFloat = geo.size.width - Self.padding * 2
            let scale: CGFloat = inner / gridWidth
            let gap: CGFloat = KeyboardWordsLayout.gap * scale
            let column: CGFloat = KeyboardWordsLayout.columnWidth(gridWidth: gridWidth) * scale
            VStack(alignment: .leading, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.self) { cell in
                            PreviewCell(text: cell.text, span: cell.span, column: column, gap: gap, scale: scale)
                        }
                    }
                }
            }
            .padding(Self.padding)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.18, alpha: 1) : UIColor(red: 0xDC / 255, green: 0xDE / 255, blue: 0xE4 / 255, alpha: 1)
        })))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 预览里的一格，按缩放比例画。
private struct PreviewCell: View {
    let text: String
    let span: Int
    let column: CGFloat
    let gap: CGFloat
    let scale: CGFloat

    var body: some View {
        let spans = CGFloat(span)
        let width: CGFloat = column * spans + gap * (spans - 1)
        let height: CGFloat = KeyboardWordsLayout.cellHeight * scale
        return Text(text)
            .font(.system(size: KeyboardWordsLayout.fontSize * scale))
            .lineLimit(1)
            .padding(.horizontal, KeyboardWordsLayout.textPadding * scale)
            .frame(width: width, height: height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).fill(Color(.systemBackground)))
    }
}

