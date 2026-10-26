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

/// 每一轮压力测试的结果，存在 App 自己这边，最多留 50 条，最新的在前面。
struct TypingTestRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var article: String
    var layout: KeyboardLayout
    var model: Bool
    /// 测的时候开没开手指校准、已经校准了几个键（加这一项之前的记录为空）。
    var calibratedKeys: Int?
    var chars: Int
    var seconds: Double
    var accuracy: Double?
    /// 下面是键盘记下的数据，键盘没开完全访问时为空。
    var medianTotal: Double?
    var slowTotal: Double?
    var slowestTotal: Double?
    var medianEngine: Double?
    var memoryMedian: Double?
    var memoryPeak: Double?
    var memoryWarnings: Int?

    var speed: Int { seconds < 1 ? 0 : Int(Double(chars) / seconds * 60) }

    private static let key = "typingTest.history"
    private static let keep = 50

    static func load() -> [TypingTestRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TypingTestRecord].self, from: data)) ?? []
    }

    static func save(_ records: [TypingTestRecord]) {
        if let data = try? JSONEncoder().encode(Array(records.prefix(keep))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct TypingTestView: View {
    @State private var article = TypingTestArticle.all[0]
    @State private var typed = ""
    @State private var startedAt: Date?
    @State private var finishedAt: Date?
    @State private var stats: TypingStats.Summary?
    @State private var modelInstalled = GrammarModel.isActive
    @State private var history = TypingTestRecord.load()
    @State private var confirmClear = false
    @State private var expanded: UUID?
    @FocusState private var focused: Bool

    private var target: [Character] { Array(article.text) }
    /// 只比汉字：标点、空格不算（不打标点也不会把后面全判错），还没上屏的拼音字母也不算。
    private var targetChars: [Character] { target.filter(Self.counts) }
    private var typedChars: [Character] { Array(typed).filter(Self.counts) }
    private var correctCount: Int { zip(typedChars, targetChars).filter { $0 == $1 }.count }

    private static func counts(_ char: Character) -> Bool {
        !(char.isASCII || char.isPunctuation || char.isWhitespace || char.isSymbol)
    }
    private var finished: Bool { finishedAt != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("压力测试", "Stress test", "負荷テスト")).font(.title.bold())
                    Text(L("切到飞地输入法，照着下面的文章连续打。打完点「完成」，看速度、卡顿和键盘内存。",
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
                        if typedChars.count >= targetChars.count && !finished { finish() }
                    }
                progressRow
                if finished { results }
                if history.count > 1 { historyChart }
                if !history.isEmpty { historyList }
            }
            // 左右和 DashPage 一样 20。
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(DashColor.page)
        .navigationTitle(L("压力测试", "Stress test", "負荷テスト"))
        // 底部标签栏会盖住结果卡片。
        .toolbar(.hidden, for: .tabBar)
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
        .onAppear { modelInstalled = GrammarModel.isActive }
        .confirmationDialog(L("清空所有历史记录？", "Clear all history?", "履歴をすべて消去しますか？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("清空", "Clear", "消去"), role: .destructive) {
                history = []
                TypingTestRecord.save(history)
            }
        }
        // 和场景页一样，进来自动弹出键盘。
        .task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            focused = true
        }
    }

    /// 原文：打对的字变绿，打错的变红，没打到的灰色。连续同色的字拼成一段，每打一个字只重排几段文字，
    /// 不拖慢输入框（这页本身卡的话，测出来的就不是键盘了）。
    private var articleView: some View {
        let typed = typedChars
        var runs: [(Color, String)] = []
        var index = 0
        var previous: Color = .secondary
        for char in target {
            // 标点跟着前一个字的颜色。
            var color = previous
            if Self.counts(char) {
                color = index >= typed.count ? .secondary : (typed[index] == char ? .green : .red)
                index += 1
                previous = color
            }
            if let last = runs.last, last.0 == color {
                runs[runs.count - 1].1.append(char)
            } else {
                runs.append((color, String(char)))
            }
        }
        let text = runs.reduce(Text("")) { $0 + Text($1.1).foregroundColor($1.0) }
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
                Text(L("\(typedChars.count) / \(targetChars.count) 字", "\(typedChars.count) / \(targetChars.count) chars", "\(typedChars.count) / \(targetChars.count) 字"))
                Spacer()
                Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)).monospacedDigit()
                Text(L("\(speed(elapsed)) 字/分", "\(speed(elapsed)) chars/min", "\(speed(elapsed)) 字/分"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    /// 这次结果（PB9）：大数字是速度，和上一轮比快了还是慢了；下面三格是准确率、一般延迟、键盘内存。
    private var results: some View {
        let elapsed = elapsedSeconds(now: finishedAt ?? Date())
        let current = speed(elapsed)
        let previous = history.first { $0.date != startedAt }
        let memory = stats?.memoryWithModel ?? stats?.memory
        return DashCard {
            DashCardHeader(icon: "keyboard", title: L("这次结果", "This run", "今回の結果"), color: DashColor.input,
                           note: "《\(article.title)》· " + SettingsStore.load().keyboardLayout.shortTitle)
            HStack(alignment: .firstTextBaseline) {
                DashBigNumber(value: "\(current)", unit: L("字 / 分钟", "chars / min", "字 / 分"))
                Spacer()
                if let previous, previous.speed != current {
                    let diff = current - previous.speed
                    Text(diff > 0 ? L("比上次快 \(diff)", "\(diff) faster than last", "前回より \(diff) 速い")
                                  : L("比上次慢 \(-diff)", "\(-diff) slower than last", "前回より \(-diff) 遅い"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(diff > 0 ? DashColor.ok : Color.orange)
                }
            }
            HStack(alignment: .top) {
                TypingSmallStat(value: typedChars.isEmpty ? "–" : String(format: "%.0f%%", Double(correctCount) / Double(typedChars.count) * 100),
                                label: L("准确率", "Accuracy", "正確さ"))
                TypingSmallStat(value: stats.map { Self.ms($0.medianTotal) } ?? "–", label: L("一般延迟", "Typical lag", "通常の遅延"))
                TypingSmallStat(value: memory.map { String(format: "%.0f MB", $0.median) } ?? "–", label: L("键盘内存", "Keyboard memory", "キーボードメモリ"))
            }
            if stats == nil {
                Text(L("键盘没有记下按键数据：要在系统设置里给飞地输入法开「允许完全访问」。",
                       "The keyboard didn't record key data. Turn on Allow Full Access for Enclave in Settings.",
                       "キーボードの記録がありません。設定で Enclave の「フルアクセスを許可」をオンにしてください。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// 历史曲线：最近 10 轮的速度，旧的在左。
    private var historyChart: some View {
        let recent = Array(history.prefix(10).reversed())
        return DashCard {
            DashCardHeader(icon: "keyboard", title: L("历史", "History", "履歴"), color: DashColor.input,
                           note: L("最近 \(recent.count) 次 · 字/分钟", "Last \(recent.count) · chars/min", "直近 \(recent.count) 回 · 字/分"))
            SpeedLine(values: recent.map { Double($0.speed) })
        }
    }

    /// 以前每一轮的结果，最新的在上面；点一行展开键盘记下的数据。
    private var historyList: some View {
        VStack(alignment: .trailing, spacing: 8) {
            DashCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider().padding(.leading, 16) }
                        historyRow(record)
                    }
                }
            }
            Button(L("清空记录", "Clear history", "履歴を消去")) { confirmClear = true }
                .font(.footnote.weight(.semibold))
                .padding(.trailing, 4)
        }
    }

    private func historyRow(_ record: TypingTestRecord) -> some View {
        let open = expanded == record.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded = open ? nil : record.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("《\(record.article)》").font(.body)
                            if record.model { DashTag(text: L("整句", "Sentence", "文章"), color: DashColor.ai) }
                        }
                        Text(record.date.formatted(.dateTime.month().day().hour().minute()) + " · " + record.layout.shortTitle)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(record.speed)").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                        if let accuracy = record.accuracy {
                            Text(L("准确 \(Int(accuracy * 100))%", "\(Int(accuracy * 100))% right", "正確 \(Int(accuracy * 100))%"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if open {
                    Text(details(record).joined(separator: "\n"))
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 展开后看的：用时、键盘延迟、引擎、内存、校准。
    private func details(_ record: TypingTestRecord) -> [String] {
        var lines = [L("\(record.chars) 字 · 用时 \(Int(record.seconds)) 秒", "\(record.chars) chars · \(Int(record.seconds)) s", "\(record.chars) 字 · \(Int(record.seconds)) 秒")]
        if let median = record.medianTotal, let slow = record.slowTotal, let slowest = record.slowestTotal {
            lines.append(L("按键 一般 \(Self.ms(median)) · 较慢 10% \(Self.ms(slow)) · 最慢 \(Self.ms(slowest))",
                           "Keys typical \(Self.ms(median)) · slow 10% \(Self.ms(slow)) · max \(Self.ms(slowest))",
                           "キー 通常 \(Self.ms(median)) · 遅い10% \(Self.ms(slow)) · 最大 \(Self.ms(slowest))"))
        }
        if let engine = record.medianEngine { lines.append(L("其中拼音引擎 \(Self.ms(engine))", "Pinyin engine \(Self.ms(engine))", "うちエンジン \(Self.ms(engine))")) }
        if let median = record.memoryMedian, let peak = record.memoryPeak {
            var memory = L("键盘内存 一般 / 最高 ", "Memory typical / peak ", "メモリ 通常 / 最大 ") + String(format: "%.0f / %.0f MB", median, peak)
            if let warnings = record.memoryWarnings, warnings > 0 {
                memory += L(" · 内存警告 \(warnings)", " · \(warnings) warnings", " · 警告 \(warnings)")
            }
            lines.append(memory)
        }
        lines.append(record.model ? L("整句模型开", "Sentence model on", "文章モデルオン") : L("整句模型关", "Sentence model off", "文章モデルオフ"))
        lines += calibration(record)
        return lines
    }

    private func calibration(_ record: TypingTestRecord) -> [String] {
        guard let keys = record.calibratedKeys else { return [] }
        return [keys > 0 ? L("手指校准 \(keys) 个键", "\(keys) keys tuned", "調整 \(keys) キー") : L("未校准", "Not tuned", "未調整")]
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
            record()
        }
    }

    /// 这一轮存进历史记录。
    private func record() {
        guard let startedAt, let finishedAt, !typedChars.isEmpty else { return }
        let memory = stats?.memoryWithModel ?? stats?.memory
        let entry = TypingTestRecord(
            date: startedAt, article: article.title, layout: SettingsStore.load().keyboardLayout, model: modelInstalled,
            calibratedKeys: TouchCalibration.isEnabled ? TouchCalibration.summary.keys : 0,
            chars: typedChars.count, seconds: finishedAt.timeIntervalSince(startedAt),
            accuracy: Double(correctCount) / Double(typedChars.count),
            medianTotal: stats?.medianTotal, slowTotal: stats?.slowTotal, slowestTotal: stats?.slowestTotal,
            medianEngine: stats?.medianEngine, memoryMedian: memory?.median, memoryPeak: memory?.peak,
            memoryWarnings: stats?.memoryWarnings)
        history.insert(entry, at: 0)
        TypingTestRecord.save(history)
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

/// 速度折线：蓝线加圆点，上下各留 6pt；只有一个点时画一条灰线。
private struct SpeedLine: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(DashColor.input, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { index in
                        Circle().fill(DashColor.input).frame(width: 6, height: 6).position(points[index])
                    }
                } else {
                    Capsule().fill(DashColor.empty).frame(height: 2)
                }
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(values.map { String(Int($0)) }.joined(separator: ", "))
    }

    private static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let span = max(high - low, 1)
        let step = (size.width - 6) / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            // 越快越靠上。
            CGPoint(x: 3 + CGFloat(index) * step, y: 6 + (size.height - 12) * CGFloat(1 - (value - low) / span))
        }
    }
}
