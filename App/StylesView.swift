import SwiftUI

struct StylesView: View {
    @Binding var styles: [StylePreset]

    var body: some View {
        List {
            ForEach($styles) { $style in
                NavigationLink {
                    StyleEditor(style: $style)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.name)
                        Text(style.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .onDelete { styles.remove(atOffsets: $0) }
            .onMove { styles.move(fromOffsets: $0, toOffset: $1) }

            Button("添加风格") {
                styles.append(StylePreset(name: "新风格", prompt: ""))
            }
            Button("恢复默认") {
                styles = StylePreset.defaults
            }
        }
        .navigationTitle("风格预设")
        .toolbar { EditButton() }
    }
}

private struct StyleEditor: View {
    @Binding var style: StylePreset

    var body: some View {
        Form {
            TextField("名称", text: $style.name)
            Section {
                TextEditor(text: $style.prompt)
                    .frame(minHeight: 160)
            } header: {
                Text("提示词")
            } footer: {
                Text("描述场景和语气，例如「场景是微信聊天，语气轻松，句子简短」。")
            }
        }
        .navigationTitle(style.name)
    }
}
