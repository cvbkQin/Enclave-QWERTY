import SwiftUI

/// 设置 · 拼音：「自动纠错」开关，全键盘、九宫格各一个，默认开（存在 App Group，键盘弹出时读）。
/// 放在模糊拼音下面、联想上面；标题后带「新」标签，0.95 去掉（0.94 纠错显示规格 CR6）。
struct CorrectionToggles: View {
    @State private var qwerty = CorrectionMemory.isEnabled(nineKey: false)
    @State private var nineKey = CorrectionMemory.isEnabled(nineKey: true)

    /// 「拼音」这一组的脚注，两种键盘共用。
    static var footnote: String { L("按原样拼出的词始终留在候选里，改过的字母在拼音行上标出。改对的词上屏后马上按删除，可恢复成你打的拼音。",
                            "What you typed always stays among the candidates, and changed letters are marked in the pinyin row. Press delete right after a corrected word to get back the pinyin you typed.",
                            "入力どおりの語は常に候補に残り、修正した文字はピンイン行で示されます。修正した語の確定直後に削除を押すと、入力したピンインに戻ります。") }

    var body: some View {
        Toggle(isOn: Binding(get: { qwerty }, set: { qwerty = $0; CorrectionMemory.setEnabled($0, nineKey: false) })) {
            label(L("全键盘自动纠错", "QWERTY autocorrect", "QWERTY の自動修正"),
                  L("拼音像打错时，候选里给出改对的词", "Suggests a corrected word when the pinyin looks mistyped", "ピンインの打ち間違いらしいとき、修正した語を候補に出します"))
        }
        Toggle(isOn: Binding(get: { nineKey }, set: { nineKey = $0; CorrectionMemory.setEnabled($0, nineKey: true) })) {
            label(L("九宫格自动纠错", "9-key autocorrect", "9 キーの自動修正"),
                  L("按错数字时，候选里给出改对的词", "Suggests a corrected word when a key looks mistyped", "キーの押し間違いらしいとき、修正した語を候補に出します"))
        }
        .onAppear {
            qwerty = CorrectionMemory.isEnabled(nineKey: false)
            nineKey = CorrectionMemory.isEnabled(nineKey: true)
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                NewBadge()
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 新功能的小标签：高 18、圆角 9、左右 6、字 11 半粗。
private struct NewBadge: View {
    var body: some View {
        Text(L("新", "New", "新"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
                : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) }))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(Color(UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0x2E / 255, green: 0x27 / 255, blue: 0x66 / 255, alpha: 1)
                : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })))
    }
}
