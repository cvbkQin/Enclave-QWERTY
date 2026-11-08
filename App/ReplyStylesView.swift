import SwiftUI

/// App › AI › 提示词 ›「帮回风格」（T16，HB16）：每行左边圆圈，勾上的是点「帮回」时一起写的几种，
/// 圈里数字 1 / 2 / 3 是卡片上从左到右的顺序；最多勾 3 种、至少 1 种。点一行进编辑页。
struct ReplyStyleSections: View {
    @Binding var settings: EnclaveSettings
    var edit: (UUID) -> Void
    var add: () -> Void
    @State private var limit: Limit?

    private enum Limit: Identifiable {
        case full, last
        var id: Self { self }
    }

    var body: some View {
        let checked = settings.checkedReplyStyles.map(\.id)
        Section {
            ForEach(settings.replyStyles) { style in
                HStack(spacing: 10) {
                    ReplyCheckCircle(number: checked.firstIndex(of: style.id).map { $0 + 1 }) {
                        toggle(style.id)
                    }
                    ReplyStyleRow(style: style, count: UsageStats.week("reply.style." + style.id.uuidString)) {
                        edit(style.id)
                    }
                }
            }
            .onDelete(perform: delete)
            .onMove { settings.replyStyles.move(fromOffsets: $0, toOffset: $1) }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(L("全部帮回风格", "All reply styles", "すべての返信スタイル"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                EditButton()
                    .font(.system(size: 16))
                    .tint(HelpStyle.title)
                    .environment(\.locale, Loc.locale)
            }
            .textCase(nil)
        } footer: {
            Text(L("左边勾上的几种会一起写，最多 3 种，数字是卡片上的顺序。次数是本周的。点一行编辑内容。",
                   "Checked styles are written together, up to 3; the number is their order on the card. Counts are for this week. Tap a row to edit it.",
                   "チェックしたスタイルをまとめて作成します（最大 3 つ、数字はカードでの順番）。回数は今週の分です。行をタップすると編集できます。"))
        }
        .alert(limit == .full ? L("最多勾 3 种", "Up to 3 styles", "選べるのは 3 つまで") : L("至少勾 1 种", "Keep at least 1", "1 つは選んでください"),
               isPresented: Binding(get: { limit != nil }, set: { if !$0 { limit = nil } })) {
            Button(L("好", "OK", "OK"), role: .cancel) {}
        } message: {
            Text(limit == .full ? L("先取消一种再勾。", "Uncheck one first.", "先にどれかのチェックを外してください。")
                 : L("点「帮回」时至少要写一种。", "Help Reply needs at least one style.", "返信アシストには 1 つ以上必要です。"))
        }
        if !missingDefaults.isEmpty {
            Section {
                ForEach(missingDefaults) { preset in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.displayName).font(.system(size: 17))
                            Text(preset.prompt).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button {
                            settings.replyStyles.append(StylePreset(name: preset.name, prompt: preset.prompt))
                        } label: {
                            Label(L("加回", "Restore", "戻す"), systemImage: "arrow.uturn.backward")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HelpStyle.title)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .deleteDisabled(true)
                    .moveDisabled(true)
                }
            } header: {
                Text(L("删掉的预设", "Deleted presets", "削除したプリセット")).font(.system(size: 13)).textCase(nil)
            }
        }
        Section {
            Button(action: add) {
                Label(L("添加帮回风格", "Add reply style", "返信スタイルを追加"), systemImage: "plus")
                    .font(.system(size: 17))
                    .foregroundStyle(HelpStyle.title)
            }
        }
    }

    private func toggle(_ id: UUID) {
        let wasChecked = settings.checkedReplyStyles.contains { $0.id == id }
        if !settings.toggleReplyChecked(id) { limit = wasChecked ? .last : .full }
    }

    /// 至少留一条。
    private func delete(_ offsets: IndexSet) {
        guard settings.replyStyles.count > offsets.count else { return }
        let removed = Set(offsets.map { settings.replyStyles[$0].id })
        settings.replyStyles.remove(atOffsets: offsets)
        settings.replyCheckedIDs.removeAll { removed.contains($0) }
    }

    private var missingDefaults: [StylePreset] {
        StylePreset.replyDefaults.filter { preset in
            !settings.replyStyles.contains { $0.name == preset.name || $0.prompt == preset.prompt }
        }
    }
}

