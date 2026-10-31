import SwiftUI
import UIKit

// 「历史」标签（第 48 条，效果图 design/ai-history/HI1–HI8）：键盘里润色和问答的原文、每一版结果，只存在本机。

/// 历史标签：列表 → 详情、历史记录设置。
struct HistoryTab: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.historyPath) {
            HistoryListView()
                .navigationDestination(for: AppRouter.HistoryPage.self) { page in
                    switch page {
                    case .detail(let id): HistoryDetailView(id: id)
                    case .settings: HistorySettingsView()
                    }
                }
        }
    }
}

/// 历史的数据：App 打开、回到前台、进历史页时从文件重读（键盘随时在写）。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [AIHistoryEntry] = []
    @Published var enabled = AIHistory.isEnabled {
        didSet { AIHistory.isEnabled = enabled }
    }
    @Published var retention = AIHistory.retention {
        didSet {
            AIHistory.retention = retention
            Task { await reload() }
        }
    }

    func reload() async {
        enabled = AIHistory.isEnabled
        entries = await Task.detached(priority: .userInitiated) { () -> [AIHistoryEntry] in
            AIHistory.prune()
            return AIHistory.load()
        }.value
    }

    func delete(_ id: String) {
        AIHistory.delete(id)
        entries.removeAll { $0.id == id }
    }

    func clear() {
        AIHistory.clear()
        entries = []
    }

    func entry(_ id: String) -> AIHistoryEntry? { entries.first { $0.id == id } }

    /// 首页、列表顶上的那行小字。
    var caption: String {
        let here = L("只存在这台 iPhone 上", "Only on this iPhone", "この iPhone にだけ保存")
        guard enabled else { return here }
        switch retention {
        case .forever: return here
        default: return here + L(" · 保留 ", " · Kept ", " · 保存 ") + retention.title
        }
    }

    #if DEBUG
    /// 截图用（-historyDemo）：写几条和效果图一样的记录。
    func seedDemo() {
        let now = Date()
        let calendar = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? now
        }
        func polish(_ original: String, _ versions: [String], style: String, used: Int?, use: String?, edited: Int? = nil, date: Date) {
            var session = EditSession(mode: .polish, original: original)
            session.startedAt = date
            for (index, text) in versions.enumerated() {
                session.append(text, edited: index == edited)
                session.noteCurrent(style: style, provider: "DeepSeek")
            }
            if let used {
                session.currentIndex = used
                session.markCurrentUsed(use)
            }
            AIHistory.record(session)
        }
        func answer(_ question: String, context: String, _ text: String, searched: Bool, date: Date) {
            var session = EditSession(mode: .polish, original: context)
            session.startedAt = date
            session.appendAsk(text, answer: true, replacingLast: false, source: .init(question: question, context: context))
            session.noteCurrent(style: "直击要害", provider: "Kimi")
            if searched { session.markSearched(by: "Kimi") }
            AIHistory.record(session)
        }
        polish("不好意思今天去不了了家里有点事", ["抱歉，今天家里临时有事，去不了了，改天再约。", "不好意思，今天家里有点事去不了，改天再约哈。"],
               style: "口语", used: 0, use: "replaced", date: at(1, 18, 3))
        answer("RAG 和微调有什么区别", context: "", "RAG 是查资料再回答，知识随时可换；微调是把知识练进模型里，改起来要重新训练。", searched: false, date: at(1, 22, 14))
        polish("thanks for ur help yesterday really appreciate", ["Thank you so much for your help yesterday. I really appreciate it."],
               style: "翻成英文", used: 0, use: "inserted", date: at(0, 9, 20))
        polish("这个方案我觉得还行但是预算有点超了", ["这个方案整体可行，不过预算略超，能否再压缩一些？"], style: "润色", used: 0, use: "replaced", date: at(0, 11, 48))
        answer("今天上海天气怎么样，要带伞吗", context: "下午去外滩拍照，几点出发比较好", "多云转小雨，14–19°C，下午 3 点后降雨概率 70%，建议带伞。想拍外滩的话最好 2 点前到。", searched: true, date: at(0, 13, 5))
        polish("明天开会的事情我再跟你确认下时间哈", ["明天开会的时间，我再跟你确认一下。", "明天会议的具体时间，我稍后再和您确认一下。", "明天会议的具体时间，我下午再和您确认。"],
               style: "正式", used: 1, use: "replaced", edited: 2, date: at(0, 14, 32))
    }
    #endif
}

