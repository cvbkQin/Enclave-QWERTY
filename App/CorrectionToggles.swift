import SwiftUI

/// 设置 · 拼音：「自动纠错」开关，全键盘、九宫格各一个，默认开（存在 App Group，键盘弹出时读）。
struct CorrectionToggles: View {
    @State private var qwerty = CorrectionMemory.isEnabled(nineKey: false)
    @State private var nineKey = CorrectionMemory.isEnabled(nineKey: true)

    var body: some View {
        Toggle(isOn: Binding(get: { qwerty }, set: { qwerty = $0; CorrectionMemory.setEnabled($0, nineKey: false) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("全键盘自动纠错", "QWERTY autocorrect", "QWERTY の自動修正"))
                Text(L("拼音像打错了时，把纠正的词放进候选，按原样拼出的词仍在", "When the pinyin looks mistyped, suggests the corrected word and keeps what you typed",
                       "ピンインの打ち間違いらしいとき、修正した語を候補に出します。入力どおりの語も残ります"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Toggle(isOn: Binding(get: { nineKey }, set: { nineKey = $0; CorrectionMemory.setEnabled($0, nineKey: true) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("九宫格自动纠错", "9-key autocorrect", "9 キーの自動修正"))
                Text(L("两种键盘都一样：纠正的词上屏后马上按删除，恢复成原样的拼音", "On either keyboard, press delete right after a correction to get back what you typed",
                       "どちらのキーボードでも、修正された語の直後に削除を押すと入力したピンインに戻ります"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            qwerty = CorrectionMemory.isEnabled(nineKey: false)
            nineKey = CorrectionMemory.isEnabled(nineKey: true)
        }
    }
}
