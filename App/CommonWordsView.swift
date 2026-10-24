import SwiftUI
import UniformTypeIdentifiers

/// 常用词的来源标签：字色和底色。
extension CommonWord.Source {
    var title: String {
        switch self {
        case .manual: return "手动"
        case .imported: return "导入"
        case .textReplacement: return "文本替换"
        case .contact: return "通讯录"
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

    /// 只列出打开了开关的系统来源。
    var all: [CommonWord] {
        words + lexicon.filter {
            ($0.source == .textReplacement && usesTextReplacement) || ($0.source == .contact && usesContacts)
        }
    }

    func count(_ source: CommonWord.Source?) -> Int {
        all.filter { source == nil || $0.source == source }.count
    }

    func reload() {
        words = CommonWordStore.load()
        lexicon = CommonWordStore.lexicon
    }

    func save(_ word: CommonWord) {
        if let index = words.firstIndex(where: { $0.id == word.id }) {
            words[index] = word
        } else {
            words.insert(word, at: 0)
        }
    }

    func delete(_ word: CommonWord) {
        words.removeAll { $0.id == word.id }
    }
}

/// 常用词列表（W2）：搜索、按来源筛选、点一行编辑、左滑删除、从文件导入、系统来源开关。
struct CommonWordsView: View {
    @StateObject private var model = CommonWordsModel()
    @State private var search = ""
    @State private var filter: CommonWord.Source?
    @State private var editing: CommonWord?
    @State private var adding = false
    @State private var readOnly: CommonWord?
    @State private var importing = false
    @State private var preview: ImportPreview?

    private var shown: [CommonWord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let compact = CommonWordStore.normalizeCode(query)
        return model.all.filter { word in
            (filter == nil || word.source == filter) && (query.isEmpty || word.text.lowercased().contains(query)
                || (!compact.isEmpty && word.codes.contains { $0.contains(compact) }))
        }
    }

    var body: some View {
        List {
            if KeyboardStatus.fullAccess == false {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("常用词还没同步到键盘").font(.subheadline.weight(.semibold))
                            Text("键盘开了「允许完全访问」才会用上这里的词。").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Color.orange.opacity(0.12))
            }
            Section {
                filterBar
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                if shown.isEmpty {
                    Text(model.all.isEmpty ? "还没有常用词。点右上角「＋」加一个，或者从文件导入。" : "没有找到。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { word in
                    Button {
                        if word.isReadOnly { readOnly = word } else { editing = word }
                    } label: {
                        WordRow(word: word)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !word.isReadOnly {
                            Button(role: .destructive) { model.delete(word) } label: { Label("删除", systemImage: "trash") }
                                .tint(.red)
                        }
                    }
                }
            } footer: {
                Text("打拼音或简码时，常用词排在候选第一位。左滑删除，点一下编辑；文本替换和通讯录的词要去系统里改。")
            }
            Section {
                Button { importing = true } label: {
                    Label("从文件导入（搜狗、百度、RIME 等）", systemImage: "square.and.arrow.down")
                }
                .tint(AppColor.purple)
            }
            Section {
                Toggle(isOn: $model.usesTextReplacement) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用系统文本替换")
                        Text("设置 › 通用 › 键盘 › 文本替换里的词").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $model.usesContacts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用通讯录里的名字")
                        Text("只读名字，不读电话和其他信息").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("自动加入")
            } footer: {
                Text("这两项和你在这里加的词，都要键盘开了「允许完全访问」才会用上。")
            }
        }
        .tint(AppColor.purple)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索词或拼音")
        .navigationTitle("常用词")
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
        .alert(item: $readOnly) { word in
            Alert(title: Text(word.text),
                  message: Text(word.source == .contact
                                ? "这个名字来自通讯录，要改请去「通讯录」。"
                                : "这个词来自系统文本替换，要改请去 设置 › 通用 › 键盘 › 文本替换。"),
                  dismissButton: .default(Text("知道了")))
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

    private var filterBar: some View {
        Picker("来源", selection: $filter) {
            Text("全部 \(model.count(nil))").tag(CommonWord.Source?.none)
            ForEach([CommonWord.Source.manual, .imported, .textReplacement, .contact], id: \.self) { source in
                Text("\(source.title) \(model.count(source))").tag(Optional(source))
            }
        }
        .pickerStyle(.segmented)
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
        Text("简码 \(code)")
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
                        Text("词").frame(width: 36, alignment: .leading)
                        TextField("比如：你的邮箱或地址", text: $text, axis: .vertical)
                            .onChange(of: text) { value in
                                if !pinyinEdited { pinyin = CommonWordStore.pinyin(of: value) }
                            }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("拼音").frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("you xiang", text: Binding(get: { pinyin }, set: {
                                pinyin = $0
                                pinyinEdited = true
                            }))
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Text("根据词自动生成，可以改；英文和数字的词请自己填一个好记的拼音")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("简码").frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("可不填", text: $shortcut)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("打这几个字母也能出这个词").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("键盘里的样子") {
                    CandidatePreview(word: draft)
                        .listRowInsets(EdgeInsets())
                }
                if let original {
                    Section {
                        Button("删除这个词", role: .destructive) {
                            onDelete(original)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(original == nil ? "添加常用词" : "编辑常用词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
            Text(hints.isEmpty ? "填好拼音或简码后在这里预览" : "打 " + hints.joined(separator: " 或 "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Text(word.text.isEmpty ? "你的词" : word.text)
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
            return ImportPreview(fileName: url.lastPathComponent, result: empty, error: "读不了这个文件。")
        }
        // 搜狗、百度导出的有时是 UTF-16 或 GB18030。
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: gb18030)
        guard let text else {
            return ImportPreview(fileName: url.lastPathComponent, result: empty, error: "文件不是文本，或者编码认不出来。")
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
                            Text(preview.error ?? "识别为：\(preview.result.format)")
                                .font(.caption)
                                .foregroundStyle(preview.error == nil ? Color.secondary : Color.red)
                        }
                    }
                    if preview.error == nil {
                        HStack {
                            stat(preview.result.lines, "文件里", .primary)
                            stat(fresh.count, "可导入", Color(hex: 0x1F7A45))
                            stat(duplicates.count, "已经有了", .secondary)
                            stat(preview.result.unreadable, "读不出", Color(hex: 0xA15C00))
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !preview.result.words.isEmpty {
                    Section("预览") {
                        ForEach(preview.result.words.prefix(3)) { WordRow(word: $0) }
                        if preview.result.words.count > 3 {
                            Text("还有 \(preview.result.words.count - 3) 条")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Section {
                        Picker("已经有的词", selection: $overwrite) {
                            Text("跳过").tag(false)
                            Text("覆盖").tag(true)
                        }
                    } footer: {
                        if preview.result.unreadable > 0 {
                            Text("\(preview.result.unreadable) 条读不出的多半是空行，或者没有汉字也没有拼音的行。")
                        }
                    }
                }
                Section {
                    Button("导入 \(importCount) 个词") {
                        onImport(fresh + (overwrite ? duplicates : []), overwrite)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(importCount == 0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("支持 .txt：搜狗、百度、QQ 拼音、RIME（词 拼音 权重）、每行一个词。")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("导入预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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
