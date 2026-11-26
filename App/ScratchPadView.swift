import SwiftUI

/// 打字板：一个空输入框，进来 0.6 秒后自动弹出键盘。App 里没有入口，只给 enclave://playground 和 -playground 启动参数用
/// （模拟器截图、scripts/bench/run-bench.sh 打字基准）。原来这两个打开的是使用指引的第一个场景，使用指引 11-26 去掉（对齐清单第 96 条）。
struct ScratchPadView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            TextField(L("在这里输入…", "Type here…", "ここに入力…"), text: $text, axis: .vertical)
                .lineLimit(6...)
                .focused($focused)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("打字板", "Scratch Pad", "入力テスト"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            focused = true
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button(L("收起键盘", "Hide keyboard", "キーボードを閉じる")) { focused = false }
                }
            }
        }
    }
}
