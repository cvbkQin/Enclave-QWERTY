import SwiftUI

// AI 标签「接口 | 提示词」的小部件和二级页（第 51 条，效果图 design/ai-page/AT1–AT4）：
// 段标题、提示词卡片、最近 20 次的统计和小柱、「最近 20 次」页、「管理提示词 / 管理问答风格」页。

/// 段标题：20 粗，黑字（放在列表分组的 header 里）。
struct AISectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 12)
    }
}

/// 提示词卡片（AT2）：名称 15.5 粗 + 说明最多两行 12.5 灰，最小高 74，圆角 14；选中的 2pt 主色描边 + 右上 ✓。
struct PromptCard: View {
    let name: String
    let summary: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.system(size: 15.5, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(DashColor.ai)
                    }
                }
                Text(summary).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DashColor.card))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DashColor.ai, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 「19/20 成功  平均 1.0 秒」（slowest 时再加「最慢 3.6 秒」）；数字粗黑，其余灰。
struct RecentStatsText: View {
    let requests: [UsageStats.Request]
    let slowest: Bool

    var body: some View {
        let ok = requests.filter(\.ok)
        let average = ok.isEmpty ? nil : Double(ok.reduce(0) { $0 + $1.ms }) / Double(ok.count) / 1000
        let slow = ok.map(\.ms).max().map { Double($0) / 1000 }
        var text = bold("\(ok.count)") + gray("/\(requests.count) " + L("成功", "OK", "成功"))
        if let average {
            text = text + gray(L("   平均 ", "   avg ", "   平均 ")) + bold(String(format: "%.1f", average)) + gray(L(" 秒", " s", " 秒"))
        }
        if slowest, let slow {
            text = text + gray(L("   最慢 ", "   max ", "   最長 ")) + bold(String(format: "%.1f", slow)) + gray(L(" 秒", " s", " 秒"))
        }
        return text.font(.system(size: 14)).lineLimit(1)
    }

    private func bold(_ text: String) -> Text { Text(text).fontWeight(.bold).foregroundColor(.primary) }
    private func gray(_ text: String) -> Text { Text(text).foregroundColor(.secondary) }
}

/// 20 根小柱：左旧右新；绿成功、橙超过 3 秒、红失败（满高）；高度按耗时，4 秒封顶。不满 20 次时左边留空。
struct RecentBars: View {
    let requests: [UsageStats.Request]
    let height: CGFloat

    static let green = Color(light: 0x22A45D, dark: 0x30D158)
    static let orange = Color(light: 0xF59E0B, dark: 0xFFB340)
    static let red = Color(light: 0xE5484D, dark: 0xFF6369)

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                let slots = UsageStats.recentLimit
                let shown = Array(requests.suffix(slots))
                ForEach(0..<slots, id: \.self) { slot in
                    let index = slot - (slots - shown.count)
                    if index >= 0 {
                        let request = shown[index]
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Self.color(request))
                            .frame(height: barHeight(request))
                            .frame(maxWidth: .infinity)
                    } else {
                        Color.clear.frame(height: 1).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack {
                Text(L("\(UsageStats.recentLimit) 次前", "\(UsageStats.recentLimit) ago", "\(UsageStats.recentLimit) 回前"))
                Spacer()
                Text(L("最新", "Latest", "最新"))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("最近 \(requests.count) 次调用", "Last \(requests.count) requests", "直近 \(requests.count) 回の呼び出し"))
    }

    private func barHeight(_ request: UsageStats.Request) -> CGFloat {
        guard request.ok else { return height }
        let fraction = min(Double(request.ms) / 4000, 1)
        return max(height * 0.28, height * CGFloat(fraction))
    }

    static func color(_ request: UsageStats.Request) -> Color {
        request.ok ? (request.slow ? orange : green) : red
    }
}

// MARK: - 最近 20 次（AT3）

struct RecentRequestsView: View {
    let answer: Bool
    @State private var requests: [UsageStats.Request] = []
    @State private var confirmsClear = false

