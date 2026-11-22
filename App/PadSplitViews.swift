import SwiftUI

// iPad 宽屏的两栏（PA2、PA3、PA4 ⑧）：左边列表、右边内容，和系统设置 App 一样。左栏竖屏 330 宽。
// 右边打开的页面内容照 iPhone，最宽 640（解锁页 560）居中。

// MARK: - 提示词（PA2 ③）

/// iPad 宽屏「提示词」标签：左边润色风格、问答风格列表（图钉、默认、本周次数，选中那一行紫底白字），右边直接是编辑页。
/// 右上「编辑」「＋」照旧，拖动排序就是 AI 栏的顺序。
struct PromptsSplitView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @State private var selection: Selection?
    /// 「＋」刚加的那条：什么都没填就换到别的，去掉它（NewPromptCleanup）。
    @State private var added: Selection?
    @State private var choosesNewKind = false
    /// 竖屏也两栏并排（PA4 ⑧），不把左栏收成浮层。
    @State private var columns: NavigationSplitViewVisibility = .all

    struct Selection: Hashable {
        let id: UUID
        let answer: Bool
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: PadWidth.sidebar, max: 380)
        } detail: {
            NavigationStack { detail }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(DashColor.ai)
        .onAppear(perform: selectDefault)
        .onChange(of: selection) { _ in dropAddedIfLeft() }
        .onChange(of: store.settings.styles.map(\.id)) { _ in keepSelectionValid() }
        .onChange(of: store.settings.answerStyles.map(\.id)) { _ in keepSelectionValid() }
        // enclave://prompts-answer：右边打开默认的问答风格。
        .onChange(of: router.promptKind) { kind in
            guard kind == .answer else { return }
            router.promptKind = .polish
            if let id = store.settings.selectedAnswerStyle?.id ?? store.settings.answerStyles.first?.id {
                selection = Selection(id: id, answer: true)
            }
        }
    }

    private var sidebar: some View {
        List {
            PromptListSections(answer: false, settings: $store.settings) { selection = Selection(id: $0, answer: false) }
            PromptListSections(answer: true, settings: $store.settings) { selection = Selection(id: $0, answer: true) }
            DeletedPresetsSection(settings: $store.settings)
        }
        .environment(\.selectedPromptID, selection?.id)
        .environment(\.padSplit, true)
        .pinnedTabTitle(caption: caption, title: L("提示词", "Prompts", "プロンプト")) {
            EmptyView()
        } trailing: {
            EditButton()
                .environment(\.locale, Loc.locale)
            Button { choosesNewKind = true } label: {
                Image(systemName: "plus").font(.title3)
            }
            .accessibilityLabel(L("添加", "Add", "追加"))
        }
        .navigationTitle(L("提示词", "Prompts", "プロンプト"))
        .tabRootPage()
        .confirmationDialog(L("添加哪一种？", "Add which kind?", "どちらを追加しますか？"), isPresented: $choosesNewKind, titleVisibility: .visible) {
            Button(L("润色风格", "Polish style", "整えるスタイル")) { add(answer: false) }
            Button(L("问答风格", "Answer style", "回答スタイル")) { add(answer: true) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection, let binding = styleBinding(selection) {
            Group {
                if selection.answer {
                    AnswerStyleEditor(style: binding, settings: $store.settings)
                } else {
                    StyleEditor(style: binding, settings: $store.settings)
                }
            }
            .id(selection)
            .padReadable()
        } else {
            SplitPlaceholder(systemImage: "text.quote", text: L("选左边的一个风格来编辑", "Choose a style on the left to edit", "左のスタイルを選んで編集"))
        }
    }

    /// 按 id 找，不按下标：编辑页里删掉这条后，旧的绑定不会越界。
    private func styleBinding(_ selection: Selection) -> Binding<StylePreset>? {
        let list = selection.answer ? store.settings.answerStyles : store.settings.styles
        guard let current = list.first(where: { $0.id == selection.id }) else { return nil }
        return Binding(get: {
            let list = selection.answer ? store.settings.answerStyles : store.settings.styles
            return list.first { $0.id == selection.id } ?? current
        }, set: { style in
            if selection.answer {
                if let index = store.settings.answerStyles.firstIndex(where: { $0.id == selection.id }) { store.settings.answerStyles[index] = style }
            } else {
                if let index = store.settings.styles.firstIndex(where: { $0.id == selection.id }) { store.settings.styles[index] = style }
            }
        })
    }

    private var caption: String {
        let count = store.settings.styles.count + store.settings.answerStyles.count
        let pinned = store.settings.pinnedStyles.count
        return L("\(count) 个风格 · \(pinned) 个固定在 AI 栏", "\(count) styles · \(pinned) pinned to the AI bar", "\(count) 個のスタイル・\(pinned) 個を AI バーに固定")
    }

    /// 一进来右边就有内容：默认的润色风格（和系统设置 App 一样总有一项选中）。
    private func selectDefault() {
        guard selection == nil else { return }
        if let id = store.settings.selectedStyle?.id ?? store.settings.styles.first?.id {
            selection = Selection(id: id, answer: false)
        }
    }

    private func keepSelectionValid() {
        guard let current = selection else { return }
        let list = current.answer ? store.settings.answerStyles : store.settings.styles
        if !list.contains(where: { $0.id == current.id }) {
            selection = nil
            selectDefault()
        }
    }

    private func add(answer: Bool) {
        let style = StylePreset(name: answer ? NewPromptCleanup.answerName : NewPromptCleanup.polishName, prompt: "")
        if answer { store.settings.answerStyles.append(style) } else { store.settings.styles.append(style) }
        let new = Selection(id: style.id, answer: answer)
        selection = new
        added = new
    }

    private func dropAddedIfLeft() {
        guard let added, added != selection else { return }
        self.added = nil
        NewPromptCleanup.dropIfBlank(added.id, answer: added.answer, settings: &store.settings)
    }
}

// MARK: - 历史（PA2 ④）

/// iPad 宽屏「历史」：左边列表（搜索、图例、按天分组，筛选在右上菜单），右边详情：你打的、每一版、用了哪版。
/// 历史记录设置也在右边打开。
struct HistorySplitView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = HistoryStore.shared
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            HistoryListView()
                .environment(\.padSplit, true)
                .navigationSplitViewColumnWidth(min: 300, ideal: PadWidth.sidebar, max: 400)
        } detail: {
            NavigationStack(path: $router.historyPath) {
                Group {
                    if let id = router.historySelection, store.entry(id) != nil {
                        HistoryDetailView(id: id).id(id)
                    } else {
                        SplitPlaceholder(systemImage: "clock", text: L("选左边的一条记录看详情", "Choose a record on the left", "左の記録を選んで詳細を表示"))
                    }
                }
                .padReadable()
                .navigationDestination(for: AppRouter.HistoryPage.self) { page in
                    Group {
                        switch page {
                        case .detail(let id): HistoryDetailView(id: id)
                        case .settings: HistorySettingsView()
                        }
                    }
                    .padReadable()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - 设置（PA3 ⑤）

/// iPad 宽屏「设置」：左边就是 iPhone 的设置列表（一行不少），右边打开选中的那一页；点 AI 卡片右边是解锁页。
/// 路径还是 router.settingsPath：第一项是左边选中的那一行，后面是右边往里推的页面。变窄时就是一列里的路径。
struct SettingsSplitView<Sidebar: View, Destination: View>: View {
    @EnvironmentObject private var router: AppRouter
    @ViewBuilder var sidebar: Sidebar
    let destination: (AppRouter.SettingsPage) -> Destination
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .environment(\.padSplit, true)
                .navigationSplitViewColumnWidth(min: 300, ideal: PadWidth.sidebar, max: 400)
        } detail: {
            NavigationStack(path: detailPath) {
                Group {
                    if let page = router.settingsPath.first {
                        destination(page).id(page)
                    } else {
                        // 没选时右边是 AI 卡片打开的那一页（内测版没有解锁，是首次设置）。
                        destination(BuiltinAPI.isInternalBuild ? .setup : .unlock)
                    }
                }
                .navigationDestination(for: AppRouter.SettingsPage.self) { destination($0) }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// 右边那一摞：settingsPath 去掉第一项（左边选中的那行）。
    private var detailPath: Binding<[AppRouter.SettingsPage]> {
        Binding(get: { Array(router.settingsPath.dropFirst()) }, set: { pages in
            let root = router.settingsPath.first ?? (BuiltinAPI.isInternalBuild ? .setup : .unlock)
            router.settingsPath = [root] + pages
        })
    }
}
