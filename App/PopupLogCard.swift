import SwiftUI
import UIKit

/// 测试工具 › 弹出记录（开发版、内测、公测）：键盘每次弹出用了多久，用大白话写；冷启动和明显慢的另外保留。
/// 一键复制发给我们查「呼出卡」。只是调试用的列表，正式版不显示也不记（PopupLog.enabled）。
struct PopupLogCard: View {
    @State private var recent = PopupLog.load()
    @State private var kept = PopupLog.loadKept()
    @State private var copied = false
    @State private var showsLegend = false
    @State private var snapshotOn = PopupLog.snapshotEnabled

    var body: some View {
        DashCard {
            DashCardHeader(icon: "stopwatch", title: L("弹出记录", "Keyboard pop-ups", "キーボード表示記録"), color: DashColor.input,
                           note: L("最近 \(recent.count) 次", "Last \(recent.count)", "直近 \(recent.count) 回"))
            if recent.isEmpty && kept.isEmpty {
                Text("弹出几次键盘，这里就有记录了。键盘要开「允许完全访问」才记得下。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text(PopupLog.summary(recent)).font(.system(size: 14, weight: .semibold))
                Button(showsLegend ? "收起说明" : "这些数字是什么意思？") { showsLegend.toggle() }
                    .font(.system(size: 13))
                if showsLegend {
                    Text(PopupLog.legend).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !kept.isEmpty {
                    section("冷启动和明显慢的（一直保留）", Array(kept.suffix(10).reversed()))
                }
                section("最近", Array(recent.suffix(10).reversed()))
            }
            // 试验开关（只在开发版、内测、公测的测试工具里）：弹出时先放上次键盘的截图，第一帧马上交出去，真键盘随后换上。
            Toggle(isOn: Binding(get: { snapshotOn }, set: { snapshotOn = $0; PopupLog.snapshotEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("弹出时先显示截图（试验）").font(.system(size: 14, weight: .semibold))
                    Text("开着时，键盘样子和上次一样就先放一张上次截的图，真键盘随后换上。看弹出顺不顺、换的时候闪不闪；收起再弹出才生效，第一次弹出先截图。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 16) {
                Button(copied ? "已复制" : "复制全部") {
                    UIPasteboard.general.string = PopupLog.report(recent: recent, kept: kept)
                    copied = true
                }
                .disabled(recent.isEmpty && kept.isEmpty)
                Button("刷新") { reload() }
                Button("清空最近") {
                    PopupLog.clear()
                    reload()
                }
                .disabled(recent.isEmpty)
                Button("清空保留的") {
                    PopupLog.clearKept()
                    reload()
                }
                .disabled(kept.isEmpty)
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .onAppear { reload() }
    }

    private func reload() {
        recent = PopupLog.load()
        kept = PopupLog.loadKept()
        copied = false
    }

    private func section(_ title: String, _ records: [PopupRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(record.isSlow ? Color.red : record.isCold ? Color.orange : Color.primary)
                    ForEach(record.details, id: \.self) { line in
                        Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