/// 左边圆圈：勾上是绿底白数字（卡片上的顺序），没勾是空心灰圈。编辑状态不显示。
private struct ReplyCheckCircle: View {
    let number: Int?
    let toggle: () -> Void
    @Environment(\.editMode) private var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing != true {
            Button(action: toggle) {
                ZStack {
                    if let number {
                        Circle().fill(HelpStyle.gradient)
                        Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(number.map { L("已勾选，第 \($0) 个", "Checked, number \($0)", "チェック済み、\($0) 番目") }
                                ?? L("未勾选", "Not checked", "未チェック"))
            .accessibilityHint(L("勾上的会在点「帮回」时一起写", "Checked styles are written together", "チェックしたものをまとめて作成します"))
        }
    }
}

private struct ReplyStyleRow: View {
    let style: StylePreset
    let count: Int
    let open: () -> Void
    @Environment(\.editMode) private var editMode

    private var editing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        Button { if !editing { open() } } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.displayName).font(.system(size: 17)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(style.prompt.isEmpty ? L("（还没写怎么回）", "(No instructions yet)", "（未入力）") : style.prompt)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !editing {
                    Text(L("\(count) 次", "\(count)×", "\(count) 回"))
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(count == 0 ? Color(.tertiaryLabel) : Color.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityHint(editing ? "" : L("编辑内容", "Edit", "編集"))
    }
}

/// 编辑一条帮回风格（HB16 第 2 格）：名称、怎么回、✨ AI 优化、「放进帮回卡片」开关、删除。
struct ReplyStyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var optimizer = PromptOptimizer()
    @FocusState private var editingPrompt: Bool
    @State private var limitHit = false

    static let newName = L("新帮回风格", "New reply style", "新しい返信スタイル")
    private var builtIn: StylePreset? { StylePreset.replyDefaults.first { $0.name == style.name } }

    var body: some View {
        Form {
            Section {
                TextField(L("名称", "Name", "名前"), text: $style.name)
            } header: {
                Text(L("名称", "Name", "名前"))
            } footer: {
                Text(L("显示在帮回卡片的语气标签上，最好 2–4 个字。", "Shown as the tone tag on the reply card. Keep it short.", "返信カードのタグに表示されます。短めがおすすめです。"))
            }
            Section {
                TextEditor(text: $style.prompt)
                    .focused($editingPrompt)
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text(L("比如「先感谢对方，再说自己的意思，一两句话」", "e.g. \"Thank them first, then say what you mean in a sentence or two\"", "例：「まずお礼を言ってから、一、二文で用件を」"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                PromptOptimizeButton(optimizer: optimizer, prompt: style.prompt, name: style.displayName, answer: false, reply: true)
            } header: {
                Text(L("怎么回", "How to reply", "返し方"))
            } footer: {
                Text(L("点「帮回」时和对方的话一起发给润色接口（主接口），每次写一种风格。", "Sent to the Polish API (main API) with the copied message; one style at a time.", "コピーした文と一緒に整える用 API（メイン API）に送られ、1 回に 1 つのスタイルで作成します。"))
            }
            if let result = optimizer.result {
                PromptOptimizedSection(optimizer: optimizer, result: result, prompt: $style.prompt)
            }
            Section {
                Toggle(isOn: Binding(get: { settings.checkedReplyStyles.contains { $0.id == style.id } },
                                     set: { _ in if !settings.toggleReplyChecked(style.id) { limitHit = true } })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("放进帮回卡片", "Write on the reply card", "返信カードに入れる"))
                        Text(L("勾上后点「帮回」会同时写这一种（最多 3 种）", "Help Reply writes this style too (up to 3)", "返信アシストでこのスタイルも作成します（最大 3 つ）"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(HelpStyle.green)
            }
            Section {
                if let builtIn {
                    Button(L("恢复这条的默认内容", "Restore default text", "元の内容に戻す")) { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button(L("删除这条帮回风格", "Delete reply style", "この返信スタイルを削除"), role: .destructive) {
                    let id = style.id
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        settings.replyStyles.removeAll { $0.id == id }
                        settings.replyCheckedIDs.removeAll { $0 == id }
                    }
                }
                .disabled(settings.replyStyles.count <= 1)
            }
        }
        .navigationTitle(L("编辑帮回风格", "Edit reply style", "返信スタイルを編集"))
        .doneEditingButton(editingPrompt)
        .onDisappear { optimizer.cancel() }
        .alert(L("最多勾 3 种", "Up to 3 styles", "選べるのは 3 つまで"), isPresented: $limitHit) {
            Button(L("好", "OK", "OK"), role: .cancel) {}
        } message: {
            Text(L("至少留 1 种、最多 3 种一起写。先在列表里取消一种再勾。", "Between 1 and 3 styles are written together. Uncheck one in the list first.",
                   "まとめて作成するのは 1〜3 つです。先にリストでどれかを外してください。"))
        }
    }

    /// 「＋ 添加」后没改名也没填内容就返回：这条空的不留（至少留一条）。
    static func dropIfBlank(_ id: UUID?, settings: inout EnclaveSettings) {
        guard let id, settings.replyStyles.count > 1 else { return }
        settings.replyStyles.removeAll {
            $0.id == id && $0.name.trimmingCharacters(in: .whitespaces) == newName
                && $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !settings.replyStyles.contains(where: { $0.id == id }) { settings.replyCheckedIDs.removeAll { $0 == id } }
    }
}
