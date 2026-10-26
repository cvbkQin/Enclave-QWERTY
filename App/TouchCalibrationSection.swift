import SwiftUI

/// 键盘设置里的「按键判定」卡（PB7）：学了多少次、每个键学得多深的格子、开关、重置。
struct TouchCalibrationSection: View {
    var layout: KeyboardLayout
    @State private var enabled = TouchCalibration.isEnabled
    @State private var summary = TouchCalibration.summary
    @State private var counts = TouchCalibration.counts
    @State private var confirmReset = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                DashCardHeader(icon: "keyboard", title: L("按键判定", "Key detection", "キーの判定"), color: DashColor.input,
                               note: L("只记落点，不记内容", "Tap spots only, never text", "位置だけ、内容は記録しない"))
                DashBigNumber(value: summary.samples.formatted(),
                              unit: L("次按键 · \(summary.keys) 个键已校准", "taps · \(summary.keys) keys adjusted", "回 · \(summary.keys) キー調整済み"))
                grid
                Text(L("颜色越深学得越多。删掉的那下不算，数据不离开手机。",
                       "Darker means more learned. Taps you delete don't count, and nothing leaves this iPhone.",
                       "色が濃いほどよく学習しています。削除した入力は数えず、データは端末の外に出ません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            Toggle(L("按手指习惯校准", "Learn how I tap", "タップの癖に合わせる"), isOn: Binding(
                get: { enabled },
                set: { enabled = $0; TouchCalibration.isEnabled = $0 }))
            Button(L("重置校准", "Reset", "リセット"), role: .destructive) { confirmReset = true }
                .disabled(summary.samples == 0)
        }
        .onAppear(perform: refresh)
        .confirmationDialog(L("重置手指习惯？", "Reset what was learned?", "学習内容をリセットしますか？"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("重置", "Reset", "リセット"), role: .destructive) {
                TouchCalibration.reset()
                refresh()
            }
        }
    }

    /// 现在用的布局，一个键一格，按键盘上的行排；没学过是灰的，学满一个窗口最深。
    private var grid: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { index in
                        cell(index < row.count ? row[index] : nil)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var rows: [[String]] {
        layout == .nineKey
            ? [["2", "3", "4", "5", "6", "7", "8", "9"].map { "9:" + $0 }]
            : ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map { "q:" + String($0) } }
    }

    private var columns: Int { layout == .nineKey ? 8 : 10 }

    @ViewBuilder
    private func cell(_ key: String?) -> some View {
        let level = key.flatMap { counts[$0] }.map { min($0 / TouchCalibration.fullCount, 1) } ?? 0
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(key == nil ? Color.clear : (level == 0 ? DashColor.empty : DashColor.input.opacity(0.2 + 0.8 * level)))
            .frame(height: 22)
            .frame(maxWidth: .infinity)
    }

    private func refresh() {
        enabled = TouchCalibration.isEnabled
        summary = TouchCalibration.summary
        counts = TouchCalibration.counts
    }
}
