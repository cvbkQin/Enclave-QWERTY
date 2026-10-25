import SwiftUI
import UniformTypeIdentifiers

/// 常用词的来源标签：字色和底色。
extension CommonWord.Source {
    var title: String {
        switch self {
        case .manual: return L("手动", "Added", "手動")
        case .imported: return L("导入", "Imported", "読み込み")
        case .textReplacement: return L("文本替换", "Text Replacement", "ユーザ辞書")
        case .contact: return L("通讯录", "Contacts", "連絡先")
        }
    }

    /// 分段控件里用的短名，英文、日文五段放得下。
    var shortTitle: String {
        switch self {
        case .textReplacement: return L("文本替换", "System", "辞書")
        default: return title
        }
    }

    var colors: (text: Color, fill: Color) {
        switch self {
        case .manual: return (Color(hex: 0x4A3BD6), Color(hex: 0xECEAFD))
        case .imported: return (Color(hex: 0xA15C00), Color(hex: 0xFFF1DC))
        case .textReplacement: return (Color(hex: 0x1F7A45), Color(hex: 0xE3F4EA))
        case .contact: return (Color(hex: 0x1D5FC2), Color(hex: 0xE6F0FF))
        }
    }
}

/// App 里的常用词，加、改、删、导入后马上存，键盘下次出现时读到。
@MainActor
final class CommonWordsModel: ObservableObject {
    @Published var words = CommonWordStore.load() {
        didSet { if words != oldValue { CommonWordStore.save(words) } }
    }
    @Published private(set) var lexicon = CommonWordStore.lexicon
    @Published var usesTextReplacement = CommonWordStore.usesTextReplacement {
        didSet { CommonWordStore.usesTextReplacement = usesTextReplacement }
    }
    @Published var usesContacts = CommonWordStore.usesContacts {
        didSet { CommonWordStore.usesContacts = usesContacts }
    }
    /// 放到键盘「常用」面板的词，按键盘里的顺序。
    @Published var keyboard = CommonWordStore.keyboardTexts {
        didSet { if keyboard != oldValue { CommonWordStore.keyboardTexts = keyboard } }
    }

    /// 只列出打开了开关的系统来源。
    var all: [CommonWord] {
        words + lexicon.filter {
            ($0.source == .textReplacement && usesTextReplacement) || ($0.source == .contact && usesContacts)
        }
    }

    func count(_ source: CommonWord.Source?) -> Int {
        all.filter { source == nil || $0.source == source }.count
    }

    /// 键盘里的词，按键盘顺序；系统来源关了开关的不算。
    var keyboardWords: [CommonWord] {
        let words = all
        return keyboard.compactMap { text in words.first { $0.text == text } }
    }

    func isOnKeyboard(_ word: CommonWord) -> Bool { keyboard.contains(word.text) }

    /// 点 ☆ / ★：放到键盘（排在最后）或拿掉。
    func toggleKeyboard(_ word: CommonWord) {
        if isOnKeyboard(word) { removeFromKeyboard(word) } else { addToKeyboard([word.text]) }
    }

    func addToKeyboard(_ texts: [String]) {
        for text in texts where !keyboard.contains(text) { keyboard.append(text) }
    }

    /// 只是不放到键盘，词本身还在。
    func removeFromKeyboard(_ word: CommonWord) {
        keyboard.removeAll { $0 == word.text }
    }

    /// 键盘标签里拖动排序。列表只显示还在的词，按这些词在 keyboard 里的位置挪。
    func moveKeyboard(from source: IndexSet, to destination: Int) {
        var shown = keyboardWords.map(\.text)
        shown.move(fromOffsets: source, toOffset: destination)
        keyboard = shown + keyboard.filter { !shown.contains($0) }
    }

    func reload() {
        words = CommonWordStore.load()
        lexicon = CommonWordStore.lexicon
        keyboard = CommonWordStore.keyboardTexts
    }

