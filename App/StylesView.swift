import SwiftUI

/// 风格预设：左滑删除，「编辑」拖动排序，添加，恢复默认。这里的顺序就是键盘「正式▾」菜单里的顺序。
struct StylesView: View {
    @Binding var settings: EnclaveSettings

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
                            if !style.prompt.isEmpty {
                                Text(style.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete { settings.styles.remove(atOffsets: $0) }
                .onMove { settings.styles.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("左滑删除，点「编辑」拖动排序。这里的顺序就是键盘「\(settings.selectedStyle?.name ?? "风格")▾」菜单里的顺序。")
            }

            Section {
                Button {
                    settings.styles.append(StylePreset(name: "新风格", prompt: ""))
                } label: {
                    Label("添加风格", systemImage: "plus")
                }
                Button("恢复默认", role: .destructive) {
                    settings.styles = StylePreset.defaults
                    settings.selectedStyleID = nil
                }
            }
        }
        .navigationTitle("风格预设")
        .toolbar { EditButton() }
    }
}

private struct StyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $style.name)
            } header: {
                Text("名称")
            } footer: {
                Text("显示在键盘的风格菜单里，两三个字最好。")
            }
            Section {
                TextEditor(text: $style.prompt)
                    .frame(minHeight: 160)
            } header: {
                Text("提示词")
            } footer: {
                Text("描述场景和语气，例如「场景是微信聊天，语气轻松，句子简短」。会加到每次请求的系统提示里。")
            }
            Section {
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
