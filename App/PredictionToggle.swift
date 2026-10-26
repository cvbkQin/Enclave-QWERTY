import SwiftUI

/// 键盘设置「拼音」里的联想开关：上屏后候选栏接着给出下一个词。
struct PredictionToggle: View {
    @State private var enabled = Predictor.isEnabled

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { enabled = $0; Predictor.isEnabled = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("联想", "Next-word suggestions", "予測変換"))
                Text(L("选完字后接着给出常跟在后面的词", "Suggests words that often come next after you pick a word", "確定した語のあとに続きやすい語を表示します"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { enabled = Predictor.isEnabled }
    }
}