    func save(_ word: CommonWord) {
        if let index = words.firstIndex(where: { $0.id == word.id }) {
            // 改了词本身，键盘里的那一条跟着改。
            let old = words[index].text
            words[index] = word
            if old != word.text, let position = keyboard.firstIndex(of: old) {
                if keyboard.contains(word.text) { keyboard.remove(at: position) } else { keyboard[position] = word.text }
            }
        } else {
            words.insert(word, at: 0)
        }
    }

    func delete(_ word: CommonWord) {
        words.removeAll { $0.id == word.id }
        if !all.contains(where: { $0.text == word.text }) { keyboard.removeAll { $0 == word.text } }
    }
}

/// 常用词页：上面分「键盘」「全部」两个标签。
/// 全部（W2 / W9）：搜索、按来源筛选、点一行编辑、左滑删除、点 ☆ 放到键盘、从文件导入、系统来源开关。
/// 键盘（W8）：放到键盘「常用」面板的词，拖 ≡ 排序、点 ★ 或左滑拿掉、添加到键盘，下面预览键盘里的样子。
struct CommonWordsView: View {
    enum Tab: Hashable { case keyboard, all }

    @StateObject private var model = CommonWordsModel()
    @State private var tab: Tab
    @State private var search = ""
    @State private var filter: CommonWord.Source?
    @State private var editing: CommonWord?
    @State private var adding = false
    @State private var addingToKeyboard = false
    @State private var readOnly: CommonWord?
    @State private var importing = false
    @State private var preview: ImportPreview?

    init(tab: Tab = .all) {
        _tab = State(initialValue: tab)
    }

    private var query: (text: String, code: String) {
        let text = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (text, CommonWordStore.normalizeCode(text))
    }

    private func matches(_ word: CommonWord) -> Bool {
        let (text, code) = query
        return text.isEmpty || word.text.lowercased().contains(text) || (!code.isEmpty && word.codes.contains { $0.contains(code) })
    }

    private var shown: [CommonWord] {
        model.all.filter { (filter == nil || $0.source == filter) && matches($0) }
    }