    var body: some View {
        List {
            Section {} header: {
                DashCard {
                    if requests.isEmpty {
                        Text(L("还没有调用记录", "No requests yet", "まだ呼び出しはありません")).font(.system(size: 14)).foregroundStyle(.secondary)
                    } else {
                        RecentStatsText(requests: requests, slowest: true)
                        RecentBars(requests: requests, height: 46)
                    }
                }
                .dashFormCard()
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(Array(group.requests.enumerated()), id: \.offset) { _, request in
                        RecentRequestRow(request: request)
                    }
                }
            }
            Section {
                Button { confirmsClear = true } label: {
                    Text(L("清空记录", "Clear", "記録を消去"))
                        .foregroundStyle(Color(hex: 0xFF3B30))
                        .frame(maxWidth: .infinity)
                }
                .disabled(requests.isEmpty)
            } header: {
                Text(L("只记时间、成功或失败、耗时、用的提示词和模型，不记你打的字和 AI 的回答（那些在「历史」里）。只存在这台 iPhone 上，润色、问答各留最近 \(UsageStats.recentLimit) 次。",
                       "Only the time, success or failure, duration, prompt and model are kept, never what you typed or the AI's reply (those are in History). Stored only on this iPhone; the last \(UsageStats.recentLimit) for Polish and for Q&A.",
                       "時刻・成否・所要時間・プロンプトとモデルだけを記録し、入力した文や AI の回答は記録しません（それは「履歴」にあります）。この iPhone にだけ保存し、整える・質問それぞれ直近 \(UsageStats.recentLimit) 回です。"))
                    .textCase(nil)
                    // 说明文字，同其他页的脚注：小号灰字（放在 header 里时系统默认是大号粗体）。
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle((answer ? L("问答", "Q&A", "質問") : L("润色", "Polish", "整える")) + " · " + L("最近 \(UsageStats.recentLimit) 次", "Last \(UsageStats.recentLimit)", "直近 \(UsageStats.recentLimit) 回"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in reload() }
        .alert(L("清空最近 \(UsageStats.recentLimit) 次？", "Clear the last \(UsageStats.recentLimit)?", "直近 \(UsageStats.recentLimit) 回を消去しますか？"), isPresented: $confirmsClear) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("清空", "Clear", "消去"), role: .destructive) {
                UsageStats.clearRecent(answer: answer)
                reload()
            }
        } message: {
            Text(answer ? L("问答卡的统计和小柱从零开始。", "The Q&A card's stats and bars start over.", "質問カードの統計とバーはゼロから始まります。")
                 : L("润色卡的统计和小柱从零开始。", "The Polish card's stats and bars start over.", "整えるカードの統計とバーはゼロから始まります。"))
        }
    }

    private func reload() {
        requests = answer ? UsageStats.answerRecent : UsageStats.polishRecent
    }

    private struct DayGroup {
        let title: String
        let requests: [UsageStats.Request]
    }

    /// 按天分组，新的在上。
    private var groups: [DayGroup] {
        var result: [DayGroup] = []
        for request in requests.reversed() {
            let title = HistoryFormat.day(request.at)
            if result.last?.title == title {
                result[result.count - 1] = DayGroup(title: title, requests: result[result.count - 1].requests + [request])
            } else {
                result.append(DayGroup(title: title, requests: [request]))
            }
        }
        return result
    }
}