extension AIHistoryEntry {
    var kindTitle: String {
        kind == .polish ? L("润色", "Polish", "整える") : L("问答", "Q&A", "質問")
    }

    /// 「今天 14:32」「昨天 22:14」「10月29日 18:03」。
    var timeTitle: String { HistoryFormat.day(date) + " " + HistoryFormat.time(date) }

    /// 风格和服务商：用过的那版的，没有就找一版有的。
    var meta: (style: String?, provider: String?) {
        let info = versions.indices.contains(shownIndex) ? versions[shownIndex] : nil
        let style = info?.style ?? versions.lazy.compactMap(\.style).first
        let provider = info?.provider ?? versions.lazy.compactMap(\.provider).first
        return (style, provider)
    }

    var searchedBy: String? { versions.lazy.compactMap(\.searchedBy).first }

    /// 绿字：「已替换」「已插入」，几版里用了其中一版写「用了第 N 版」。
    var useText: String? {
        guard let index = usedIndex, let use = versions[index].use else { return nil }
        if versions.count > 1 { return L("用了第 \(index + 1) 版", "Used version \(index + 1)", "第 \(index + 1) 版を使用") }
        return HistoryFormat.useTitle(use)
    }
}

enum HistoryFormat {
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("今天", "Today", "今日") }
        if calendar.isDateInYesterday(date) { return L("昨天", "Yesterday", "昨日") }
        return Loc.monthDay(date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func useTitle(_ use: AIHistoryEntry.Use) -> String {
        use == .replaced ? L("已替换", "Replaced", "置き換え済み") : L("已插入", "Inserted", "挿入済み")
    }

    static let green = Color(light: 0x22A45D, dark: 0x4CD38A)
}

// MARK: - 列表（HI1、HI7、HI8）