    var body: some View {
        List {
            if KeyboardStatus.fullAccess == false {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("常用词还没同步到键盘", "My Words aren't on the keyboard yet", "ユーザ辞書はまだキーボードに反映されていません")).font(.subheadline.weight(.semibold))
                            Text(L("键盘开了「允许完全访问」才会用上这里的词。", "The keyboard uses these words once Allow Full Access is on.", "キーボードで「フルアクセスを許可」をオンにすると使われます。")).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Color.orange.opacity(0.12))
            }
            Section {
                tabBar
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if tab == .all {
                    filterBar
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            if tab == .keyboard { keyboardSections } else { allSections }
        }
        .tint(AppColor.purple)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: L("搜索词或拼音", "Search words or pinyin", "語またはピンインを検索"))
        .navigationTitle(L("常用词", "My Words", "ユーザ辞書"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            WordEditor(word: nil) { model.save($0) } onDelete: { _ in }
        }
        .sheet(item: $editing) { word in
            WordEditor(word: word) { model.save($0) } onDelete: { model.delete($0) }
        }
        .sheet(isPresented: $addingToKeyboard) {
            AddToKeyboardSheet(model: model)
        }
        .alert(item: $readOnly) { word in
            Alert(title: Text(word.text),
                  message: Text(word.source == .contact
                                ? L("这个名字来自通讯录，要改请去「通讯录」。", "This name comes from Contacts. Edit it there.", "この名前は連絡先から読み込んでいます。連絡先で変更してください。")
                                : L("这个词来自系统文本替换，要改请去 设置 › 通用 › 键盘 › 文本替换。", "This word comes from Text Replacement. Edit it in Settings › General › Keyboard › Text Replacement.", "この語は iPhone のユーザ辞書から読み込んでいます。設定 › 一般 › キーボード › ユーザ辞書 で変更してください。")),
                  dismissButton: .default(Text(L("知道了", "Got it", "OK"))))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .utf8PlainText]) { result in
            guard case .success(let url) = result else { return }
            preview = ImportPreview.load(url)
        }
        .sheet(item: $preview) { preview in
            ImportPreviewView(preview: preview, existing: model.words) { imported, overwrite in
                var words = model.words
                for word in imported {
                    if let index = words.firstIndex(where: { $0.text == word.text }) {
                        if overwrite { words[index].pinyin = word.pinyin }
                    } else {
                        words.append(word)
                    }
                }
                model.words = words
            }
        }
        .onAppear { model.reload() }
    }

    private var tabBar: some View {
        Picker(L("显示", "Show", "表示"), selection: $tab) {
            Text(L("键盘 \(model.keyboardWords.count)", "Keyboard \(model.keyboardWords.count)", "キーボード \(model.keyboardWords.count)")).tag(Tab.keyboard)
            Text(L("全部 \(model.all.count)", "All \(model.all.count)", "すべて \(model.all.count)")).tag(Tab.all)
        }
        .pickerStyle(.segmented)
    }

    private var filterBar: some View {
        Picker(L("来源", "Source", "ソース"), selection: $filter) {
            Text(L("全部 \(model.count(nil))", "All \(model.count(nil))", "すべて \(model.count(nil))")).tag(CommonWord.Source?.none)
            ForEach([CommonWord.Source.manual, .imported, .textReplacement, .contact], id: \.self) { source in
                Text("\(source.shortTitle) \(model.count(source))").tag(Optional(source))
            }
        }
        .pickerStyle(.segmented)
    }

    private func edit(_ word: CommonWord) {
        if word.isReadOnly { readOnly = word } else { editing = word }
    }

    // MARK: 全部

    @ViewBuilder
    private var allSections: some View {
        Section {
            if shown.isEmpty {
                Text(model.all.isEmpty ? L("还没有常用词。点右上角「＋」加一个，或者从文件导入。", "No words yet. Tap ＋ to add one, or import from a file.", "まだ登録がありません。右上の「＋」で追加するか、ファイルから読み込みます。") : L("没有找到。", "No results.", "見つかりません。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { word in
                HStack(spacing: 12) {
                    Button { edit(word) } label: {
                        WordRow(word: word)
                    }
                    .buttonStyle(.plain)
                    KeyboardStar(on: model.isOnKeyboard(word)) { model.toggleKeyboard(word) }
                }
                .swipeActions {
                    if !word.isReadOnly {
                        Button(role: .destructive) { model.delete(word) } label: { Label(L("删除", "Delete", "削除"), systemImage: "trash") }
                            .tint(.red)
                    }
                }
            }
        } footer: {
            Text(L("点 ☆ 把词放到键盘的「常用」里，默认都不放。打拼音或简码时，常用词照常排在候选第一位。左滑删除，点一下编辑；文本替换和通讯录的词要去系统里改。",
                   "Tap ☆ to put a word in the keyboard's 常用 panel; none are added by default. Your words still come first when you type their pinyin or shortcut. Swipe left to delete, tap to edit. Text Replacement and Contacts entries are edited in iOS.",
                   "☆ をタップするとキーボードの「常用」に入ります（初期状態では入りません）。ピンインや略語を入力すると、登録した語が候補の先頭に出ます。左にスワイプで削除、タップで編集。ユーザ辞書と連絡先の語は iOS 側で変更します。"))
        }
        Section {
            Button { importing = true } label: {
                Label(L("从文件导入（搜狗、百度、RIME 等）", "Import from file (Sogou, Baidu, RIME…)", "ファイルから読み込む（Sogou・Baidu・RIME など）"), systemImage: "square.and.arrow.down")
            }
            .tint(AppColor.purple)
        }
        Section {
            Toggle(isOn: $model.usesTextReplacement) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("使用系统文本替换", "Use Text Replacements", "iPhone のユーザ辞書を使う"))
                    Text(L("设置 › 通用 › 键盘 › 文本替换里的词", "Words in Settings › General › Keyboard › Text Replacement", "設定 › 一般 › キーボード › ユーザ辞書 の語")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $model.usesContacts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("使用通讯录里的名字", "Use names from Contacts", "連絡先の名前を使う"))
                    Text(L("只读名字，不读电话和其他信息", "Names only, never numbers or other details", "名前だけを読み、電話番号などは読みません")).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("自动加入", "Add automatically", "自動で追加"))
        } footer: {
            Text(L("这两项和你在这里加的词，都要键盘开了「允许完全访问」才会用上。", "These and the words you add here need Allow Full Access on the keyboard.", "これらとここで追加した語は、キーボードの「フルアクセスを許可」がオンのときに使われます。"))
        }
    }

    // MARK: 键盘

    private func move(from source: IndexSet, to destination: Int) {
        model.moveKeyboard(from: source, to: destination)
    }

    @ViewBuilder
    private var keyboardSections: some View {
        let words = model.keyboardWords
        let filtered = words.filter(matches)
        Section {
            if !query.text.isEmpty && filtered.isEmpty {
                Text(L("没有找到。", "No results.", "見つかりません。")).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(filtered) { word in
                HStack(spacing: 12) {
                    Button { edit(word) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(word.text).font(.system(size: 16)).lineLimit(1)
                            if !word.pinyin.isEmpty {
                                Text(word.pinyin).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color(hex: 0x8E8E93))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    KeyboardStar(on: true) { model.removeFromKeyboard(word) }
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0xC7C7CC))
                }
                .swipeActions {
                    Button { model.removeFromKeyboard(word) } label: { Label(L("拿掉", "Remove", "外す"), systemImage: "star.slash") }
                        .tint(.orange)
                }
            }
            // 搜索时列表不全，不能拖。
            .onMove(perform: query.text.isEmpty ? move : nil)
            Button { addingToKeyboard = true } label: {
                Label(L("添加到键盘", "Add to Keyboard", "キーボードに追加"), systemImage: "plus")
                    .foregroundStyle(AppColor.purple)
            }
        } footer: {
            Text(L("按住右边的 ≡ 上下拖动，键盘里按这个顺序显示。点 ★ 或左滑从键盘里拿掉，词本身还在「全部」里。",
                   "Touch and hold ≡ and drag to reorder; the keyboard shows them in this order. Tap ★ or swipe left to remove a word from the keyboard. It stays in All.",
                   "≡ を長押しして上下にドラッグすると並べ替えられ、キーボードもこの順で表示します。★ をタップするか左にスワイプでキーボードから外せます（語は「すべて」に残ります）。"))
        }
        if !words.isEmpty {
            Section {
                KeyboardWordsPreview(texts: words.map(\.text))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(L("键盘里的样子", "On the keyboard", "キーボードでの表示"))
            } footer: {
                Text(L("一行四格：短词一格，邮箱这类两格，地址和长句占一整行。", "Four per row: short words take one cell, emails two, addresses and sentences a full row.", "1 行 4 マス：短い語は 1 マス、メールアドレスなどは 2 マス、住所や長い文は 1 行。"))
            }
        }
    }
}

