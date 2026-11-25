import SwiftUI

/// 设置 · 拼音「emoji 候选」开关（0.95 A5）：打出开心、猫、生日这类词时，在那个词后面给一个 emoji。
struct EmojiToggle: View {
    @State private var enabled = EmojiSuggestions.isEnabled

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { enabled = $0; EmojiSuggestions.isEnabled = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("emoji 候选", "Emoji suggestions", "絵文字の候補"))
                Text(L("打出「开心」「猫」这类词时，候选里给一个 emoji，不占首选", "Offers an emoji among the candidates for words like 开心 or 猫, never as the first one",
                       "「开心」「猫」のような語を入力すると、候補に絵文字を 1 つ出します（先頭にはしません）"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { enabled = EmojiSuggestions.isEnabled }
    }
}
