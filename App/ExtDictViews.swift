import StoreKit
import SwiftUI
import UniformTypeIdentifiers

// 扩展词库（B6，效果图 design/ext-dict/EX1–EX13）。
// 键盘 › 词库 页的万象卡下面只放概况：「热门词库 ›」「导入的词库 ›」两行（EX9）。
// 热门词库页管内置和下载的（EX10、EX11），导入的词库页管导入的和「从文件导入」（EX12、EX13）。

/// 词库页里的「扩展词库」一组：两行概况，点进子页。放在 PinyinView 的 List 里。
struct ExtDictOverviewSection: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = ExtDictStore.shared
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        let hot = store.rows(.hot), imported = store.rows(.imported)
        let enabled = hot.filter(\.enabled).count + imported.filter(\.enabled).count
        Section {
            row(icon: "sparkles", color: AppColor.purple, title: L("热门词库", "Popular dictionaries", "人気の辞書"),
                subtitle: store.isDeploying(.hot) ? deployingText
                    : ExtDictStore.entryText(entries(hot)) + L(" · 游戏、流行语、百科词库等", " · games, slang, encyclopedia and more", " · ゲーム、流行語、百科辞書など"),
                value: L("已开 \(hot.filter(\.enabled).count) 个", "\(hot.filter(\.enabled).count) on", "\(hot.filter(\.enabled).count) 個オン")) {
                router.keyboardPath.append(AppRouter.ExtDictGroupPage.hot)
            }
            row(icon: "keyboard", color: ExtDictBadge.orange, title: L("导入的词库", "Imported dictionaries", "読み込んだ辞書"),
                subtitle: store.isDeploying(.imported) ? deployingText
                    : imported.isEmpty
                        ? L("细胞词库（.scel）、Rime 词库（.dict.yaml）", "Cell (.scel) and Rime (.dict.yaml) dictionaries", "セル辞書（.scel）、Rime 辞書（.dict.yaml）")
                        : ExtDictStore.entryText(entries(imported)) + L(" · 细胞词库、Rime 词库", " · cell and Rime dictionaries", " · セル辞書、Rime 辞書"),
                value: imported.isEmpty ? L("未导入", "None", "なし") : L("\(imported.count) 个", "\(imported.count)", "\(imported.count) 個")) {
                router.keyboardPath.append(AppRouter.ExtDictGroupPage.imported)
            }
        } header: {
            Text(L("扩展词库 · 已开 \(enabled) 个，约 ", "Extra dictionaries · \(enabled) on, about ", "拡張辞書 · \(enabled) 個オン、約 ")
                 + ExtDictStore.wordsText(store.enabledEntries))
        } footer: {
            Text(L("扩展词库的词排在基础词库后面，不抢常用词的首选。",
                   "Words from extra dictionaries rank after the main dictionary, so your usual first choices stay first.",
                   "拡張辞書の語は基本辞書の後に並ぶので、よく使う語の第一候補は変わりません。"))
        }
    }

    private var deployingText: String { L("部署中…", "Installing…", "インストール中…") }

    private func entries(_ rows: [ExtDictStore.Row]) -> Int { rows.reduce(0) { $0 + $1.entries } }

    private func row(icon: String, color: Color, title: String, subtitle: String, value: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                TintIcon(systemName: icon, color: color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(value).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 热门词库（EX10、EX11）

/// 最上面「自动更新了…」提示（有时）、「自动更新」一组（DU2，第 99 条）；
/// 「已装」：内置 + 已下载；下面「可以下载」：删掉的内置（恢复）+ 在线词库。一页滚动。
struct HotDictsView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = ExtDictStore.shared
    @ObservedObject private var deployer = RimeDeployer.shared
    @ObservedObject private var auto = DictAutoUpdate.shared
    /// 进这页时导航栈多深：离开时浅了才算真离开（进详情页不算），去掉提示、「刚更新」和「新」。
    @State private var depth: Int?

    private var deploying: Bool { deployer.state == .deploying }

    var body: some View {
        List {
            if let recent = auto.recent {
                Section { RecentUpdateBanner(recent: recent) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            autoUpdateSection
            installedSection
            downloadSection
        }
        .navigationTitle(L("热门词库", "Popular dictionaries", "人気の辞書"))
        .navigationBarTitleDisplayMode(.inline)
        // 打开这页照旧拉一次清单（开关关着也拉，用户自己打开的页面），显示「有更新」「新」。
        .task { await store.refreshCatalog() }
        .onAppear { if depth == nil { depth = router.keyboardPath.count } }
        .onDisappear {
            guard let depth, router.keyboardPath.count < depth else { return }
            auto.pageLeft(catalog: store.catalog.dicts.map(\.id))
        }
    }

    // MARK: 自动更新（DU2 ③⑤）

    private var autoUpdateSection: some View {
        Section {
            Toggle(isOn: $auto.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("自动更新词库", "Auto-Update Dictionaries", "辞書を自動更新")).font(.system(size: 17))
                    if auto.isConstrained && auto.enabled {
                        Text(L("低数据模式开着，先不自动下载", "Low Data Mode is on, so nothing downloads automatically", "省データモードのため自動ダウンロードしません"))
                            .font(.system(size: 13)).foregroundStyle(ExtDictBadge.orange)
                    } else {
                        Text(L("每 7 天检查一次，有新版就自动下载", "Checks every 7 days and downloads new versions", "7 日ごとに確認し、新しい版を自動でダウンロード"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.green)
            LastCheckRow()
        } header: {
            Text(L("自动更新", "Auto-Update", "自動更新"))
        } footer: {
            Text(auto.enabled
                 ? L("只更新你装着的词库，内置的也算；新词库不会自动装。更新完下次打开 App 自动装进键盘。低数据模式下不自动下载。",
                     "Only dictionaries you have are updated, built-in ones included; new dictionaries are never installed automatically. Updates go into the keyboard the next time you open the app. Nothing downloads automatically in Low Data Mode.",
                     "入っている辞書だけを更新します（内蔵も含む）。新しい辞書は自動では入りません。更新は次にアプリを開いたときにキーボードへ反映されます。省データモードでは自動ダウンロードしません。")
                 : L("关掉后不自动检查。有新版时那一行标「有更新」，点进去手动更新；也可以点「检查更新」。",
                     "Nothing is checked automatically. Dictionaries with a new version show Update; open one to update it, or tap Check Now.",
                     "自動では確認しません。新しい版がある辞書には「更新あり」が付くので、開いて手動で更新するか「今すぐ確認」をタップしてください。"))
        }
    }

    private var installedSection: some View {
        let rows = store.rows(.hot)
        let enabled = rows.filter(\.enabled).reduce(0) { $0 + $1.entries }
        return Section {
            if deploying { ExtDictDeployBanner() }
            ForEach(rows) { row in
                ExtDictRow(row: row, disabled: deploying, justUpdated: auto.recentIDs.contains(row.id)) {
                    router.keyboardPath.append(AppRouter.ExtDictPage(id: row.id))
                } toggle: { store.setEnabled(row.id, $0) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(L("删除", "Delete", "削除"), role: .destructive) { store.remove(row.id) }
                        .disabled(deploying)
                }
            }
        } header: {
            Text(L("已装 · \(rows.count) 个，约 ", "Installed · \(rows.count), about ", "インストール済み · \(rows.count) 個、約 ")
                 + ExtDictStore.wordsText(enabled))
        } footer: {
            Text(deploying
                 ? L("部署中开关先变灰，部署完才能再改。", "Switches are grayed out while installing and come back when it's done.", "インストール中はスイッチを変更できません。終わると戻ります。")
                 : L("「内置」随 App 带着，也会跟着服务器更新；「已下载」是从下面下的。都能开关和删除；关掉的不出候选。",
                     "Built-in ones come with the app and also update from the server; Downloaded ones are from the list below. You can turn any of them off or delete them; words from ones that are off don't appear.",
                     "「内蔵」はアプリに付属し、サーバーからも更新されます。「ダウンロード済み」は下の一覧からです。どれもオン・オフや削除ができ、オフの辞書の語は候補に出ません。"))
        }
    }

    private var downloadSection: some View {
        Section {
            ForEach(store.removedBuiltinPacks) { pack in
                OnlineRow(title: pack.name,
                          detail: [pack.category, ExtDictStore.entryText(store.builtinCopies[pack.id]?.entries ?? 0)].filter { !$0.isEmpty }.joined(separator: " · "),
                          license: L("内置词库 · 删掉后可以恢复", "Built in · can be restored", "内蔵辞書 · 削除後も戻せます")) {
                    CapsuleButton(title: L("恢复", "Restore", "戻す"), active: !deploying) { store.restore(pack.id) }
                }
            }
            let fresh = DictUpdatePolicy.newIDs(catalog: store.catalog.dicts.map(\.id), seen: auto.seenIDs)
            ForEach(store.catalog.dicts) { item in
                OnlineRow(title: item.displayName, isNew: fresh.contains(item.id) && !store.isDownloaded(item.id),
                          detail: onlineDetail(item), license: onlineLicense(item)) {
                    if let progress = store.downloads[item.id] {
                        DownloadRing(fraction: Double(progress.received) / Double(max(progress.expected, 1))) { store.cancelDownload(item.id) }
                    } else if store.isDownloaded(item.id) {
                        CapsuleButton(title: L("已下载", "Downloaded", "ダウンロード済み"), active: false) {}
                    } else if ExtDictCatalog.downloadURL(item) == nil {
                        // 不写「准备中 / Coming soon」：审核指南 2.3.1 不让写还没有的功能（05 上架风险报告低 4）。
                        // 服务器清单里都有地址，只有拉不到清单、用 App 自带的那份时才会走到这里。
                        CapsuleButton(title: L("暂时无法下载", "Unavailable", "現在ダウンロード不可"), active: false) {}
                    } else {
                        CapsuleButton(title: L("下载", "Download", "ダウンロード"), active: true) { store.download(item) }
                    }
                }
            }
        } header: {
            Text(L("可以下载", "Available to download", "ダウンロードできる辞書"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let progress = store.downloads.values.first {
                    Text(L("正在下载 \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB。可以离开这页，点圆圈里的方块取消。",
                           "Downloading \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB. You can leave this page; tap the square in the circle to cancel.",
                           "ダウンロード中 \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB。このページを離れても大丈夫です。円の中の四角でキャンセルします。"))
                } else {
                    Text(L("新词库只在你点「下载」时下载；装着的词库按上面的设置自动更新。不上传任何内容。列表里没有的，可以回到上一页「导入的词库」里从文件导入。",
                           "New dictionaries download only when you tap Download; the ones you have update automatically per the setting above. Nothing is uploaded. For anything not listed, go back and import a file under Imported dictionaries.",
                           "新しい辞書は「ダウンロード」をタップしたときだけダウンロードします。入っている辞書は上の設定に従って自動更新します。何もアップロードしません。一覧にないものは、前のページの「読み込んだ辞書」でファイルから読み込めます。"))
                }
                if let error = store.downloadError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000)
    }

    private func onlineDetail(_ item: ExtDictCatalog.Item) -> String {
        var parts = [ExtDictStore.entryText(item.entries), ExtDictStore.sizeText(item.size)]
        if item.license == .thuocl { parts.insert("THUOCL", at: 0) }
        if item.license == .wikidata { parts.insert("Wikidata", at: 0) }
        if let summary = item.summary { parts.append(summary.value) }
        return parts.joined(separator: " · ")
    }

    private func onlineLicense(_ item: ExtDictCatalog.Item) -> String {
        switch item.license {
        case .thuocl: return L("THUOCL 清华大学开放中文词库 · MIT", "THUOCL (Tsinghua University) · MIT", "THUOCL（清華大学）· MIT")
        case .wiki:
            return Storefront.isMainlandChina
                ? L("来自百科词条整理 · CC BY-SA 4.0 · 详情见许可", "From encyclopedia entries · CC BY-SA 4.0 · see license", "百科事典の項目から · CC BY-SA 4.0 · ライセンス参照")
                : "Wikipedia contributors · fcitx5-pinyin-zhwiki · CC BY-SA 4.0"
        case .wikidata: return L("名称来自 Wikidata · CC0 1.0", "Names from Wikidata · CC0 1.0", "名称は Wikidata から · CC0 1.0")
        case .own: return L("飞地输入法整理", "Compiled by Enclave", "Enclave 編集")
        }
    }
}

// MARK: - 自动更新的提示和「上次检查」（DU2）

/// 页面最上面一条浅绿提示：「11月26日自动更新了 医学、法律、网络流行语」，点开看每个词库多了多少词。
private struct RecentUpdateBanner: View {
    let recent: DictAutoUpdate.Recent
    @ObservedObject private var deployer = RimeDeployer.shared
    @State private var expanded = false

    private var installing: Bool { deployer.state == .deploying || deployer.needsDeploy }

    private var names: String {
        recent.items.map(\.name).joined(separator: L("、", ", ", "、"))
    }

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ExtDictBadge.greenText)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("\(Loc.monthDay(recent.date))自动更新了 \(names)", "Updated automatically on \(Loc.monthDay(recent.date)): \(names)", "\(Loc.monthDay(recent.date))に自動更新：\(names)"))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if expanded {
                        ForEach(recent.items) { item in
                            HStack {
                                Text(item.name + (item.builtin ? L("（内置）", " (built in)", "（内蔵）") : "") + " · " + ExtDictStore.versionText(item.version))
                                    .font(.system(size: 14)).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if item.added != 0 {
                                    Text((item.added > 0 ? "+" : "−") + L("\(abs(item.added).formatted()) 词", "\(abs(item.added).formatted()) words", "\(abs(item.added).formatted()) 語"))
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(ExtDictBadge.greenText)
                                }
                            }
                        }
                        Text(installing
                             ? L("正在装进键盘…离开这页后不再显示。", "Installing into the keyboard… This goes away when you leave the page.", "キーボードに追加中…このページを離れると消えます。")
                             : L("已经装进键盘。离开这页后不再显示。", "Already in the keyboard. This goes away when you leave the page.", "キーボードに追加済みです。このページを離れると消えます。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        Text(installing
                             ? L("正在装进键盘…", "Installing into the keyboard…", "キーボードに追加中…")
                             : L("已经装进键盘 · 点开看多了哪些词", "Already in the keyboard · tap to see what's new", "キーボードに追加済み · タップで追加された語を表示"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ExtDictBadge.green.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ExtDictBadge.green.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? L("收起", "Collapse", "閉じる") : L("展开看每个词库多了多少词", "Shows how many words each one gained", "辞書ごとの追加語数を表示"))
    }
}

/// 「上次检查」一行：平时「3 天前」+「检查更新」；检查中转圈；没有新版绿勾 3 秒；有新版写几个和进度圈；失败橙字两行 +「重试」。
private struct LastCheckRow: View {
    @ObservedObject private var auto = DictAutoUpdate.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(L("上次检查", "Last checked", "前回の確認")).font(.system(size: 17))
            Spacer(minLength: 8)
            switch auto.status {
            case .idle:
                Text(auto.lastCheck.map(Self.ago) ?? L("还没查过", "Never", "未確認"))
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                checkButton(L("检查更新", "Check Now", "今すぐ確認"))
            case .checking:
                ProgressView().controlSize(.small)
                Text(L("正在检查…", "Checking…", "確認中…")).font(.system(size: 15)).foregroundStyle(.secondary)
            case .upToDate:
                Label(L("刚刚 · 已是最新", "Just now · Up to date", "たった今 · 最新です"), systemImage: "checkmark")
                    .font(.system(size: 15)).foregroundStyle(ExtDictBadge.greenText)
            case .downloading(let count, let done):
                Text(L("发现 \(count) 个更新，正在下载", "Downloading \(count) updates", "\(count) 件の更新をダウンロード中"))
                    .font(.system(size: 15)).foregroundStyle(AppColor.purple)
                ZStack {
                    Circle().stroke(AppColor.softFill, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.08, Double(done) / Double(max(count, 1))))
                        .stroke(AppColor.purple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
            case .failed:
                VStack(alignment: .trailing, spacing: 1) {
                    Text(L("没连上服务器", "Couldn't reach the server", "サーバーに接続できません"))
                    Text(L("明天再自动试", "Will try again tomorrow", "明日もう一度試します"))
                }
                .font(.system(size: 13)).foregroundStyle(ExtDictBadge.orange)
                checkButton(L("重试", "Retry", "再試行"))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func checkButton(_ title: String) -> some View {
        Button(title) { auto.checkNow() }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColor.purple)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(AppColor.softFill))
            .buttonStyle(.borderless)
            .fixedSize()
    }

    /// 「刚刚」「5 分钟前」「3 小时前」「3 天前」。
    static func ago(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return L("刚刚", "Just now", "たった今") }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            return L("\(m) 分钟前", "\(m) min ago", "\(m) 分前")
        }
        if seconds < 86400 {
            let h = Int(seconds / 3600)
            return L("\(h) 小时前", "\(h) h ago", "\(h) 時間前")
        }
        let d = Int(seconds / 86400)
        return L("\(d) 天前", d == 1 ? "1 day ago" : "\(d) days ago", "\(d) 日前")
    }
}

// MARK: - 导入的词库（EX12、EX13）

/// 上面「已导入」列表（没导入过换成一段说明），下面「从文件导入」。文件选择器和导入确认挂在这一页。
struct ImportedDictsView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = ExtDictStore.shared
    @ObservedObject private var deployer = RimeDeployer.shared

    private var deploying: Bool { deployer.state == .deploying }

    var body: some View {
        let rows = store.rows(.imported)
        List {
            if rows.isEmpty {
                Section {} header: { emptyNote }
            } else {
                Section {
                    if deploying { ExtDictDeployBanner() }
                    ForEach(rows) { row in
                        ExtDictRow(row: row, disabled: deploying) {
                            router.keyboardPath.append(AppRouter.ExtDictPage(id: row.id))
                        } toggle: { store.setEnabled(row.id, $0) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(L("删除", "Delete", "削除"), role: .destructive) { store.remove(row.id) }
                                .disabled(deploying)
                        }
                    }
                } header: {
                    Text(L("已导入 · \(rows.count) 个，约 ", "Imported · \(rows.count), about ", "読み込み済み · \(rows.count) 個、約 ")
                         + ExtDictStore.wordsText(rows.reduce(0) { $0 + $1.entries }))
                } footer: {
                    Text(deploying
                         ? L("部署中开关先变灰，部署完才能再改。", "Switches are grayed out while installing and come back when it's done.", "インストール中はスイッチを変更できません。終わると戻ります。")
                         : L("点一行看详情、改名或删除；左滑也能删除。", "Tap one to see details, rename or delete it. You can also swipe left to delete.", "タップで詳細・名前の変更・削除。左にスワイプしても削除できます。"))
                }
            }
            Section {
                importRow
            } footer: {
                if !rows.isEmpty {
                    Text(L("列表里没有的（比如别的游戏、动漫），可以在网上找细胞词库（.scel）用这里导入。",
                           "For anything not listed (other games, anime…), find a cell dictionary (.scel) online and import it here.",
                           "一覧にないもの（ほかのゲームやアニメなど）は、ネットでセル辞書（.scel）を探してここから読み込めます。"))
                }
            }
        }
        .extDictImporter()
        .navigationTitle(L("导入的词库", "Imported dictionaries", "読み込んだ辞書"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 没导入过：居中一段说明（EX13）。
    private var emptyNote: some View {
        VStack(spacing: 10) {
            Text(L("还没有导入词库", "No imported dictionaries yet", "読み込んだ辞書はまだありません"))
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
            Text(L("可以在网上找细胞词库（.scel）或 Rime 词库（.dict.yaml），在这里导入，比如别的游戏、动漫、专业名词。",
                   "Find a cell dictionary (.scel) or Rime dictionary (.dict.yaml) online and import it here, for other games, anime or specialist terms.",
                   "ネットでセル辞書（.scel）や Rime 辞書（.dict.yaml）を探して、ここから読み込めます。ほかのゲーム、アニメ、専門用語など。"))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 16)
        .padding(.horizontal, 12)
    }

    private var importRow: some View {
        Button { store.picking = true } label: {
            HStack(spacing: 12) {
                TintIcon(systemName: "keyboard", color: AppColor.purple, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("从文件导入", "Import from file", "ファイルから読み込む")).font(.system(size: 17)).foregroundStyle(AppColor.purple)
                    Text(L("支持细胞词库（.scel）和 Rime 词库（.dict.yaml），在本机转换，不上传",
                           "Cell dictionaries (.scel) and Rime dictionaries (.dict.yaml). Converted on this iPhone; nothing is uploaded.",
                           "セル辞書（.scel）と Rime 辞書（.dict.yaml）に対応。この iPhone 上で変換し、アップロードしません。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(deploying)
    }
}

/// 部署进度：放在「已装」或「已导入」组顶上。编译没有真实进度，按上次实际用的时间估（没部署过按一分钟）。
private struct ExtDictDeployBanner: View {
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(deployer.startedAt ?? context.date)
                let expected = RimeDeployer.expectedSeconds
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("正在把新词加进键盘…", "Adding the new words to the keyboard…", "新しい語をキーボードに追加中…"))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(elapsed < expected - 5 ? L("还要", "", "残り") + RimeDeployer.durationText(expected - elapsed) : L("快好了", "Almost done", "まもなく完了"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(elapsed / expected, 0.95)).tint(AppColor.purple)
                }
            }
            Text(L("可以离开这页，也可以先用键盘打字；部署完新词才会出现。", "You can leave this page or keep typing; the new words appear once it's done.", "このページを離れても、そのまま入力しても大丈夫です。新しい語は完了後に出ます。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// 文件选择器、导入确认和失败卡，挂在导入的词库页的 List 上。
private struct ExtDictImporter: ViewModifier {
    @ObservedObject private var store = ExtDictStore.shared
    #if DEBUG
    private static var debugImportShown = false
    #endif

    func body(content: Content) -> some View {
        content
            .task {
                #if DEBUG
                // 模拟器截图、测导入：-extDictImport /path/to/file.scel 直接弹出导入确认（或「没能导入」）。
                // 每次启动只弹一次：从详情页返回时这页又出现，不再弹。
                if !Self.debugImportShown, let path = UserDefaults.standard.string(forKey: "extDictImport"), store.draft == nil, store.failedFile == nil {
                    Self.debugImportShown = true
                    let url = URL(fileURLWithPath: path)
                    if let parsed = ExtDictStore.readImport(url) { store.draft = parsed } else { store.failedFile = url.lastPathComponent }
                }
                #endif
            }
            .fileImporter(isPresented: $store.picking, allowedContentTypes: [.item]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    let parsed = await Task.detached { ExtDictStore.readImport(url) }.value
                    if let parsed { store.draft = parsed } else { store.failedFile = url.lastPathComponent }
                }
            }
            .sheet(item: $store.draft) { draft in
                ImportConfirmSheet(draft: draft) { store.draft = nil }
            }
            .sheet(isPresented: Binding(get: { store.failedFile != nil }, set: { if !$0 { store.failedFile = nil } })) {
                ImportFailedSheet(fileName: store.failedFile ?? "") {
                    store.failedFile = nil
                } retry: {
                    store.failedFile = nil
                    // 等这张卡收起再弹文件选择器。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.picking = true }
                }
            }
    }
}

extension View {
    func extDictImporter() -> some View { modifier(ExtDictImporter()) }
}

// MARK: - 行和小部件

/// 热门词库、导入的词库里的一行：名称 + 小标签（+ 有更新），第二行灰字，右边开关和 ›。点文字进详情。
private struct ExtDictRow: View {
    let row: ExtDictStore.Row
    let disabled: Bool
    /// 自动更新刚换过（绿色「刚更新」，离开热门词库页后去掉）。
    var justUpdated = false
    let open: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.system(size: 17)).lineLimit(1)
                    ExtDictBadge(kind: row.kind)
                    if justUpdated {
                        ExtDictBadge(text: L("刚更新", "Updated", "更新済み"), fill: ExtDictBadge.green.opacity(0.15), color: ExtDictBadge.greenText)
                    } else if row.hasUpdate {
                        ExtDictBadge(text: L("有更新", "Update", "更新あり"), fill: AppColor.softFill, color: AppColor.purple)
                    }
                }
                Text(row.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            Toggle("", isOn: Binding(get: { row.enabled }, set: toggle))
                .labelsHidden()
                .disabled(disabled)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                .onTapGesture(perform: open)
        }
        .padding(.vertical, 2)
    }
}

/// 小标签：内置灰底灰字，已下载浅紫底紫字，导入浅橙底橙字。高 18、圆角 9、字 11 半粗。
struct ExtDictBadge: View {
    /// 导入的橙色：标签字、词库页「导入的词库」图标。
    static let orange = Color(light: 0xB86200, dark: 0xFFB340)
    /// 「刚更新」、自动更新提示：#34C759 底，字 #248A3D（深色 #30D158）。
    static let green = Color(hex: 0x34C759)
    static let greenText = Color(light: 0x248A3D, dark: 0x30D158)

    var text: String
    var fill: Color
    var color: Color

    init(text: String, fill: Color, color: Color) {
        self.text = text
        self.fill = fill
        self.color = color
    }

    init(kind: ExtDict.Kind) {
        switch kind {
        case .builtin:
            self.init(text: L("内置", "Built in", "内蔵"), fill: Color(.systemGray5), color: .secondary)
        case .downloaded:
            self.init(text: L("已下载", "Downloaded", "ダウンロード済み"), fill: AppColor.softFill, color: AppColor.purple)
        case .imported:
            self.init(text: L("导入", "Imported", "インポート"), fill: Self.orange.opacity(0.14), color: Self.orange)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(fill))
            .fixedSize()
    }
}

/// 「在线词库」一行：名称；词条数 · 大小 · 内容；许可。右边按钮。
private struct OnlineRow<Trailing: View>: View {
    let title: String
    /// 服务器上新加的、这页还没看过（DU2 ④）。
    var isNew = false
    let detail: String
    let license: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 17))
                    if isNew { NewBadge() }
                }
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(license).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 2)
    }
}

/// 「下载」浅紫胶囊；不可点时（已下载、准备中）灰胶囊。
private struct CapsuleButton: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? AppColor.purple : .secondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(active ? AppColor.softFill : Color(.systemGray5)))
        }
        .buttonStyle(.borderless)
        .disabled(!active)
        .fixedSize()
    }
}