/// 放到键盘的星标：☆ 灰色、★ 橙色 #FF9F0A。
private struct KeyboardStar: View {
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 19))
                .foregroundStyle(on ? AppColor.keyboardStar : Color(hex: 0xC7C7CC))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(on ? L("从键盘里拿掉", "Remove from keyboard", "キーボードから外す") : L("放到键盘", "Add to keyboard", "キーボードに追加"))
    }
}

/// 「键盘里的样子」：灰底 #DCDEE4，按键盘同样的一行四格规则缩小显示。
private struct KeyboardWordsPreview: View {
    let texts: [String]

    private static let gap: CGFloat = 4
    private static let font = UIFont.systemFont(ofSize: 11)
    private static let padding: CGFloat = 7

    var body: some View {
        // 列表行宽 = 屏宽减两边 16 的边距，再减预览自己的内边距 8。
        let width = UIScreen.main.bounds.width - 32 - 16
        let column = (width - Self.gap * 3) / 4
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(Array(CommonWordStore.keyboardRows(texts, column: column, gap: Self.gap, font: Self.font,
                                                       padding: Self.padding).prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gap) {
                    ForEach(row, id: \.self) { cell in
                        Text(cell.text)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .padding(.horizontal, Self.padding)
                            .frame(width: column * CGFloat(cell.span) + Self.gap * CGFloat(cell.span - 1), height: 24, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(.systemBackground)))
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.18, alpha: 1) : UIColor(red: 0xDC / 255, green: 0xDE / 255, blue: 0xE4 / 255, alpha: 1)
        })))
    }
}

