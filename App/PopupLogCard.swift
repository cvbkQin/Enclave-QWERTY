import SwiftUI
import UIKit

/// 测试工具 › 弹出记录（开发版、内测、公测）：键盘最近每次弹出是冷启动还是热启动、各段耗时，一键复制发给我们查「呼出卡」。
/// 只是调试用的列表，正式版不显示也不记（PopupLog.enabled）。
struct PopupLogCard: View {
    @State private var records = PopupLog.load()
    @State private var copied = false

    var body: some View {
        DashCard {
            DashCardHeader(icon: "stopwatch", title: L("弹出记录", "Keyboard pop-ups", "キーボード表示記録"), color: DashColor.input,
                           note: L("最近 \(records.count) 次", "Last \(records.count)", "直近 \(records.count) 回"))
            if records.isEmpty {
                Text(L("弹出几次键盘，这里就有记录了。键盘要开「允许完全访问」才记得下。",
                       "Open the keyboard a few times and records show up here. The keyboard needs Allow Full Access.",
                       "キーボードを何度か表示すると記録が表示されます。「フルアクセスを許可」が必要です。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text(PopupLog.report(records).components(separatedBy: "\n").first ?? "")
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(records.suffix(12).reversed()) { record in
                        Text(record.line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(record.nth == 1 ? Color.orange : Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 16) {
                Button(copied ? L("已复制", "Copied", "コピーしました") : L("复制全部", "Copy all", "すべてコピー")) {
                    UIPasteboard.general.string = PopupLog.report(records)
                    copied = true
                }
                .disabled(records.isEmpty)
                Button(L("刷新", "Refresh", "更新")) {
                    records = PopupLog.load()
                    copied = false
                }
                Button(L("清空", "Clear", "消去")) {
                    PopupLog.clear()
                    records = []
                    copied = false
                }
                .disabled(records.isEmpty)
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .onAppear { records = PopupLog.load() }
    }
}
