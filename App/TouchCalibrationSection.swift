import SwiftUI

/// 键盘设置里的「按手指习惯校准」：开关、学了多少、重置。
struct TouchCalibrationSection: View {
    @State private var enabled = TouchCalibration.isEnabled
    @State private var summary = TouchCalibration.summary
    @State private var confirmReset = false

    var body: some View {
        Section {
            Toggle(L("按手指习惯校准", "Learn how I tap", "タップの癖に合わせる"), isOn: Binding(
                get: { enabled },
                set: { enabled = $0; TouchCalibration.isEnabled = $0 }))
            LabeledContent(L("已学习", "Learned", "学習済み"),
                           value: L("\(summary.samples) 次按键 · \(summary.keys) 个键已校准",
                                    "\(summary.samples) taps · \(summary.keys) keys adjusted",
                                    "\(summary.samples) 回 · \(summary.keys) キー調整済み"))
            Button(L("重置校准", "Reset", "リセット"), role: .destructive) { confirmReset = true }
                .disabled(summary.samples == 0)
        } header: {
            Text(L("按键判定", "Key detection", "キーの判定"))
        } footer: {
            Text(L("平时打字时自动学习：每个字母键你常按偏到哪儿，判定时就把这个键往那边挪一点。删掉的那下不算。只记落点偏移，不记打的内容，也不离开手机。键盘需要打开「允许完全访问」。",
                   "Learns as you type: if you tend to hit a letter key off-center, that key's target shifts toward where you tap. Taps you delete don't count. Only tap offsets are stored, never what you type, and they stay on this iPhone. Needs Allow Full Access.",
                   "入力しながら自動で学習します。各文字キーをどちらにずれて押しがちかを覚え、判定をその方向に少し寄せます。削除した入力は数えません。保存するのはタップ位置のずれだけで、入力内容は保存せず、端末の外にも出ません。「フルアクセスを許可」が必要です。"))
        }
        .onAppear {
            enabled = TouchCalibration.isEnabled
            summary = TouchCalibration.summary
        }
        .confirmationDialog(L("重置手指习惯？", "Reset what was learned?", "学習内容をリセットしますか？"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("重置", "Reset", "リセット"), role: .destructive) {
                TouchCalibration.reset()
                summary = TouchCalibration.summary
            }
        }
    }
}