struct HistoryListView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = HistoryStore.shared
    @State private var query = ""
    @State private var filter: AIHistoryEntry.Kind?
    /// 一次显示 50 条，滑到底再加载。
    @State private var limit = 50
    @State private var confirmsClear = false

    private var filtered: [AIHistoryEntry] {
        store.entries.filter { (filter == nil || $0.kind == filter) && $0.matches(query) }
    }

    var body: some View {
        content
            .pinnedTabTitle(caption: store.caption, title: L("历史", "History", "履歴")) {
                if store.enabled || !store.entries.isEmpty {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            searchField
                            moreMenu
                        }
                        Picker("", selection: $filter) {
                            Text(L("全部", "All", "すべて")).tag(AIHistoryEntry.Kind?.none)
                            Text(L("润色", "Polish", "整える")).tag(AIHistoryEntry.Kind?.some(.polish))
                            Text(L("问答", "Q&A", "質問")).tag(AIHistoryEntry.Kind?.some(.answer))
                        }
                        .pickerStyle(.segmented)
                        .frame(height: 34)
                    }
                } else {
                    HStack { Spacer(); moreMenu }
                }
            }
            .navigationTitle(L("历史", "History", "履歴"))
            .tabRootPage()
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-historyDemo"), AIHistory.load().isEmpty { store.seedDemo() }
                #endif
                await store.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await store.reload() }
            }
            .onChange(of: query) { _ in limit = 50 }
            .onChange(of: filter) { _ in limit = 50 }
            .alert(L("清空全部历史？", "Clear all history?", "履歴をすべて消去しますか？"), isPresented: $confirmsClear) {
                Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
                Button(L("清空", "Clear", "消去"), role: .destructive) { store.clear() }
            } message: {
                Text(L("这台 iPhone 上的润色和问答记录都会删除。", "All polish and Q&A records on this iPhone will be deleted.", "この iPhone の整える・質問の記録がすべて削除されます。"))
            }
    }

    @ViewBuilder
    private var content: some View {
        let list = filtered
        if !store.enabled && store.entries.isEmpty {
            HistoryEmptyView(title: L("记录已关闭", "History is off", "記録はオフです"),
                             message: L("打开后，键盘里润色和问答的原文和结果会存在这里，方便以后找回、复制。",
                                        "Turn it on to keep the original text and results of polish and Q&A from the keyboard here, so you can find and copy them later.",
                                        "オンにすると、キーボードでの整える・質問の元の文と結果がここに保存され、あとで探したりコピーしたりできます。"),
                             button: L("打开记录", "Turn On", "記録をオンにする")) { store.enabled = true }
        } else if store.entries.isEmpty {
            HistoryEmptyView(title: L("还没有记录", "No history yet", "まだ記録はありません"),
                             message: L("在键盘里点 ✨ 润色或问答，结果会出现在这里", "Tap ✨ on the keyboard to polish or ask, and the results show up here.", "キーボードで ✨ をタップして整えたり質問したりすると、結果がここに表示されます。"))
        } else {
            // 搜不到时 List 也留着，「没有找到」盖在上面：换掉 List 会让顶上的搜索框重建、丢焦点，
            // 打到一半的字（还有没选的拼音）就没了（waitan 只剩 wa）。
            List {
                ForEach(groups(Array(list.prefix(limit))), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            Button { router.historyPath.append(AppRouter.HistoryPage.detail(entry.id)) } label: {
                                HistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(L("删除", "Delete", "削除"), role: .destructive) { store.delete(entry.id) }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = entry.shown } label: {
                                    Label(L("复制结果", "Copy Result", "結果をコピー"), systemImage: "doc.on.doc")
                                }
                                Button { UIPasteboard.general.string = entry.original } label: {
                                    Label(L("复制原文", "Copy Original", "元の文をコピー"), systemImage: "text.quote")
                                }
                                Button(role: .destructive) { store.delete(entry.id) } label: {
                                    Label(L("删除", "Delete", "削除"), systemImage: "trash")
                                }
                            }
                            .onAppear {
                                if entry.id == list.prefix(limit).last?.id, list.count > limit { limit += 50 }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if list.isEmpty {
                    HistoryEmptyView(title: L("没有找到「\(query)」", "No results for \"\(query)\"", "「\(query)」は見つかりません"), message: nil)
                }
            }
        }
    }

    private struct DayGroup {
        let title: String
        let entries: [AIHistoryEntry]
    }

    /// 按天分组，新的在上（entries 已经是新的在前）。
    private func groups(_ entries: [AIHistoryEntry]) -> [DayGroup] {
        var result: [DayGroup] = []
        for entry in entries {
            let title = HistoryFormat.day(entry.date)
            if result.last?.title == title {
                result[result.count - 1] = DayGroup(title: title, entries: result[result.count - 1].entries + [entry])
            } else {
                result.append(DayGroup(title: title, entries: [entry]))
            }
        }
        return result
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("搜索原文和结果", "Search originals and results", "元の文と結果を検索"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    private var moreMenu: some View {
        Menu {
            Button { router.historyPath.append(AppRouter.HistoryPage.settings) } label: {
                Label(L("历史记录设置", "History Settings", "履歴の設定"), systemImage: "gearshape")
            }
            Button(role: .destructive) { confirmsClear = true } label: {
                Label(L("清空全部历史", "Clear All History", "履歴をすべて消去"), systemImage: "trash")
            }
            .disabled(store.entries.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.purple)
                .frame(width: 32, height: 36)
        }
        .accessibilityLabel(L("更多", "More", "その他"))
    }
}

/// 一条记录：类型标签（+ 已联网）+ 时间；原文一行；用过的那版最多两行；风格 · 服务商 · N 版 · 用了哪版。
private struct HistoryRow: View {
    let entry: AIHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                HistoryKindBadge(kind: entry.kind)
                if entry.searched {
                    Text("🌐 " + L("已联网", "Web", "ウェブ検索済み")).font(.system(size: 13)).foregroundStyle(DashColor.input)
                }
                Spacer()
                Text(HistoryFormat.time(entry.date)).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(entry.kind == .answer ? L("问：", "Q: ", "問：") + entry.original : entry.original)
                .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            Text(entry.shown).font(.system(size: 16)).foregroundStyle(.primary).lineLimit(2)
            metaLine
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var metaLine: some View {
        let meta = entry.meta
        var parts = [meta.style, meta.provider].compactMap { $0 }
        if entry.kind == .polish || entry.versions.count > 1 {
            parts.append(L("\(entry.versions.count) 版", "\(entry.versions.count) versions", "\(entry.versions.count) 版"))
        }
        let base = Text(parts.joined(separator: " · ")).foregroundColor(Color(.tertiaryLabel))
        let line: Text
        if entry.kind == .polish, let use = entry.useText {
            line = base + Text(parts.isEmpty ? "" : " · ").foregroundColor(Color(.tertiaryLabel)) + Text(use).foregroundColor(HistoryFormat.green)
        } else {
            line = base
        }
        return line.font(.system(size: 13)).lineLimit(1)
    }
}

/// 润色：主色浅底；问答：蓝色浅底。字 11 半粗，高 18 圆角 9。
private struct HistoryKindBadge: View {
    let kind: AIHistoryEntry.Kind

    var body: some View {
        let color = kind == .polish ? AppColor.purple : DashColor.input
        ExtDictBadge(text: kind == .polish ? L("润色", "Polish", "整える") : L("问答", "Q&A", "質問"),
                     fill: color.opacity(0.12), color: color)
    }
}

private struct HistoryEmptyView: View {
    let title: String
    let message: String?
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock").font(.system(size: 44)).foregroundStyle(Color(.systemGray2))
            Text(title).font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let button {
                Button(button, action: action)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.purple)
                    .frame(maxWidth: 260, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.softFill))
                    .padding(.top, 4)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DashColor.page)
    }
}