/// 添加到键盘（W10）：输入一个新词，或者从常用词里多选；已经在键盘里的置灰。
private struct AddToKeyboardSheet: View {
    @ObservedObject var model: CommonWordsModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    /// 按勾选顺序加到键盘最后。
    @State private var selected: [String] = []
    @State private var creating = false
    /// 新词存好了：关掉新建页后这一页也关掉。
    @State private var created = false

    private var candidates: [CommonWord] {
        let text = search.trimmingCharacters(in: .whitespaces).lowercased()
        let code = CommonWordStore.normalizeCode(text)
        var seen = Set<String>()
        return model.all.filter { word in
            seen.insert(word.text).inserted && (text.isEmpty || word.text.lowercased().contains(text)
                || (!code.isEmpty && word.codes.contains { $0.contains(code) }))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { creating = true } label: {
                        Label(L("输入一个新词", "New Word", "新しい単語"), systemImage: "plus").foregroundStyle(AppColor.purple)
                    }
                }
                Section(L("从常用词里选", "From My Words", "ユーザ辞書から選ぶ")) {
                    ForEach(candidates) { word in
                        let added = model.isOnKeyboard(word)
                        let checked = selected.contains(word.text)
                        Button {
                            if checked { selected.removeAll { $0 == word.text } } else { selected.append(word.text) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: added || checked ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(added ? Color(hex: 0xC7C7CC) : checked ? AppColor.purple : Color(hex: 0xC7C7CC))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(word.text).font(.system(size: 16)).lineLimit(1)
                                        .foregroundStyle(added ? Color.secondary : Color.primary)
                                    Text(added ? L("已在键盘里", "Already added", "追加済み") : word.pinyin)
                                        .font(.system(size: 12.5, design: added ? .default : .monospaced))
                                        .foregroundStyle(Color(hex: 0x8E8E93))
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(added)
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: L("搜索词或拼音", "Search words or pinyin", "語またはピンインを検索"))
            .navigationTitle(L("添加到键盘", "Add to Keyboard", "キーボードに追加"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消", "Cancel", "キャンセル")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? L("添加", "Add", "追加") : L("添加 \(selected.count) 个", "Add (\(selected.count))", "\(selected.count)件を追加")) {
                        model.addToKeyboard(selected)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .tint(AppColor.purple)
            .sheet(isPresented: $creating, onDismiss: { if created { dismiss() } }) {
                // 新词保存后直接放到键盘。
                WordEditor(word: nil) { word in
                    model.save(word)
                    model.addToKeyboard([word.text])
                    created = true
                } onDelete: { _ in }
            }
        }
    }
}

/// 列表里的一行：词、拼音和简码、右边来源标签。
private struct WordRow: View {
    let word: CommonWord

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.text).font(.system(size: 16)).lineLimit(1)
                HStack(spacing: 6) {
                    if !word.pinyin.isEmpty {
                        Text(word.pinyin).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color(hex: 0x8E8E93))
                    }
                    if !word.shortcut.isEmpty {
                        ShortcutTag(code: word.shortcut)
                    }
                }
            }
            Spacer(minLength: 8)
            SourceTag(source: word.source)
        }
        .contentShape(Rectangle())
    }
}

struct ShortcutTag: View {
    let code: String

    var body: some View {
        Text(L("简码 \(code)", "Shortcut \(code)", "略語 \(code)"))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(hex: 0x4A3BD6))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(hex: 0xC9C3F5)))
    }
}

struct SourceTag: View {
    let source: CommonWord.Source

