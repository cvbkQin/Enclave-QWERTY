import SwiftUI

/// 「风格」标签。
struct StylesTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            StylesView(settings: $store.settings)
        }
    }
}

/// 风格预设：左滑删除，「编辑」拖动排序，添加，恢复默认。这里的顺序就是键盘「正式▾」菜单里的顺序。
struct StylesView: View {
    @Binding var settings: EnclaveSettings
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ForEach($settings.styles) { $style in
                    NavigationLink {
                        StyleEditor(style: $style, settings: $settings)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(style.displayName)
                                if style.id == settings.selectedStyle?.id {
                                    Text(L("默认", "Default", "デフォルト"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                }
                            }
                            Text(style.prompt.isEmpty ? L("按原文的场景和语气润色，不改变意思。", "Polishes in the original context and tone without changing the meaning.", "元の場面と語調のまま、意味を変えずに整えます。") : style.prompt)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { settings.styles.remove(atOffsets: $0) }
                .onMove { settings.styles.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text(L("每个风格是一段提示词，润色时带上。", "Each style is a prompt sent along when you polish.", "文体ごとにプロンプトがあり、整えるときに一緒に送られます。"))
                    .font(.subheadline)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                Text(L("这里的顺序就是键盘「\(settings.selectedStyle?.displayName ?? L("风格", "Styles", "文体"))▾」菜单里的顺序。点「编辑」拖动排序，左滑删除。", "This is the order in the keyboard's \(settings.selectedStyle?.displayName ?? "Style") ▾ menu. Tap Edit to reorder, swipe left to delete.", "キーボードの「\(settings.selectedStyle?.displayName ?? "文体")▾」メニューもこの順番です。「編集」で並べ替え、左にスワイプで削除できます。"))
            }

            Section {
                Button {
                    settings.styles.append(StylePreset(name: L("新风格", "New style", "新しい文体"), prompt: ""))
                } label: {
                    Label(L("添加风格", "Add style", "文体を追加"), systemImage: "plus")
                }
            }
            Section {
                Button(L("恢复默认风格", "Restore default styles", "デフォルトの文体に戻す")) { confirmReset = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .confirmationDialog(L("恢复成默认的 5 个风格？你改过和添加的风格会被删掉。", "Restore the 5 default styles? Styles you changed or added will be removed.", "デフォルトの 5 つの文体に戻しますか？変更・追加した文体は削除されます。"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("恢复默认风格", "Restore default styles", "デフォルトの文体に戻す"), role: .destructive) {
                settings.styles = StylePreset.defaults
                settings.selectedStyleID = nil
            }
        }
        .navigationTitle(L("风格", "Styles", "文体"))
        .toolbar { EditButton() }
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
                HStack {
                    TextField(L("名称", "Name", "名前"), text: $style.name)
                    if settings.selectedStyle?.id == style.id {
                        Text(L("默认", "Default", "デフォルト"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
            } header: {
                Text(L("名称", "Name", "名前"))
            } footer: {
                Text(L("显示在键盘的风格菜单里，两三个字最好。", "Shown in the keyboard's style menu. Keep it short.", "キーボードの文体メニューに表示されます。短めがおすすめです。"))
            }
            Section {
                TextEditor(text: $style.prompt)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text(L("比如：场景是回复客户，语气耐心", "e.g. Replying to customers, patient tone", "例：お客様への返信、丁寧で落ち着いた語調"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text(L("提示词", "Prompt", "プロンプト"))
            } footer: {
                Text(L("描述场景和语气，会加到每次请求的系统提示里。", "Describe the context and tone. It's added to the system prompt of every request.", "場面と語調を書きます。毎回のリクエストのシステムプロンプトに追加されます。"))
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
                    Text(builtIn == nil ? L("点一下加进提示词，再点一下拿掉。自定义风格显示通用建议。", "Tap to add to the prompt, tap again to remove. Custom styles show general suggestions.", "タップでプロンプトに追加、もう一度タップで外します。カスタムの文体には汎用の候補を表示します。") : L("点一下加进提示词，再点一下拿掉。", "Tap to add to the prompt, tap again to remove.", "タップでプロンプトに追加、もう一度タップで外します。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 和上面分组标题、说明文字对齐。
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section {
                if let builtIn {
                    Button(L("恢复这个风格的默认提示词", "Restore this style's default prompt", "この文体のプロンプトを元に戻す")) { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button(L("设为默认风格", "Set as default style", "デフォルトの文体にする")) { settings.selectedStyleID = style.id }
                    .disabled(settings.selectedStyle?.id == style.id)
                Button(L("删除这个风格", "Delete this style", "この文体を削除"), role: .destructive) {
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
        .navigationTitle(L("编辑风格", "Edit style", "文体を編集"))
    }
}
