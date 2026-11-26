import SwiftUI

/// App 里通用的颜色写法（原来放在使用指引 LabView.swift 里，11-26 使用指引去掉后挪到这里）。
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 浅色用 light，深色用 dark（可带透明度）。
    init(light: UInt32, dark: UInt32, darkOpacity: CGFloat = 1) {
        func ui(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark, darkOpacity) : ui(light, 1) })
    }
}


/// 测试工具 › 压力测试（原使用指引页底部那张卡）：「开始测试」进 TypingTestView。
struct StressTestCard: View {
    @State private var lastTest = TypingTestRecord.load().first

    var body: some View {
        card.onAppear { lastTest = TypingTestRecord.load().first }
    }

    private var card: some View {
        NavigationLink {
            TypingTestView()
        } label: {
            DashCard {
                DashCardHeader(icon: "speedometer", title: L("压力测试", "Stress test", "負荷テスト"), color: DashColor.input,
                               note: lastTest.map { L("上次 \(Loc.monthDay($0.date))", "Last \(Loc.monthDay($0.date))", "前回 \(Loc.monthDay($0.date))") })
                if let lastTest {
                    HStack(alignment: .top) {
                        stat("\(lastTest.speed)", L("字 / 分钟", "chars/min", "字／分"))
                        stat(lastTest.slowTotal.map { "\(Int($0.rounded())) ms" } ?? "–", L("较慢的 10% 按键", "slowest 10% of keys", "遅い 10% のキー"))
                        stat(lastTest.memoryPeak.map { "\(Int($0)) MB" } ?? "–", L("键盘内存", "keyboard memory", "キーボードのメモリ"))
                    }
                } else {
                    Text(L("照着文章连续打字，看速度、卡顿和键盘内存", "Type a passage nonstop and see speed, lag and keyboard memory", "文章を続けて入力し、速さ・遅延・メモリを確認"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