/// 一次调用：左边圆点（绿 ✓、橙 ✓ 较慢、红 !），时间，第二行灰字「提示词 · 模型」或失败原因；右边耗时（失败写红字「失败」）。
private struct RecentRequestRow: View {
    let request: UsageStats.Request

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(RecentBars.color(request))
                Image(systemName: request.ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(HistoryFormat.time(request.at)).font(.system(size: 16)).monospacedDigit()
                if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if request.ok {
                Text(String(format: "%.1f", Double(request.ms) / 1000) + L(" 秒", " s", " 秒"))
                    .font(.system(size: 16)).monospacedDigit()
                    .foregroundStyle(request.slow ? RecentBars.orange : .primary)
            } else {
                Text(L("失败", "Failed", "失敗")).font(.system(size: 16)).foregroundStyle(RecentBars.red)
            }
        }
        .padding(.vertical, 2)
    }

    /// 「正式 · deepseek-flash · 较慢」「联网 · 搜索 2.1 秒」「超时：太久没有回应」「测试连接 · kimi-k2」。旧数据什么都没有就不写这一行。
    private var detail: String? {
        var parts: [String] = []
        if !request.ok {
            parts.append(request.failureText)
            if request.test == true { parts.append(L("测试连接", "Connection test", "接続テスト")) }
        } else {
            if request.test == true { parts.append(L("测试连接", "Connection test", "接続テスト")) }
            if let style = request.styleName { parts.append(style) }
            if let model = request.model, !model.isEmpty { parts.append(model) }
            if request.slow { parts.append(L("较慢", "slow", "遅め")) }
            if let search = request.webSearchMs {
                parts.append(L("联网", "web", "ウェブ"))
                parts.append(L("搜索 ", "search ", "検索 ") + String(format: "%.1f", Double(search) / 1000) + L(" 秒", " s", " 秒"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - 管理提示词 / 管理问答风格（AT4）

/// 一直在编辑状态：左边红色 −（第一条默认的没有）、名称、「编辑」、拖动把手；「删掉的预设」带「加回」；最下「＋ 新建」。
struct ManagePromptsView: View {
    let answer: Bool
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: UUID?

    private var styles: Binding<[StylePreset]> {
        answer ? $store.settings.answerStyles : $store.settings.styles
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(styles.wrappedValue.enumerated()), id: \.element.id) { index, style in
                    HStack {
                        Text(style.displayName)
                        Spacer(minLength: 8)
                        Button(L("编辑", "Edit", "編集")) { editing = style.id }
                            .buttonStyle(.borderless)
                            .foregroundStyle(DashColor.ai)
                    }
                    .deleteDisabled(index == 0)
                }
                .onDelete { offsets in
                    let removed = offsets.filter { $0 > 0 }.map { styles.wrappedValue[$0].id }
                    styles.wrappedValue.removeAll { removed.contains($0.id) }
                    if answer, let id = store.settings.selectedAnswerStyleID, removed.contains(id) { store.settings.selectedAnswerStyleID = nil }
                    if !answer, let id = store.settings.selectedStyleID, removed.contains(id) { store.settings.selectedStyleID = nil }
                }
                .onMove { styles.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text(L("拖动排序 · 左边删除", "Drag to reorder · tap − to delete", "ドラッグで並べ替え・− で削除"))
            } footer: {
                let first = styles.wrappedValue.first?.displayName ?? ""
                Text(L("第一条「\(first)」是默认的，不能删，可以编辑。顺序就是 AI 页卡片和键盘里风格菜单的顺序。",
                       "The first one, \"\(first)\", is the default: you can edit it but not delete it. This order is used on the AI tab and in the keyboard's style menu.",
                       "最初の「\(first)」はデフォルトで、削除できませんが編集できます。この順番が AI タブのカードとキーボードのスタイルメニューの順番です。"))
            }
            if !missingDefaults.isEmpty {
                Section(L("删掉的预设", "Deleted presets", "削除したプリセット")) {
                    ForEach(missingDefaults) { preset in
                        HStack {
                            Text(preset.displayName).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button(L("加回", "Restore", "戻す")) {
                                // 换个新 id：本周次数从 0 算，不和删掉的那条混在一起。
                                styles.wrappedValue.append(StylePreset(name: preset.name, prompt: preset.prompt))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(DashColor.ai)
                        }
                    }
                }
            }
            Section {
                Button {
                    let style = StylePreset(name: answer ? L("新问答风格", "New answer style", "新しい回答スタイル") : L("新提示词", "New prompt", "新しいプロンプト"), prompt: "")
                    styles.wrappedValue.append(style)
                    editing = style.id
                } label: {
                    Label(answer ? L("新建问答风格", "New answer style", "回答スタイルを追加") : L("新建提示词", "New prompt", "プロンプトを追加"), systemImage: "plus")
                        .foregroundStyle(DashColor.ai)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(answer ? L("管理问答风格", "Manage answer styles", "回答スタイルの管理") : L("管理提示词", "Manage prompts", "プロンプトの管理"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("完成", "Done", "完了")) { dismiss() }.fontWeight(.semibold)
            }
        }
        .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let index = styles.wrappedValue.firstIndex(where: { $0.id == editing }) {
                if answer {
                    AnswerStyleEditor(style: $store.settings.answerStyles[index], settings: $store.settings)
                } else {
                    StyleEditor(style: $store.settings.styles[index], settings: $store.settings)
                }
            }
        }
    }

    /// 自带的里被删掉的：名字和内容都找不到了才算（改了名或改了内容的还在列表里）。
    private var missingDefaults: [StylePreset] {
        let defaults = answer ? StylePreset.answerDefaults : StylePreset.defaults
        return defaults.filter { preset in
            !styles.wrappedValue.contains { $0.name == preset.name || $0.prompt == preset.prompt }
        }
    }
}
