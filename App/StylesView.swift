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
                                Text(style.name)
                                if style.id == settings.selectedStyle?.id {
                                    Text("默认")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                }
                            }
                            Text(style.prompt.isEmpty ? "按原文的场景和语气润色，不改变意思。" : style.prompt)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { settings.styles.remove(atOffsets: $0) }
                .onMove { settings.styles.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("每个风格是一段提示词，润色时带上。")
                    .font(.subheadline)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                Text("这里的顺序就是键盘「\(settings.selectedStyle?.name ?? "风格")▾」菜单里的顺序。点「编辑」拖动排序，左滑删除。")
            }

            Section {
                Button {
                    settings.styles.append(StylePreset(name: "新风格", prompt: ""))
                } label: {
                    Label("添加风格", systemImage: "plus")
                }
            }
            Section {
                Button("恢复默认风格") { confirmReset = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .confirmationDialog("恢复成默认的 5 个风格？你改过和添加的风格会被删掉。", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复默认风格", role: .destructive) {
                settings.styles = StylePreset.defaults
                settings.selectedStyleID = nil
            }
        }
        .navigationTitle("风格")
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
                    TextField("名称", text: $style.name)
                    if settings.selectedStyle?.id == style.id {
                        Text("默认")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
            } header: {
                Text("名称")
            } footer: {
                Text("显示在键盘的风格菜单里，两三个字最好。")
            }
            Section {
                TextEditor(text: $style.prompt)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text("比如：场景是回复客户，语气耐心")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("提示词")
            } footer: {
                Text("描述场景和语气，会加到每次请求的系统提示里。")
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("建议", systemImage: "sparkle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.deepPurple)
                    SuggestionChips(tags: StyleSuggestions.tags(for: style), prompt: $style.prompt)
                    Text(builtIn == nil ? "点一下加进提示词，再点一下拿掉。自定义风格显示通用建议。" : "点一下加进提示词，再点一下拿掉。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }
            Section {
                if let builtIn {
                    Button("恢复这个风格的默认提示词") { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button("设为默认风格") { settings.selectedStyleID = style.id }
                    .disabled(settings.selectedStyle?.id == style.id)
                Button("删除这个风格", role: .destructive) {
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
        .navigationTitle("编辑风格")
    }
}
