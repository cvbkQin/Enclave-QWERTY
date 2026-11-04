import SwiftUI

/// 键盘常用语：九宫格「常用 / 剪贴板」左栏里点着输入的词句，比如邮箱、地址、信用代码（对齐清单第 62 条，CW4）。
/// 每条有标题（可空）、内容、简码（可空）。填了简码的，打这个简码时内容排在候选第一；没简码的不进候选。
@MainActor
final class KeyboardPhrasesModel: ObservableObject {
    @Published var phrases = CommonWordStore.keyboardPhrases {
        didSet { if phrases != oldValue { CommonWordStore.keyboardPhrases = phrases } }
    }
    /// 显示方式：和键盘左栏共用一个值。
    @Published var display = CommonWordStore.phraseDisplay {
        didSet { if display != oldValue { CommonWordStore.phraseDisplay = display } }
    }

    func reload() {
        phrases = CommonWordStore.keyboardPhrases
        display = CommonWordStore.phraseDisplay
    }

    /// 新加的排在最后；内容已经有的那条，用新填的标题、简码更新它。
    func add(_ phrase: KeyboardPhrase) {
        if let index = phrases.firstIndex(where: { $0.text == phrase.text }) {
            phrases[index] = phrase
        } else {
            phrases.append(phrase)
        }
    }

    /// 改成内容已有的另一条时，两条并成一条（留原来这条的位置）。
    func replace(_ old: KeyboardPhrase, with phrase: KeyboardPhrase) {
        guard let index = phrases.firstIndex(where: { $0.text == old.text }) else { return }
        var list = phrases
        list[index] = phrase
        if phrase.text != old.text, let other = list.indices.first(where: { $0 != index && list[$0].text == phrase.text }) {
            list.remove(at: other)
        }
        phrases = KeyboardPhrase.merged(list)
    }

    func delete(_ phrase: KeyboardPhrase) { phrases.removeAll { $0.text == phrase.text } }

    func move(from source: IndexSet, to destination: Int) {
        phrases.move(fromOffsets: source, toOffset: destination)
    }
}

/// 键盘常用语页（CW4）：分组头右边切换钮（和键盘共用），拖 ≡ 排序、点一行编辑、左滑删除、＋ 添加，下面「键盘里看起来」。
struct KeyboardPhrasesView: View {
    @StateObject private var model = KeyboardPhrasesModel()
    @State private var adding = false
    /// 正在编辑的那一条。
    @State private var editing: KeyboardPhrase?

    var body: some View {
        List {
            Section {
                if model.phrases.isEmpty {
                    Text(L("还没有常用语。点「添加」加一条，比如邮箱、地址、公司税号。", "No phrases yet. Tap Add for things like your email, address or company ID.", "まだありません。「追加」でメールアドレスや住所などを入れてください。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.phrases) { phrase in
                    HStack(spacing: 12) {
                        Button { editing = phrase } label: {
                            PhraseRow(phrase: phrase, display: model.display)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: 0xC7C7CC))
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.delete(phrase) } label: { Label(L("删除", "Delete", "削除"), systemImage: "trash") }
                            .tint(.red)
                    }
                }
                .onMove(perform: model.move)
                Button { adding = true } label: {
                    Label(L("添加", "Add", "追加"), systemImage: "plus")
                        .foregroundStyle(AppColor.purple)
                }
            } header: {
                HStack {
                    Text(L("常用语 \(model.phrases.count)", "Phrases \(model.phrases.count)", "定型文 \(model.phrases.count)"))
                    Spacer()
                    if !model.phrases.isEmpty {
                        DisplayToggle(display: $model.display)
                    }
                }
                .textCase(nil)
            } footer: {
                Text(L("在键盘九宫格左边点「常用/剪贴板」，左栏就是这些，点一下就输入。按住 ≡ 排顺序，左滑删除，点一下编辑。",
                       "Tap 常用/剪贴板 on the left of the 9-key keyboard: these are in the left column. Tap one to enter it. Touch and hold ≡ to reorder, swipe left to delete, tap to edit.",
                       "9 キーの左の「常用/剪贴板」を開くと左の列にこれらが並び、タップで入力できます。≡ を長押しで並べ替え、左にスワイプで削除、タップで編集。"))
            }
            if !model.phrases.isEmpty {
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("键盘里看起来", "On the keyboard", "キーボードでの表示"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        KeyboardColumnPreview(phrases: model.phrases, display: model.display)
                    }
                    .dashFormCard()
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
            PhraseEditor(original: phrase) { model.replace(phrase, with: $0) } onDelete: { model.delete(phrase) }
        }
        .onAppear { model.reload() }
    }
}

/// 分组头右边的切换钮：浅紫底、紫字、⇄ + 当前方式，点一下换下一种（标题和内容 → 标题 → 内容）。
private struct DisplayToggle: View {
    @Binding var display: PhraseDisplay

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { display = display.next } } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold))
                Text(display.name).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppColor.deepPurple)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColor.purple.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("显示方式：\(display.name)", "Show: \(display.name)", "表示：\(display.name)"))
    }
}

/// 列表里的一行：标题紫色粗体 15.5、下行内容次要色 13.5 一行省略；没标题的只显示内容（最多两行）。
/// 填了简码的在标题（或内容）后面带「简码 xx」小标签。「标题」方式只列标题（没标题的显示内容，灰色）；「内容」方式只列内容。
private struct PhraseRow: View {
    let phrase: KeyboardPhrase
    let display: PhraseDisplay

