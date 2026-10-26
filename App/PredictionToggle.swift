import SwiftUI

/// 键盘设置「拼音」里的联想开关：上屏后候选栏接着给出下一个词；开着时还能选空格连续联想。
struct PredictionToggle: View {
    @State private var enabled = Predictor.isEnabled
    @State private var spaceChains = Predictor.spaceChains

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { enabled = $0; Predictor.isEnabled = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("联想", "Next-word suggestions", "予測変換"))
                Text(L("上屏后接着推荐下一个词", "Suggests words that often come next after you pick a word", "確定した語のあとに続きやすい語を表示します"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            enabled = Predictor.isEnabled
            spaceChains = Predictor.spaceChains
        }
        if enabled {
            Toggle(isOn: Binding(get: { spaceChains }, set: { spaceChains = $0; Predictor.spaceChains = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("空格连续联想", "Space accepts suggestion", "スペースで予測を確定"))
                    Text(L("有联想时按空格上屏第一个词，一直按就一直往下接", "With suggestions showing, space types the first one; keep pressing to continue", "予測表示中にスペースで先頭の語を入力し、押し続けるとつながります"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 键盘设置「英文」里的单词补全和联想开关（和拼音词库页「英文词库」卡里的是同一个）。
struct EnglishSuggestionsToggle: View {
    @State private var enabled = Predictor.englishEnabled

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { enabled = $0; Predictor.englishEnabled = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("单词补全和联想", "Word suggestions", "単語の候補と予測"))
                Text(L("打字时补全单词，打完一个词接着推荐下一个", "Completes words as you type and suggests the next one", "入力中に単語を補完し、次の単語を予測します"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { enabled = Predictor.englishEnabled }
    }
}
