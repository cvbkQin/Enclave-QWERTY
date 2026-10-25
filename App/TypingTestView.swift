import SwiftUI

/// 压力测试：照着一篇文章用 Enclave 键盘连续打字，结束后看打字速度、准确率，以及键盘记下的按键耗时和内存。
/// 开始时清空键盘的统计，这样结果只算这一轮；键盘要开完全访问才记得下统计。
struct TypingTestArticle: Identifiable {
    let id: Int
    let title: String
    let text: String

    /// 练的是中文拼音，文章固定中文。
    static let all: [TypingTestArticle] = [
        TypingTestArticle(id: 0, title: "周末", text: "这个周末天气很好，我们一家人早上七点就出门了。先去菜市场买了新鲜的蔬菜和水果，然后开车去郊外的公园。公园里人不多，草地上开满了小花，孩子们在湖边喂鸭子，玩得特别开心。中午我们在树下野餐，吃了自己做的三明治。下午起风了，我们放了一会儿风筝，四点多才回家。虽然有点累，但是大家都觉得这一天过得很充实。"),
        TypingTestArticle(id: 1, title: "项目周报", text: "本周项目整体进展顺利，前端页面已经完成了百分之八十，后端接口基本联调通过。目前主要的问题是测试环境不太稳定，经常出现数据库连接超时的情况，影响了测试进度。下周计划先解决环境问题，再安排两天时间做性能优化。另外，设计团队提出了几处交互上的修改意见，我们会在周三之前评估工作量，并和产品经理确认最终方案。如果没有其他风险，预计月底可以按时上线。"),
        TypingTestArticle(id: 2, title: "读书", text: "小时候家里书不多，我最喜欢去学校的图书馆。那里有一排排高高的书架，阳光从窗户照进来，空气里有一种旧纸张的味道。每次借到一本新书，我都会迫不及待地在回家的路上翻开。后来工作越来越忙，读书的时间越来越少，手机占据了大部分的空闲。最近我重新养成了睡前读书的习惯，每天哪怕只读二十分钟，也觉得心里安静了很多。"),
    ]
}

struct TypingTestView: View {
    @State private var article = TypingTestArticle.all[0]
    @State private var typed = ""
    @State private var startedAt: Date?
    @State private var finishedAt: Date?
    @State private var stats: TypingStats.Summary?
    @State private var modelInstalled = GrammarModel.isInstalled
    @FocusState private var focused: Bool