/// 下载中：进度圈，中间方块点了取消（和整句模型下载同一种写法）。
private struct DownloadRing: View {
    let fraction: Double
    let cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            ZStack {
                Circle().stroke(AppColor.softFill, lineWidth: 3)
                Circle().trim(from: 0, to: max(0.03, min(fraction, 1)))
                    .stroke(AppColor.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: 2).fill(AppColor.purple).frame(width: 9, height: 9)
            }
            .frame(width: 28, height: 28)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("取消下载", "Cancel download", "ダウンロードをキャンセル"))
    }
}

// MARK: - 导入确认、失败（EX6、EX7）

private struct ImportConfirmSheet: View {
    @State var draft: ExtDictStore.ImportDraft
    let done: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text(L("导入词库", "Import dictionary", "辞書を読み込む")).font(.system(size: 20, weight: .bold)).padding(.top, 22)
            Text("\(draft.fileName) · \(draft.format) · \(ExtDictStore.sizeText(draft.fileSize))")
                .font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            VStack(alignment: .leading, spacing: 6) {
                DashBigNumber(value: draft.entries.count.formatted(), unit: L("个词", "words", "語"), size: 30)
                Text(draft.entries.prefix(4).map(\.word).joined(separator: "、") + (draft.entries.count > 4 ? "…" : ""))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            VStack(alignment: .leading, spacing: 6) {
                Text(L("名称", "Name", "名前")).font(.system(size: 13)).foregroundStyle(.secondary)
                TextField(L("名称", "Name", "名前"), text: $draft.name)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            HStack(spacing: 12) {
                Button(L("取消", "Cancel", "キャンセル"), action: done).buttonStyle(SoftButtonStyle())
                Button(L("导入", "Import", "読み込む")) {
                    do {
                        try ExtDictStore.shared.commitImport(draft)
                        done()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Text(L("在本机转换，文件不上传。导入后加进「导入的词库」，重新部署\(RimeDeployer.durationText)。",
                   "Converted on this iPhone; the file isn't uploaded. It's added to Imported dictionaries and installs in \(RimeDeployer.durationText).",
                   "この iPhone 上で変換し、ファイルはアップロードしません。読み込むと「読み込んだ辞書」に追加され、\(RimeDeployer.durationText)でインストールします。"))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
    }
}

private struct ImportFailedSheet: View {
    let fileName: String
    let dismiss: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(L("没能导入", "Couldn't import", "読み込めませんでした")).font(.system(size: 20, weight: .bold)).padding(.top, 22)
            Text(L("「\(fileName)」不是细胞词库（.scel）或 Rime 词库（.dict.yaml），或者里面没有带拼音的词。请换一个文件再试。",
                   "\"\(fileName)\" isn't a cell dictionary (.scel) or Rime dictionary (.dict.yaml), or it has no words with pinyin. Please try another file.",
                   "「\(fileName)」はセル辞書（.scel）や Rime 辞書（.dict.yaml）ではないか、ピンイン付きの語がありません。別のファイルでお試しください。"))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button(L("好的", "OK", "OK"), action: dismiss).buttonStyle(SoftButtonStyle())
                Button(L("重新选择文件", "Choose another file", "別のファイルを選ぶ"), action: retry).buttonStyle(PrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(260)])
    }
}

/// 浅紫底紫字的次按钮，和 PrimaryButtonStyle 一样高。
private struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppColor.purple)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.softFill.opacity(configuration.isPressed ? 0.6 : 1)))
    }
}