// MARK: - 详情（HI3、HI4）

struct HistoryDetailView: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = HistoryStore.shared
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let entry = store.entry(id) {
                DashPage {
                    if entry.kind == .polish {
                        HistoryTextCard(title: L("原文", "Original", "元の文"), text: entry.original)
                        groupTitle(L("结果", "Results", "結果"), entry)
                    } else {
                        HistoryTextCard(title: L("问题", "Question", "質問"), text: entry.original)
                        if !entry.context.isEmpty {
                            HistoryTextCard(title: L("一起发送的上下文", "Context sent with it", "一緒に送った文脈"), text: entry.context, secondary: true)
                        }
                        groupTitle(L("回答", "Answer", "回答"), entry)
                    }
                    ForEach(Array(entry.versions.enumerated()), id: \.offset) { index, version in
                        HistoryVersionCard(entry: entry, index: index, version: version)
                    }
                    Button(role: .destructive) { confirmsDelete = true } label: {
                        Text(L("删除这条记录", "Delete This Record", "この記録を削除"))
                            .font(.body)
                            .foregroundStyle(Color(hex: 0xFF3B30))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
                .navigationTitle(entry.kindTitle + " · " + entry.timeTitle)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { UIPasteboard.general.string = entry.shown } label: {
                                Label(L("复制用过的那版", "Copy the Version Used", "使った版をコピー"), systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) { confirmsDelete = true } label: {
                                Label(L("删除", "Delete", "削除"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(AppColor.purple)
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("删除这条记录？", "Delete this record?", "この記録を削除しますか？"), isPresented: $confirmsDelete) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("删除", "Delete", "削除"), role: .destructive) {
                store.delete(id)
                dismiss()
            }
        }
    }

    /// 「结果 · 正式 · DeepSeek」。
    private func groupTitle(_ title: String, _ entry: AIHistoryEntry) -> some View {
        let meta = entry.meta
        return Text(([title] + [meta.style, meta.provider].compactMap { $0 }).joined(separator: " · "))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }
}

/// 白卡：左上灰色小标题，右上「复制」，下面正文。
private struct HistoryTextCard: View {
    let title: String
    let text: String
    var secondary = false

    var body: some View {
        DashCard {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                HistoryCopyButton(text: text)
            }
            Text(text).font(.system(size: 17)).foregroundStyle(secondary ? .secondary : .primary).textSelection(.enabled)
        }
    }
}

/// 一版结果：「第 N 版」（+ 已替换 / 已插入，+ · 已改）；联网过的写「🌐 已联网 · Kimi」。用过的那版主色 2pt 描边。
private struct HistoryVersionCard: View {
    let entry: AIHistoryEntry
    let index: Int
    let version: AIHistoryEntry.Version

    var body: some View {
        let used = entry.usedIndex == index
        DashCard {
            HStack(spacing: 8) {
                if let searchedBy = version.searchedBy {
                    Text("🌐 " + L("已联网", "Web", "ウェブ検索済み") + " · " + searchedBy)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(DashColor.input)
                } else if entry.versions.count > 1 || entry.kind == .polish {
                    Text(L("第 \(index + 1) 版", "Version \(index + 1)", "第 \(index + 1) 版") + (version.edited ? L(" · 已改", " · Edited", " · 編集済み") : ""))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
                if let use = version.use {
                    ExtDictBadge(text: HistoryFormat.useTitle(use), fill: HistoryFormat.green.opacity(0.14), color: HistoryFormat.green)
                }
                Spacer()
                HistoryCopyButton(text: version.text)
            }
            Text(version.text).font(.system(size: 17)).textSelection(.enabled)
        }
        .overlay {
            if used {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppColor.purple, lineWidth: 2)
            }
        }
    }
}

private struct HistoryCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Text(copied ? L("已复制", "Copied", "コピーしました") : L("复制", "Copy", "コピー"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.purple)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 历史记录设置（HI6）

struct HistorySettingsView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Section {
                Toggle(L("记录润色和问答", "Keep Polish and Q&A History", "整える・質問を記録"), isOn: $store.enabled)
            } footer: {
                Text(L("关掉后不再记录新的，已有的留着，可以手动清空。键盘里正在用的这一轮（结果卡上的几版）不受影响。",
                       "When off, nothing new is recorded; existing records stay until you clear them. The round in use on the keyboard (the versions on the result card) isn't affected.",
                       "オフにすると新しい記録はされません。既存の記録は残り、手動で消去できます。キーボードで使用中の回（結果カードの各版）には影響しません。"))
            }
            Section {
                ForEach(AIHistory.Retention.allCases) { option in
                    Button { store.retention = option } label: {
                        HStack {
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if store.retention == option {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(AppColor.purple)
                            }
                        }
                    }
                }
            } header: {
                Text(L("保留时间", "Keep For", "保存期間"))
            } footer: {
                Text(L("超过时间的自动删除。最多存 1,000 条，满了先删最早的。", "Older records are deleted automatically. Up to 1,000 records are kept; when full, the oldest go first.", "期間を過ぎた記録は自動で削除されます。最大 1,000 件で、いっぱいになると古いものから削除されます。"))
            }
            Section {
                Button { confirmsClear = true } label: {
                    Text(L("清空全部历史", "Clear All History", "履歴をすべて消去"))
                        .foregroundStyle(Color(hex: 0xFF3B30))
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(L("历史只存在这台 iPhone 上，不上传，也不会发给 AI 服务商。删除 App 会一起删掉。",
                       "History stays on this iPhone. It's never uploaded or sent to AI providers. Deleting the app deletes it too.",
                       "履歴はこの iPhone にだけ保存され、アップロードも AI サービスへの送信もされません。アプリを削除すると一緒に削除されます。"))
            }
        }
        .navigationTitle(L("历史记录设置", "History Settings", "履歴の設定"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("清空全部历史？", "Clear all history?", "履歴をすべて消去しますか？"), isPresented: $confirmsClear) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("清空", "Clear", "消去"), role: .destructive) { store.clear() }
        } message: {
            Text(L("这台 iPhone 上的润色和问答记录都会删除。", "All polish and Q&A records on this iPhone will be deleted.", "この iPhone の整える・質問の記録がすべて削除されます。"))
        }
    }
}
