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