// MARK: - 详情（EX5、EX8）

struct ExtDictDetailView: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ExtDictStore.shared
    @ObservedObject private var auto = DictAutoUpdate.shared
    @ObservedObject private var deployer = RimeDeployer.shared

    private var installed: ExtDict.Installed? { store.installed.first { $0.id == id } }
    private var builtin: ExtDict.Builtin? {
        installed == nil ? ExtDict.availableBuiltins.first { $0.id == id && !store.removedBuiltins.contains($0.id) } : nil
    }
    private var deploying: Bool { deployer.state == .deploying }
    /// 导入的词库可以改名（导入的词库页脚注「点一行看详情、改名或删除」）。
    @State private var name = ""

    var body: some View {
        List {
            if installed != nil || builtin != nil {
                Section {} header: { summaryCard.dashFormCard() }
                if let installed, installed.kind == .imported {
                    Section(L("名称", "Name", "名前")) {
                        TextField(installed.name, text: $name)
                            .submitLabel(.done)
                            .onSubmit { store.rename(id, to: name) }
                    }
                }
                Section {
                    Toggle(L("使用这个词库", "Use this dictionary", "この辞書を使う"),
                           isOn: Binding(get: { !store.off.contains(id) }, set: { store.setEnabled(id, $0) }))
                        .disabled(deploying)
                }
                Section(L("来源和许可", "Source and license", "出典とライセンス")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(attribution).font(.system(size: 15)).foregroundStyle(.secondary)
                        if let url = licenseURL {
                            Link(destination: url) {
                                Text(L("查看许可 ›", "View license ›", "ライセンスを見る ›")).font(.system(size: 15))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button(role: .destructive) {
                        store.remove(id)
                        dismiss()
                    } label: {
                        Text(L("删除这个词库", "Delete this dictionary", "この辞書を削除")).frame(maxWidth: .infinity)
                    }
                    .disabled(deploying)
                } footer: {
                    Text(deleteNote)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let installed { name = installed.name } }
        // 改了名没按完成就返回，也存下来。
        .onDisappear { store.rename(id, to: name) }
    }

    private var title: String {
        if let installed { return store.displayName(installed) }
        return builtin?.name ?? ""
    }

    private var summaryCard: some View {
        DashCard {
            if let installed {
                DashBigNumber(value: ExtDictStore.countText(installed.entries),
                              unit: L("词 · ", "words · ", "語 · ") + ExtDictStore.sizeText(installed.size))
                if installed.kind == .downloaded {
                    let update = store.update(for: installed)
                    Text(downloadedNote(installed, update: update)).font(.system(size: 14)).foregroundStyle(.secondary)
                    if let update {
                        Button(L("更新到 \(ExtDictStore.versionText(update.version))", "Update to \(ExtDictStore.versionText(update.version))", "\(ExtDictStore.versionText(update.version))に更新")) {
                            store.download(update)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(deploying || store.downloads[id] != nil)
                    }
                } else if let date = ISO8601DateFormatter().date(from: installed.version) {
                    Text(L("\(Loc.monthDay(date)) 导入", "Imported \(Loc.monthDay(date))", "\(Loc.monthDay(date))に読み込み"))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
            } else if let builtin {
                let copy = store.builtinCopies[builtin.id]
                DashBigNumber(value: ExtDictStore.countText(copy?.entries ?? 0),
                              unit: L("词 · 内置", "words · Built in", "語 · 内蔵"))
                Text(builtin.blurb + (copy.map { " " + ExtDictStore.versionText($0.version) + L("。", ".", "。") } ?? ""))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                // 自动更新关着时，内置词库有新版在这里手动更新（DU2 ③）。
                if let update = store.builtinUpdate(for: builtin.id) {
                    Button(L("更新到 \(ExtDictStore.versionText(update.version))", "Update to \(ExtDictStore.versionText(update.version))", "\(ExtDictStore.versionText(update.version))に更新")) {
                        DictAutoUpdate.shared.checkNow()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(deploying || auto.status != .idle)
                }
            }
        }
    }

    private func downloadedNote(_ item: ExtDict.Installed, update: ExtDictCatalog.Item?) -> String {
        var text = L("已下载 ", "Downloaded ", "ダウンロード済み ") + ExtDictStore.versionText(item.version)
        if let update {
            let delta = update.entries - item.entries
            let more = delta > 0 ? L("（+\(delta.formatted()) 词）", " (+\(delta.formatted()) words)", "（+\(delta.formatted()) 語）") : ""
            text += L(" · 有新版 ", " · New: ", " · 新しい版 ") + ExtDictStore.versionText(update.version) + more
        }
        return text
    }

    private var license: ExtDict.License? { installed?.license ?? builtin?.license }

    private var attribution: String {
        if let installed, installed.kind == .imported {
            return L("你导入的文件 · \(installed.fileName ?? "")。只在本机使用，不上传。", "Your imported file · \(installed.fileName ?? ""). Used only on this iPhone; never uploaded.", "読み込んだファイル · \(installed.fileName ?? "")。この iPhone 内だけで使い、アップロードしません。")
        }
        switch license {
        case .thuocl: return ExtDictAttribution.thuocl
        case .wiki: return ExtDictAttribution.wiki
        case .wikidata: return ExtDictAttribution.wikidata
        default:
            return L("飞地输入法整理，只收录名称文字，不含游戏 logo 或图片。", "Compiled by Enclave. Names only; no game logos or images.", "Enclave が編集。名前の文字だけで、ゲームのロゴや画像は含みません。")
        }
    }

    private var licenseURL: URL? {
        guard installed?.kind != .imported else { return nil }
        switch license {
        case .thuocl: return URL(string: "https://github.com/thunlp/THUOCL/blob/master/LICENSE")
        case .wiki: return URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")
        case .wikidata: return URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")
        default: return nil
        }
    }

    private var deleteNote: String {
        let d = RimeDeployer.durationText
        switch installed?.kind {
        case .downloaded:
            return L("删除后要重新部署，\(d)，以后可以在「热门词库」里再下载。", "Deleting reinstalls the dictionary (\(d)). You can download it again from Popular dictionaries.", "削除すると再インストールします（\(d)）。「人気の辞書」からいつでもダウンロードし直せます。")
        case .imported:
            return L("删除后要重新部署，\(d)。要再用得重新导入文件。", "Deleting reinstalls the dictionary (\(d)). To use it again, import the file again.", "削除すると再インストールします（\(d)）。再び使うにはファイルを読み込み直してください。")
        default:
            return L("删除后要重新部署，\(d)。删掉的内置词库会出现在「热门词库」的「可以下载」里，点「恢复」就能加回来。", "Deleting reinstalls the dictionary (\(d)). Deleted built-in dictionaries appear under Available to download in Popular dictionaries; tap Restore to add them back.", "削除すると再インストールします（\(d)）。削除した内蔵辞書は「人気の辞書」の「ダウンロードできる辞書」に表示され、「戻す」で戻せます。")
        }
    }
}

/// 署名文字：详情页和「关于 › 开源许可」共用（05 许可结论）。
enum ExtDictAttribution {
    /// T106，05 定的写法（compliance/词库-Wikidata/许可和审核要求.md）。
    static var wikidata: String {
        L("景点、机场、地标和名人词库：词条名称来自 Wikidata（wikidata.org），按 CC0 1.0 公有领域贡献使用。拼音标注、筛选和整理由飞地输入法完成。",
          "Places, airports, landmarks and people dictionaries: entry names from Wikidata (wikidata.org), used under CC0 1.0. Pinyin, filtering and curation by Enclave.",
          "観光地・空港・ランドマーク・人名辞書：項目名は Wikidata（wikidata.org）から CC0 1.0 のもとで使用しています。ピンインの付与、選別、整理は Enclave が行っています。")
    }

    static var thuocl: String {
        L("来自 THUOCL 清华大学开放中文词库（github.com/thunlp/THUOCL），飞地输入法转换为 Rime 格式。\n\nCopyright (c) 2018 THUNLP。以 MIT 许可发布。",
          "From THUOCL, the Tsinghua Open Chinese Lexicon (github.com/thunlp/THUOCL), converted to Rime format by Enclave.\n\nCopyright (c) 2018 THUNLP. Released under the MIT License.",
          "THUOCL 清華大学オープン中国語辞書（github.com/thunlp/THUOCL）から、Enclave が Rime 形式に変換しました。\n\nCopyright (c) 2018 THUNLP。MIT ライセンスで公開。")
    }

    static var wiki: String {
        Storefront.isMainlandChina
            ? L("词条来自中文百科各位贡献者，由 fcitx5-pinyin-zhwiki 项目（github.com/felixonmars/fcitx5-pinyin-zhwiki）整理，飞地输入法转换为 Rime 格式并做了筛选。以 CC BY-SA 4.0 许可发布。",
                "Entries by encyclopedia contributors, compiled by fcitx5-pinyin-zhwiki (github.com/felixonmars/fcitx5-pinyin-zhwiki); converted to Rime format and filtered by Enclave. Released under CC BY-SA 4.0.",
                "百科事典の寄稿者による項目を fcitx5-pinyin-zhwiki（github.com/felixonmars/fcitx5-pinyin-zhwiki）がまとめ、Enclave が Rime 形式に変換して絞り込みました。CC BY-SA 4.0 で公開。")
            : L("词条来自维基百科贡献者（Wikipedia contributors），由 fcitx5-pinyin-zhwiki 项目（github.com/felixonmars/fcitx5-pinyin-zhwiki）整理，飞地输入法转换为 Rime 格式并做了筛选。以 CC BY-SA 4.0 许可发布。",
                "Entries by Wikipedia contributors, compiled by fcitx5-pinyin-zhwiki (github.com/felixonmars/fcitx5-pinyin-zhwiki); converted to Rime format and filtered by Enclave. Released under CC BY-SA 4.0.",
                "ウィキペディアの寄稿者（Wikipedia contributors）による項目を fcitx5-pinyin-zhwiki（github.com/felixonmars/fcitx5-pinyin-zhwiki）がまとめ、Enclave が Rime 形式に変換して絞り込みました。CC BY-SA 4.0 で公開。")
    }
}