    var body: some View {
        let title = display == .content ? nil : phrase.displayTitle
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let title {
                    Text(title).font(.system(size: 15.5, weight: .bold)).foregroundStyle(AppColor.deepPurple).lineLimit(1)
                } else {
                    Text(display == .title ? phrase.flattened : phrase.text)
                        .font(.system(size: 16))
                        .foregroundStyle(display == .title ? Color.secondary : Color.primary)
                        .lineLimit(display == .title ? 1 : 2)
                }
                if !phrase.shortcut.isEmpty { ShortcutTag(code: phrase.shortcut).layoutPriority(1) }
            }
            if title != nil, display == .both {
                Text(phrase.flattened).font(.system(size: 13.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// 「键盘里看起来」：按当前方式画出键盘左栏的样子（灰底 #DCDEE4），最多画几条。
private struct KeyboardColumnPreview: View {
    let phrases: [KeyboardPhrase]
    let display: PhraseDisplay

    private static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.18, alpha: 1) : UIColor(red: 0xDC / 255, green: 0xDE / 255, blue: 0xE4 / 255, alpha: 1)
    })

    var body: some View {
        Group {
            if display == .title {
                PhraseFlow(spacing: 5) {
                    ForEach(phrases.prefix(12)) { phrase in
                        PhraseChip(phrase: phrase, accent: AppColor.deepPurple, fill: Color(.systemBackground))
                    }
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(phrases.prefix(3)) { phrase in
                        PhraseCard(phrase: phrase, showsTitle: display == .both, accent: AppColor.deepPurple, fill: Color(.systemBackground))
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.background))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// 添加 / 编辑一条常用语（CW4）：一个分组三行，排法照常用词编辑页（左边 36pt 栏名，右边输入框，下面一行说明）。
/// 下面「打简码时的样子」预览候选第一位；编辑时最下面「删除这条常用语」。
private struct PhraseEditor: View {
    let original: KeyboardPhrase?
    let onSave: (KeyboardPhrase) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var shortcut: String
    @FocusState private var focused: Bool

    init(original: KeyboardPhrase?, onSave: @escaping (KeyboardPhrase) -> Void, onDelete: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: original?.title ?? "")
        _text = State(initialValue: original?.text ?? "")
        _shortcut = State(initialValue: original?.shortcut ?? "")
    }

    private var draft: KeyboardPhrase {
        KeyboardPhrase(title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10)),
                       text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                       shortcut: CommonWordStore.normalizeCode(shortcut))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(L("标题", "Title", "タイトル"),
                          note: L("可不填。键盘里显示在内容上面，一眼找到是哪条；最多 10 个字", "Optional. Shown above the text on the keyboard so you can find it fast. Up to 10 characters",
                                  "任意。キーボードで内容の上に表示され、すぐ見つけられます。10 文字まで")) {
                        TextField(L("比如：公司地址", "e.g. Office address", "例：会社の住所"), text: $title)
                            // 打字时不截：框里的字加上正在拼的拼音（marked text，空格也算）超过 10 个就截的话，
                            // 拼音会被当成已输入的字母留在框里（录屏 11-02 14:11）。10 个字的上限在保存时截（draft）。
                    }
                    field(L("内容", "Text", "内容"),
                          note: L("点一下输入的就是这段；中文、英文、数字都可以", "This is what gets entered when you tap it. Any text works", "タップで入力されるのはこの文です。どんな文字でも可")) {
                        TextField(L("比如：邮箱、地址、税号", "e.g. email, address, company ID", "例：メールアドレス、住所"), text: $text, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($focused)
                    }
                    field(L("简码", "Shortcut", "略語"),
                          note: L("可不填。打这几个字母，这段排在候选第一", "Optional. Type these letters and this text comes first in the candidates", "任意。この文字を入力すると候補の先頭に出ます")) {
                        TextField(L("比如 gsdz", "e.g. gsdz", "例：gsdz"), text: Binding(get: { shortcut }, set: { shortcut = CommonWordStore.normalizeCode($0) }))
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                    }
                }
                if !draft.shortcut.isEmpty {
                    Section {
                        ShortcutPreview(phrase: draft)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text(L("打简码时的样子", "When you type the shortcut", "略語を入力したとき"))
                    } footer: {
                        Text(L("候选里显示内容，不显示标题；太长的末尾省略，选中后输入完整一段。", "Candidates show the text, not the title. Long text is cut off, but the whole text is entered.",
                               "候補にはタイトルでなく内容が出ます。長い場合は末尾を省略し、選ぶと全文を入力します。"))
                    }
                }
                if original != nil {
                    Section {
                        Button(L("删除这条常用语", "Delete this phrase", "この定型文を削除"), role: .destructive) {
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
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.text.isEmpty)
                }
            }
            .tint(AppColor.purple)
            .onAppear { if original == nil { focused = true } }
        }
    }

    private func field<Content: View>(_ name: String, note: String, @ViewBuilder input: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(name).frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                input()
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 「打 gsdz」：候选行第一位是内容（紫色、太长末尾省略、右上小紫点），后面两个普通候选。
private struct ShortcutPreview: View {
    let phrase: KeyboardPhrase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("打 \(phrase.shortcut)", "Type \(phrase.shortcut)", "\(phrase.shortcut) と入力"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Text(phrase.text.isEmpty ? L("这段内容", "Your text", "この内容") : phrase.flattened)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.purple)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Color(hex: 0x8B7CF6)).frame(width: 5, height: 5).offset(x: 6, y: 1)
                    }
                Text("公司").font(.system(size: 17))
                Text("高速").font(.system(size: 17))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
    }
}
