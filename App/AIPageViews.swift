import SwiftUI

// AI 标签「接口 | 提示词」的小部件和二级页（第 51、54 条，效果图 design/ai-page、design/prompts-tab）：
// 段标题、最近 20 次的统计和小柱、「最近 20 次」页、提示词的「润色风格 | 问答风格」标签和列表。

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

// MARK: - 提示词：润色风格 / 问答风格（第 54 条，PT1–PT3）

/// 「提示词」下面的两个大标签：各占一半宽、高 48、字 18（没选中常规灰、选中 700 主文字色），条数放在小圆角底里；
/// 底下 1px 分隔线，选中的那个底部 3 高主色下划线（左右各缩 14），下面一行 13 灰字说明。
struct PromptKindTabs: View {
    @Binding var kind: AppRouter.PromptKind
    var polishCount: Int
    var answerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                tab(.polish, title: L("润色风格", "Polish styles", "整えるスタイル"), count: polishCount)
                tab(.answer, title: L("问答风格", "Answer styles", "回答スタイル"), count: answerCount)
            }
            .background(alignment: .bottom) { Rectangle().fill(Color(.separator)).frame(height: 1) }
            Text(kind == .polish
                 ? L("点 ✨ 润色时用「默认」那条；键盘上点名字可以临时换一条。", "Tapping ✨ uses the Default one. Tap the name on the keyboard to switch for a moment.", "✨ で整えるときは「デフォルト」を使います。キーボードで名前をタップすると一時的に切り替えられます。")
                 : L("按住 ✨ 问答时用「默认」那种；键盘上点「问答 ⌄」可以临时换。", "Holding ✨ to ask uses the Default one. Tap Ask ⌄ on the keyboard to switch for a moment.", "✨ 長押しの質問では「デフォルト」を使います。キーボードの「質問 ⌄」で一時的に切り替えられます。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func tab(_ value: AppRouter.PromptKind, title: String, count: Int) -> some View {
        let selected = kind == value
        return Button { kind = value } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 18, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(count)")
                    .font(.system(size: 12.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? DashColor.ai : Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 20)
                    .background(Capsule().fill(selected ? PromptListColor.chip : Color(.systemGray5)))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(alignment: .bottom) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5).fill(DashColor.ai).frame(height: 3).padding(.horizontal, 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum PromptListColor {
    /// 条数小底、「默认」小标签：浅紫 #ECEAFD，深色 #2E2766。
    static let chip = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x2E / 255, green: 0x27 / 255, blue: 0x66 / 255, alpha: 1)
        : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
}

/// 一种风格的列表（照以前的行样式）：分组标题「全部润色风格」+ 右边「编辑 / 完成」；每行名称、「默认」、一句说明、本周次数、›；
/// 「编辑」时就地拖动排序、点 − 删除（平时也能左滑删除）；下面「删掉的预设」带「↶ 加回」，最后「＋ 添加」。
struct PromptListSections: View {
    let answer: Bool
    @Binding var settings: EnclaveSettings
    var edit: (UUID) -> Void
    var add: () -> Void

    private var styles: Binding<[StylePreset]> { answer ? $settings.answerStyles : $settings.styles }
    private var defaultID: UUID? { answer ? settings.selectedAnswerStyle?.id : settings.selectedStyle?.id }

    var body: some View {
        Section {
            ForEach(styles.wrappedValue) { style in
                PromptListRow(name: style.displayName, summary: summary(style), isDefault: style.id == defaultID,
                              count: UsageStats.week((answer ? "answer.style." : "polish.style.") + style.id.uuidString)) {
                    edit(style.id)
                }
            }
            .onDelete(perform: delete)
            .onMove(perform: move)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(answer ? L("全部问答风格", "All answer styles", "すべての回答スタイル") : L("全部润色风格", "All polish styles", "すべての整えるスタイル"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                // 系统的编辑按钮：自己管 editMode 时拖过一次后再拖、点 ⊖ 都没反应（PH2 的经验）。
                EditButton()
                    .font(.system(size: 16))
                    .tint(DashColor.ai)
                    .environment(\.locale, Loc.locale)
            }
            .textCase(nil)
        } footer: {
            PromptListFooter(answer: answer)
        }
        if !missingDefaults.isEmpty {
            Section {
                ForEach(missingDefaults) { preset in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.displayName).font(.system(size: 17))
                            Text(summary(preset)).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button {
                            // 换个新 id：本周次数从 0 算，不和删掉的那条混在一起。
                            styles.wrappedValue.append(StylePreset(name: preset.name, prompt: preset.prompt))
                        } label: {
                            Label(L("加回", "Restore", "戻す"), systemImage: "arrow.uturn.backward")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DashColor.ai)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .deleteDisabled(true)
                    .moveDisabled(true)
                }
            } header: {
                Text(L("删掉的预设", "Deleted presets", "削除したプリセット")).font(.system(size: 13)).textCase(nil)
            } footer: {
                Text(answer
                     ? L("加回到列表最后，内容是默认的；你自己的问答风格不受影响。", "Adds it back at the end with its default text. Your own answer styles stay as they are.", "デフォルトの内容でリストの最後に戻します。自分の回答スタイルはそのままです。")
                     : L("加回到列表最后，内容是默认的；你自己的润色风格不受影响。", "Adds it back at the end with its default text. Your own polish styles stay as they are.", "デフォルトの内容でリストの最後に戻します。自分の整えるスタイルはそのままです。"))
            }
        }
        Section {
            Button(action: add) {
                Label(answer ? L("添加问答风格", "Add answer style", "回答スタイルを追加") : L("添加润色风格", "Add polish style", "整えるスタイルを追加"),
                      systemImage: "plus")
                    .font(.system(size: 17))
                    .foregroundStyle(DashColor.ai)
            }
        }
    }

    private func summary(_ style: StylePreset) -> String {
        answer ? (style.prompt.isEmpty ? AnswerStyleSections.answerFallback : style.prompt) : PolishPromptSections.summary(style)
    }

    /// 拖动只改顺序，不改默认：没选过默认时默认跟着第一条，拖之前先把它记下来，不然拖到最上面的那条就悄悄变成了默认。
    private func move(_ offsets: IndexSet, _ destination: Int) {
        if answer, settings.selectedAnswerStyleID == nil { settings.selectedAnswerStyleID = defaultID }
        if !answer, settings.selectedStyleID == nil { settings.selectedStyleID = defaultID }
        styles.wrappedValue.move(fromOffsets: offsets, toOffset: destination)
    }

    /// 至少留一条；删掉的是默认那条就回到第一条。
    private func delete(_ offsets: IndexSet) {
        guard styles.wrappedValue.count > offsets.count else { return }
        let removed = offsets.map { styles.wrappedValue[$0].id }
        styles.wrappedValue.remove(atOffsets: offsets)
        if answer, let id = settings.selectedAnswerStyleID, removed.contains(id) { settings.selectedAnswerStyleID = nil }
        if !answer, let id = settings.selectedStyleID, removed.contains(id) { settings.selectedStyleID = nil }
    }

    /// 自带的里被删掉的：名字和内容都找不到了才算（改了名或改了内容的还在列表里）。
    private var missingDefaults: [StylePreset] {
        let defaults = answer ? StylePreset.answerDefaults : StylePreset.defaults
        return defaults.filter { preset in
            !styles.wrappedValue.contains { $0.name == preset.name || $0.prompt == preset.prompt }
        }
    }
}

/// 一行：名称 17 +「默认」小标签，下面一句说明 13 灰；右边「N 次」15 灰（0 次更浅）+ ›。编辑状态藏起次数和 ›，点了也不进编辑页。
private struct PromptListRow: View {
    let name: String
    let summary: String
    let isDefault: Bool
    let count: Int
    let open: () -> Void
    @Environment(\.editMode) private var editMode

    private var editing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        Button { if !editing { open() } } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(name).font(.system(size: 17)).foregroundStyle(Color.primary).lineLimit(1)
                        if isDefault {
                            Text(L("默认", "Default", "デフォルト"))
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(DashColor.ai)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(PromptListColor.chip))
                        }
                    }
                    Text(summary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !editing {
                    Text(L("\(count) 次", "\(count)×", "\(count) 回"))
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(count == 0 ? Color(.tertiaryLabel) : Color.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 分隔线从文字左边起。
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityHint(editing ? "" : L("编辑内容", "Edit", "編集"))
    }
}

/// 组脚注：平时说顺序和次数，编辑状态说怎么拖、怎么删。
private struct PromptListFooter: View {
    let answer: Bool
    @Environment(\.editMode) private var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            Text(L("按住右边 ≡ 拖动排序，点左边 − 删除；也可以在列表里向左滑删除。", "Drag ≡ on the right to reorder, tap − on the left to delete. You can also swipe left in the list.", "右の ≡ をドラッグで並べ替え、左の − で削除。リストで左にスワイプしても削除できます。"))
        } else if answer {
            Text(L("顺序就是键盘「问答 ⌄」下拉里的顺序。次数是本周的。点一行编辑内容。", "Same order as the keyboard's Ask ⌄ menu. Counts are for this week. Tap a row to edit it.", "キーボードの「質問 ⌄」と同じ順番です。回数は今週の分です。行をタップすると編集できます。"))
        } else {
            Text(L("顺序就是键盘「润色风格 ⌄」下拉里的顺序。次数是本周的。点一行编辑内容。", "Same order as the keyboard's polish style ⌄ menu. Counts are for this week. Tap a row to edit it.", "キーボードの「整えるスタイル ⌄」と同じ順番です。回数は今週の分です。行をタップすると編集できます。"))
        }
    }
}

/// 「＋ 新建提示词 / 新建问答风格」先加一条空的再进编辑页；没改名也没填内容就返回时把它去掉，不留一条空的。
enum NewPromptCleanup {
    static let polishName = L("新润色风格", "New polish style", "新しい整えるスタイル")
    static let answerName = L("新问答风格", "New answer style", "新しい回答スタイル")

    static func dropIfBlank(_ id: UUID?, answer: Bool, settings: inout EnclaveSettings) {
        guard let id else { return }
        let name = answer ? answerName : polishName
        func blank(_ style: StylePreset) -> Bool {
            style.id == id && style.name.trimmingCharacters(in: .whitespaces) == name
                && style.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if answer {
            // 问答风格至少留一条。
            guard settings.answerStyles.count > 1, settings.answerStyles.contains(where: blank) else { return }
            settings.answerStyles.removeAll(where: blank)
            if settings.selectedAnswerStyleID == id { settings.selectedAnswerStyleID = nil }
        } else {
            guard settings.styles.contains(where: blank) else { return }
            settings.styles.removeAll(where: blank)
            if settings.selectedStyleID == id { settings.selectedStyleID = nil }
        }
    }
}
