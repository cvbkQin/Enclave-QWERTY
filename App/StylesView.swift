import SwiftUI

/// 「提示词」标签（原「风格」）。
struct StylesTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            StylesView(settings: $store.settings)
        }
    }
}

/// 提示词（PR1，原「风格」）：顶部说明小卡、全部提示词（每行本周次数）、添加、恢复默认。
/// 左滑删除，「编辑」拖动排序；这里的顺序就是键盘「润色▾」里的顺序。存储还是 StylePreset。
struct StylesView: View {
    @Binding var settings: EnclaveSettings
    @State private var confirmReset = false
    /// 每条提示词本周执行的次数，进页面时读一次。
    @State private var weekCounts: [UUID: Int] = [:]

    var body: some View {
        List {
            Section {
                HowItWorksCard(name: settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える"))
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                TabTitle(caption: caption, title: L("提示词", "Prompts", "プロンプト"))
                    // 标题到第一张卡片和首页一样约 18pt。
                    .padding(.bottom, 11)
                    .dashFormCard()
            }
            Section {
                ForEach($settings.styles) { $style in
                    NavigationLink {
                        StyleEditor(style: $style, settings: $settings)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(style.displayName).font(.body)
                                    if style.id == settings.selectedStyle?.id {
                                        DashTag(text: L("默认", "Default", "デフォルト"), color: DashColor.ai)
                                    }
                                }
                                Text(Self.summary(style))
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(L("\(weekCounts[style.id] ?? 0) 次", "\(weekCounts[style.id] ?? 0)×", "\(weekCounts[style.id] ?? 0) 回"))
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        // 分隔线都从名字左边开始，不要有的通栏。
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
                .onDelete { settings.styles.remove(atOffsets: $0) }
                .onMove { settings.styles.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text(L("全部提示词", "All prompts", "すべてのプロンプト"))
                    Spacer()
                    // 系统的编辑按钮（PH2 挪到分组标题右边）：自己管 editMode 时拖过一次后再拖、点 ⊖ 都没反应。
                    EditButton()
                        .font(.system(size: 15))
                        .tint(DashColor.ai)
                        .environment(\.locale, Loc.locale)
                        .textCase(nil)
                }
            } footer: {
                Text(L("顺序就是键盘「\(settings.selectedStyle?.displayName ?? "润色") ▾」里的顺序。次数是本周的。",
                       "This is the order in the keyboard's \(settings.selectedStyle?.displayName ?? "Polish") ▾ menu. Counts are for this week.",
                       "キーボードの「\(settings.selectedStyle?.displayName ?? "整える") ▾」もこの順番です。回数は今週の分です。"))
            }

            Section {
                Button {
                    settings.styles.append(StylePreset(name: L("新提示词", "New prompt", "新しいプロンプト"), prompt: ""))
                } label: {
                    Label(L("添加提示词", "Add prompt", "プロンプトを追加"), systemImage: "plus")
                }
            }
            Section {
                Button(L("恢复默认提示词", "Restore default prompts", "デフォルトのプロンプトに戻す")) { confirmReset = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .tint(DashColor.ai)
        .confirmationDialog(L("恢复成默认的 5 条提示词？你改过和添加的会被删掉。", "Restore the 5 default prompts? Prompts you changed or added will be removed.", "デフォルトの 5 つのプロンプトに戻しますか？変更・追加したものは削除されます。"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("恢复默认提示词", "Restore default prompts", "デフォルトのプロンプトに戻す"), role: .destructive) {
                settings.styles = StylePreset.defaults
                settings.selectedStyleID = nil
            }
        }
        .navigationTitle(L("提示词", "Prompts", "プロンプト"))
        .tabRootPage()
        .onAppear {
            weekCounts = Dictionary(uniqueKeysWithValues: settings.styles.map { ($0.id, UsageStats.week("polish.style.\($0.id.uuidString)")) })
        }
    }

    /// 标题上的灰字：「5 条 · 默认「润色」」。
    private var caption: String {
        let name = settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
        let count = settings.styles.count
        return L("\(count) 条 · 默认「\(name)」", "\(count) prompts · Default: \(name)", "\(count) 件 · デフォルト「\(name)」")
    }

    /// 一句说明：自带的 5 条用固定的说明，自己加的显示提示词内容。
    static func summary(_ style: StylePreset) -> String {
        if let builtIn = StyleSuggestions.builtIn(style), builtIn.prompt == style.prompt {
            switch style.name {
            case "润色": return L("不加额外要求，按原文的语气改顺、改通", "No extra instructions. Smooths the text in its own tone", "追加の指示なし。元の語調のまま読みやすく整えます")
            case "正式": return L("书面、得体、礼貌，适合工作沟通和对外发送", "Written, polite and proper, for work and outside contacts", "書き言葉で丁寧に。仕事や社外向けに")
            case "口语": return L("像本人平时说话一样自然随意", "Natural and casual, the way you talk", "普段話すように自然でカジュアルに")
            case "简短": return L("只留核心意思，能一句说清就一句", "Just the point, in one sentence if possible", "要点だけ。できれば一文で")
            case "结构": return L("提炼关键信息，整理成编号要点", "Pulls out the key points as a numbered list", "要点を抜き出して番号付きで整理")
            default: break
            }
        }
        return style.prompt.isEmpty ? L("不加额外要求，按原文的语气改顺、改通", "No extra instructions. Smooths the text in its own tone", "追加の指示なし。元の語調のまま読みやすく整えます") : style.prompt
    }
}

/// 顶部说明小卡：左边画键盘上的「✨ + 润色▾」，右边一句怎么用。
private struct HowItWorksCard: View {
    var name: String

    var body: some View {
        HStack(spacing: 12) {
            KeyboardChipPreview(name: name)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray6)))
            Text(L("点 ✨，用当前这条提示词改输入框里的话；点名字换一条。", "Tap ✨ to run the current prompt on your text. Tap the name to switch.", "✨ で、いまのプロンプトを入力欄の文章に使います。名前をタップで切り替え。"))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 键盘 AI 栏上的「✨」和「名字 ▾」的小样，提示词页和编辑页用。
struct KeyboardChipPreview: View {
    var name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 24)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .leading, endPoint: .trailing)))
            HStack(spacing: 2) {
                Text(name).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(maxWidth: 92)
            .frame(height: 24)
            .background(Capsule().fill(DashColor.card))
            .overlay(Capsule().strokeBorder(Color(.systemGray4), lineWidth: 0.5))
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

private struct StyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @Environment(\.dismiss) private var dismiss

    private var builtIn: StylePreset? { StyleSuggestions.builtIn(style) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField(L("名称", "Name", "名前"), text: $style.name)
                    Text(L("键盘上显示", "On keyboard", "キーボード")).font(.caption).foregroundStyle(.secondary)
                    KeyboardChipPreview(name: style.displayName)
                }
            } header: {
                Text(L("名称", "Name", "名前"))
            } footer: {
                Text(L("显示在键盘 ✨ 旁边，四个字以内最好。", "Shown next to ✨ on the keyboard. Keep it short.", "キーボードの ✨ の横に表示されます。短めがおすすめです。"))
            }
            Section {
                TextEditor(text: $style.prompt)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text(L("比如：翻成日语，发给客户，客气一点", "e.g. Translate into Japanese for a client, keep it polite", "例：日本語に訳して、お客様向けに丁寧に"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text(L("提示词内容", "Prompt", "プロンプトの内容"))
            } footer: {
                Text(L("写清楚场景和要求，什么都可以写，比如「翻成日语，发给客户，客气一点」。每次点 ✨ 都会带上。", "Describe the situation and what you want. Anything goes, like \"translate into Japanese for a client, keep it polite\". It's sent every time you tap ✨.", "場面と要望をはっきり書きます。何でも書けます（例：「日本語に訳して、お客様向けに丁寧に」）。✨ をタップするたびに送られます。"))
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                        Text(L("建议", "Suggestions", "候補"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.deepPurple)
                    SuggestionChips(tags: StyleSuggestions.tags(for: style), prompt: $style.prompt)
                    Text(builtIn == nil ? L("点一下加进提示词，再点一下拿掉。自己加的提示词显示通用建议。", "Tap to add to the prompt, tap again to remove. Prompts you added show general suggestions.", "タップでプロンプトに追加、もう一度タップで外します。追加したプロンプトには汎用の候補を表示します。") : L("点一下加进提示词，再点一下拿掉。", "Tap to add to the prompt, tap again to remove.", "タップでプロンプトに追加、もう一度タップで外します。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 和上面分组标题、说明文字对齐。
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section {
                if let builtIn {
                    Button(L("恢复这条的默认内容", "Restore default text", "元の内容に戻す")) { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button(L("设为默认提示词", "Set as default", "デフォルトにする")) { settings.selectedStyleID = style.id }
                    .disabled(settings.selectedStyle?.id == style.id)
                Button(L("删除这条提示词", "Delete prompt", "このプロンプトを削除"), role: .destructive) {
                    let id = style.id
                    dismiss()
                    // 先退回列表再删，免得正在显示的编辑页绑定到已删除的项。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        settings.styles.removeAll { $0.id == id }
                        if settings.selectedStyleID == id { settings.selectedStyleID = nil }
                    }
                }
                .disabled(settings.styles.count <= 1)
            }
        }
        .navigationTitle(L("编辑提示词", "Edit prompt", "プロンプトを編集"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