    var body: some View {
        Text(source.title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(source.colors.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(source.colors.fill))
    }
}

// MARK: - 添加、编辑

/// 添加 / 编辑（W3）：词、拼音（按词自动生成，可改）、简码；下面预览键盘里的样子；编辑时可以删除。
private struct WordEditor: View {
    let original: CommonWord?
    let onSave: (CommonWord) -> Void
    let onDelete: (CommonWord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var pinyin: String
    @State private var shortcut: String
    /// 用户自己改过拼音后，不再跟着词自动生成。
    @State private var pinyinEdited: Bool

    init(word: CommonWord?, onSave: @escaping (CommonWord) -> Void, onDelete: @escaping (CommonWord) -> Void) {
        original = word
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: word?.text ?? "")
        _pinyin = State(initialValue: word?.pinyin ?? "")
        _shortcut = State(initialValue: word?.shortcut ?? "")
        _pinyinEdited = State(initialValue: word != nil)
    }

    private var draft: CommonWord {
        var word = original ?? CommonWord(text: "", pinyin: "")
        word.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        word.pinyin = pinyin.trimmingCharacters(in: .whitespaces).lowercased()
        word.shortcut = CommonWordStore.normalizeCode(shortcut)
        return word
    }

    private var canSave: Bool { !draft.text.isEmpty && !draft.codes.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(L("词", "Word", "語")).frame(width: 36, alignment: .leading)
                        TextField(L("比如：你的邮箱或地址", "e.g. your email or address", "例：メールアドレスや住所"), text: $text, axis: .vertical)
                            .onChange(of: text) { value in
                                if !pinyinEdited { pinyin = CommonWordStore.pinyin(of: value) }
                            }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(L("拼音", "Pinyin", "ピンイン")).frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("you xiang", text: Binding(get: { pinyin }, set: {
                                pinyin = $0
                                pinyinEdited = true
                            }))
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Text(L("根据词自动生成，可以改；英文和数字的词请自己填一个好记的拼音", "Generated from the word and editable. For English or numbers, enter pinyin that's easy to remember", "語から自動で作成され、変更もできます。英語や数字の語は覚えやすいピンインを入れてください"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(L("简码", "Shortcut", "略語")).frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField(L("可不填", "Optional", "任意"), text: $shortcut)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text(L("打这几个字母也能出这个词", "Type these letters to get the word too", "この文字を入力しても候補に出ます")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(L("键盘里的样子", "Preview", "キーボードでの表示")) {
                    CandidatePreview(word: draft)
                        .listRowInsets(EdgeInsets())
                }
                if let original {
                    Section {
                        Button(L("删除这个词", "Delete this word", "この語を削除"), role: .destructive) {
                            onDelete(original)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(original == nil ? L("添加常用词", "Add word", "語を追加") : L("编辑常用词", "Edit word", "語を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消", "Cancel", "キャンセル")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存", "Save", "保存")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .tint(AppColor.purple)
        }
    }
}

/// 预览候选条：「打 yx 或 you xiang」，常用词排第一，带小紫点。
private struct CandidatePreview: View {
    let word: CommonWord

    var body: some View {
        let hints = [word.shortcut, word.pinyin].filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            Text(hints.isEmpty ? L("填好拼音或简码后在这里预览", "Enter pinyin or a shortcut to preview here", "ピンインか略語を入れるとここでプレビューできます") : L("打 ", "Type ", "") + hints.joined(separator: L(" 或 ", " or ", " または ")) + L("", "", " と入力"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Text(word.text.isEmpty ? L("你的词", "Your word", "あなたの語") : word.text)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.purple)
                    .lineLimit(1)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Color(hex: 0x8B7CF6)).frame(width: 5, height: 5).offset(x: 6, y: 1)
                    }
                Text("一下").font(.system(size: 17))
                Text("有些").font(.system(size: 17))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
    }
}

// MARK: - 导入

/// 选好的文件和解析结果。
struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let result: CommonWordStore.ImportResult
    let error: String?

    static func load(_ url: URL) -> ImportPreview {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let empty = CommonWordStore.ImportResult(format: "", words: [], lines: 0, unreadable: 0)
        guard let data = try? Data(contentsOf: url) else {
            return ImportPreview(fileName: url.lastPathComponent, result: empty, error: L("读不了这个文件。", "Can't read this file.", "このファイルを読み込めません。"))
        }
        // 搜狗、百度导出的有时是 UTF-16 或 GB18030。
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: gb18030)
        guard let text else {
            return ImportPreview(fileName: url.lastPathComponent, result: empty, error: L("文件不是文本，或者编码认不出来。", "The file isn't text, or its encoding isn't recognized.", "テキストファイルでないか、文字コードを判別できません。"))
        }
        return ImportPreview(fileName: url.lastPathComponent, result: CommonWordStore.parseImport(text), error: nil)
    }
}

/// 导入预览（W4）：文件名和格式、四个数字、前三条、已有的词跳过或覆盖、导入按钮。
private struct ImportPreviewView: View {
    let preview: ImportPreview
    let existing: [CommonWord]
    let onImport: ([CommonWord], Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var overwrite = false

    private var existingTexts: Set<String> { Set(existing.map(\.text)) }
    private var fresh: [CommonWord] { preview.result.words.filter { !existingTexts.contains($0.text) } }
    private var duplicates: [CommonWord] { preview.result.words.filter { existingTexts.contains($0.text) } }
    private var importCount: Int { fresh.count + (overwrite ? duplicates.count : 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.title3)
                            .foregroundStyle(Color(hex: 0xA15C00))
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0xFFF1DC)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.fileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(preview.error ?? L("识别为：\(preview.result.format)", "Detected: \(preview.result.format)", "判別結果：\(preview.result.format)"))
                                .font(.caption)
                                .foregroundStyle(preview.error == nil ? Color.secondary : Color.red)
                        }
                    }
                    if preview.error == nil {
                        HStack {
                            stat(preview.result.lines, L("文件里", "In file", "ファイル内"), .primary)
                            stat(fresh.count, L("可导入", "New", "読み込み可"), Color(hex: 0x1F7A45))
                            stat(duplicates.count, L("已经有了", "Already added", "登録済み"), .secondary)
                            stat(preview.result.unreadable, L("读不出", "Unreadable", "読めない行"), Color(hex: 0xA15C00))
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !preview.result.words.isEmpty {
                    Section(L("预览", "Preview", "プレビュー")) {
                        ForEach(preview.result.words.prefix(3)) { WordRow(word: $0) }
                        if preview.result.words.count > 3 {
                            Text(L("还有 \(preview.result.words.count - 3) 条", "\(preview.result.words.count - 3) more", "ほか \(preview.result.words.count - 3) 件"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Section {
                        Picker(L("已经有的词", "Existing words", "登録済みの語"), selection: $overwrite) {
                            Text(L("跳过", "Skip", "スキップ")).tag(false)
                            Text(L("覆盖", "Replace", "上書き")).tag(true)
                        }
                    } footer: {
                        if preview.result.unreadable > 0 {
                            Text(L("\(preview.result.unreadable) 条读不出的多半是空行，或者没有汉字也没有拼音的行。", "The \(preview.result.unreadable) unreadable lines are usually blank or have neither Chinese nor pinyin.", "読めなかった \(preview.result.unreadable) 行は、たいてい空行か、漢字もピンインもない行です。"))
                        }
                    }
                }
                Section {
                    Button(L("导入 \(importCount) 个词", "Import \(importCount) words", "\(importCount) 語を読み込む")) {
                        onImport(fresh + (overwrite ? duplicates : []), overwrite)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(importCount == 0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(L("支持 .txt：搜狗、百度、QQ 拼音、RIME（词 拼音 权重）、每行一个词。", "Supports .txt from Sogou, Baidu, QQ Pinyin, RIME (word pinyin weight), or one word per line.", "対応形式（.txt）：Sogou、Baidu、QQ ピンイン、RIME（語 ピンイン 重み）、1 行 1 語。"))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle(L("导入预览", "Import preview", "読み込みのプレビュー"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消", "Cancel", "キャンセル")) { dismiss() } }
            }
            .tint(AppColor.purple)
        }
    }

    private func stat(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