    private var target: [Character] { Array(article.text) }
    private var typedChars: [Character] { Array(typed) }
    private var correctCount: Int { zip(typedChars, target).filter { $0 == $1 }.count }
    private var finished: Bool { finishedAt != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("压力测试", "Stress test", "負荷テスト")).font(.title.bold())
                    Text(L("切到 Enclave 键盘，照着下面的文章连续打。打完点「完成」，看速度、卡顿和键盘内存。",
                           "Switch to the Enclave keyboard and type the passage below. Tap Done to see speed, lag and keyboard memory.",
                           "Enclave キーボードに切り替えて、下の文章を入力します。「完了」で速さ、遅延、メモリを確認できます。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Picker(L("文章", "Passage", "文章"), selection: Binding(get: { article.id }, set: { choose($0) })) {
                    ForEach(TypingTestArticle.all) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.segmented)
                articleView
                TextField(L("在这里打字…", "Type here…", "ここに入力…"), text: $typed, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($focused)
                    .disabled(finished)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColor.purple, lineWidth: focused ? 2 : 0))
                    .onChange(of: typed) { value in
                        if startedAt == nil && !value.isEmpty { start() }
                        if value.count >= target.count && !finished { finish() }
                    }
                progressRow
                if finished { results }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("压力测试", "Stress test", "負荷テスト"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if finished || startedAt != nil {
                    Button(L("重来", "Restart", "やり直す")) { choose(article.id) }
                }
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button(L("完成", "Done", "完了")) { finish() }.disabled(startedAt == nil)
                }
            }
        }
        .onAppear { modelInstalled = GrammarModel.isInstalled }
    }

    /// 原文：打对的字变绿，打错的变红，没打到的灰色。
    private var articleView: some View {
        let typed = typedChars
        let text = target.enumerated().reduce(Text("")) { result, item in
            let (index, char) = item
            let color: Color = index >= typed.count ? .secondary : (typed[index] == char ? .green : .red)
            return result + Text(String(char)).foregroundColor(color)
        }
        return text
            .font(.system(size: 17))
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var progressRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = elapsedSeconds(now: context.date)
            HStack {
                Text(L("\(typedChars.count) / \(target.count) 字", "\(typedChars.count) / \(target.count) chars", "\(typedChars.count) / \(target.count) 字"))
                Spacer()
                Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)).monospacedDigit()
                Text(L("\(speed(elapsed)) 字/分", "\(speed(elapsed)) chars/min", "\(speed(elapsed)) 字/分"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private var results: some View {
        let elapsed = elapsedSeconds(now: finishedAt ?? Date())
        return VStack(alignment: .leading, spacing: 0) {
            Text(L("结果", "Results", "結果")).font(.headline).padding(.bottom, 10)
            resultRow(L("速度", "Speed", "速さ"), L("\(speed(elapsed)) 字/分", "\(speed(elapsed)) chars/min", "\(speed(elapsed)) 字/分"))
            resultRow(L("准确率", "Accuracy", "正確さ"), typedChars.isEmpty ? "–" : String(format: "%.0f%%", Double(correctCount) / Double(typedChars.count) * 100))
            resultRow(L("整句模型", "Sentence model", "文章モデル"), modelInstalled ? L("已开", "On", "オン") : L("未下载", "Not downloaded", "未ダウンロード"))
            if let stats {
                Divider().padding(.vertical, 8)
                resultRow(L("按键到候选：一般", "Key to candidates: typical", "キー→候補：通常"), Self.ms(stats.medianTotal))
                resultRow(L("较慢的 10%", "Slowest 10%", "遅い 10%"), Self.ms(stats.slowTotal))
                resultRow(L("最慢", "Slowest", "最も遅い"), Self.ms(stats.slowestTotal))
                if let memory = stats.memoryWithModel ?? stats.memory {
                    resultRow(L("键盘内存 一般 / 最高", "Keyboard memory typical / peak", "メモリ 通常 / 最大"),
                              String(format: "%.0f / %.0f MB", memory.median, memory.peak))
                }
                resultRow(L("内存警告", "Memory warnings", "メモリ警告"), "\(stats.memoryWarnings)")
            } else {
                Text(L("键盘没有记下按键数据：要在系统设置里给 Enclave 键盘开「允许完全访问」。",
                       "The keyboard didn't record key data. Turn on Allow Full Access for Enclave in Settings.",
                       "キーボードの記録がありません。設定で Enclave の「フルアクセスを許可」をオンにしてください。"))
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func resultRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private func choose(_ id: Int) {
        article = TypingTestArticle.all.first { $0.id == id } ?? TypingTestArticle.all[0]
        typed = ""
        startedAt = nil
        finishedAt = nil
        stats = nil
        focused = true
    }

    private func start() {
        startedAt = Date()
        // 只算这一轮：清掉键盘之前的记录。
        TypingStats.clear()
    }

    private func finish() {
        guard startedAt != nil, finishedAt == nil else { return }
        finishedAt = Date()
        // 收起键盘时键盘会把最后几个键的数据写进去，稍等一下再读。
        focused = false
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            stats = TypingStats.summary
        }
    }

    private func elapsedSeconds(now: Date) -> Double {
        guard let startedAt else { return 0 }
        return max(0, (finishedAt ?? now).timeIntervalSince(startedAt))
    }

    private func speed(_ elapsed: Double) -> Int {
        elapsed < 1 ? 0 : Int(Double(typedChars.count) / elapsed * 60)
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }
}
