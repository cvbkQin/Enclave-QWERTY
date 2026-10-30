import StoreKit
import SwiftUI
import UniformTypeIdentifiers

// 键盘 › 词库 页的扩展词库（B6，效果图 design/ext-dict/EX1–EX8）：
// 「万象拼音」等卡片下面依次是「我的词库」「在线词库」「从文件导入」三组。

/// 词库页里的三组，放在 PinyinView 的 List 里。List 上还要加 .extDictImporter()（文件选择器、导入确认）。
struct ExtDictSections: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var store = ExtDictStore.shared
    @ObservedObject private var deployer = RimeDeployer.shared

    private var deploying: Bool { deployer.state == .deploying }

    var body: some View {
        myDicts
        online
        importSection
    }

    // MARK: - 我的词库（EX1、EX3、EX4）

    private var myDicts: some View {
        let rows = store.rows
        return Section {
            if deploying { deployBanner }
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
            Text(L("我的词库 · \(rows.count) 个，约 \(ExtDictStore.countText(store.enabledEntries)) 词",
                   "My dictionaries · \(rows.count), about \(ExtDictStore.countText(store.enabledEntries)) words",
                   "マイ辞書 · \(rows.count) 個、約 \(ExtDictStore.countText(store.enabledEntries)) 語"))
        } footer: {
            Text(deploying
                 ? L("部署中开关先变灰，部署完才能再改。", "Switches are grayed out while installing and come back when it's done.", "インストール中はスイッチを変更できません。終わると戻ります。")
                 : L("「内置」随 App 带着，「已下载」是从下面在线词库下的，「导入」是你自己的文件。都能开关和删除；关掉的不出候选。这些词排在基础词库后面，不抢常用词的首选。",
                     "Built-in ones come with the app, Downloaded ones are from the online list below, and Imported ones are your own files. You can turn any of them off or delete them; words from ones that are off don't appear. These words rank after the main dictionary, so your usual first choices stay first.",
                     "「内蔵」はアプリに付属、「ダウンロード済み」は下のオンライン辞書から、「インポート」はご自身のファイルです。どれもオン・オフや削除ができ、オフの辞書の語は候補に出ません。これらの語は基本辞書の後に並ぶので、よく使う語の第一候補は変わりません。"))
        }
    }

    /// 部署进度：编译没有真实进度，沿用万象部署那条按一分钟估的进度条。
    private var deployBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(deployer.startedAt ?? context.date)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("正在把新词加进键盘…", "Adding the new words to the keyboard…", "新しい語をキーボードに追加中…"))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(elapsed < 50 ? L("约 1 分钟", "About 1 min", "約 1 分") : L("快好了", "Almost done", "まもなく完了"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(elapsed / 60, 0.95)).tint(AppColor.purple)
                }
            }
            Text(L("可以离开这页，也可以先用键盘打字；部署完新词才会出现。", "You can leave this page or keep typing; the new words appear once it's done.", "このページを離れても、そのまま入力しても大丈夫です。新しい語は完了後に出ます。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 在线词库（EX1、EX2、EX4）

    private var online: some View {
        Section {
            ForEach(store.removedBuiltinPacks) { pack in
                OnlineRow(title: pack.name,
                          detail: [pack.category, ExtDictStore.entryText(ExtDict.builtinManifest[pack.id]?.entries ?? 0)].filter { !$0.isEmpty }.joined(separator: " · "),
                          license: L("内置词库 · 删掉后可以恢复", "Built in · can be restored", "内蔵辞書 · 削除後も戻せます")) {
                    CapsuleButton(title: L("恢复", "Restore", "戻す"), active: !deploying) { store.restore(pack.id) }
                }
            }
            ForEach(store.catalog.dicts) { item in
                OnlineRow(title: item.displayName, detail: onlineDetail(item), license: onlineLicense(item)) {
                    if let progress = store.downloads[item.id] {
                        DownloadRing(fraction: Double(progress.received) / Double(max(progress.expected, 1))) { store.cancelDownload(item.id) }
                    } else if store.isDownloaded(item.id) {
                        CapsuleButton(title: L("已下载", "Downloaded", "ダウンロード済み"), active: false) {}
                    } else if ExtDictCatalog.downloadURL(item) == nil {
                        CapsuleButton(title: L("准备中", "Coming soon", "準備中"), active: false) {}
                    } else {
                        CapsuleButton(title: L("下载", "Download", "ダウンロード"), active: true) { store.download(item) }
                    }
                }
            }
        } header: {
            Text(L("在线词库", "Online dictionaries", "オンライン辞書"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let progress = store.downloads.values.first {
                    Text(L("正在下载 \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB。可以离开这页，点圆圈里的方块取消。",
                           "Downloading \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB. You can leave this page; tap the square in the circle to cancel.",
                           "ダウンロード中 \(megabytes(progress.received)) / \(megabytes(progress.expected)) MB。このページを離れても大丈夫です。円の中の四角でキャンセルします。"))
                } else {
                    Text(L("在线词库只在你点「下载」时从开发者服务器下载，不上传任何内容。",
                           "Online dictionaries are downloaded from the developer's server only when you tap Download. Nothing is uploaded.",
                           "オンライン辞書は「ダウンロード」をタップしたときだけ開発者のサーバーからダウンロードします。何もアップロードしません。"))
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
        case .own: return L("飞地输入法整理", "Compiled by Enclave", "Enclave 編集")
        }
    }

    // MARK: - 从文件导入（EX6、EX7）

    private var importSection: some View {
        Section {
            Button { store.picking = true } label: {
                HStack(spacing: 12) {
                    TintIcon(systemName: "square.and.arrow.down", color: AppColor.purple, size: 36)
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
        } footer: {
            Text(L("列表里没有的（比如别的游戏、动漫），可以在网上找细胞词库（.scel）用这里导入。",
                   "For anything not listed (other games, anime…), find a cell dictionary (.scel) online and import it here.",
                   "一覧にないもの（ほかのゲームやアニメなど）は、ネットでセル辞書（.scel）を探してここから読み込めます。"))
        }
    }
}

/// 文件选择器、导入确认和失败卡；打开词库页时顺便拉一次在线词库清单。
/// 放在 List 上而不是各组上：修饰 Group 会给每一组各挂一份。
private struct ExtDictImporter: ViewModifier {
    @ObservedObject private var store = ExtDictStore.shared

    func body(content: Content) -> some View {
        content
            .task {
                #if DEBUG
                // 模拟器截图、测导入：-extDictImport /path/to/file.scel 直接弹出导入确认（或「没能导入」）。
                if let path = UserDefaults.standard.string(forKey: "extDictImport"), store.draft == nil, store.failedFile == nil {
                    let url = URL(fileURLWithPath: path)
                    if let parsed = ExtDictStore.readImport(url) { store.draft = parsed } else { store.failedFile = url.lastPathComponent }
                }
                #endif
                await store.refreshCatalog()
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

/// 「我的词库」一行：名称 + 小标签（+ 有更新），第二行灰字，右边开关和 ›。点文字进详情。
private struct ExtDictRow: View {
    let row: ExtDictStore.Row
    let disabled: Bool
    let open: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.system(size: 17)).lineLimit(1)
                    ExtDictBadge(kind: row.kind)
                    if row.hasUpdate { ExtDictBadge(text: L("有更新", "Update", "更新あり"), fill: AppColor.softFill, color: AppColor.purple) }
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
            let orange = Color(light: 0xB86200, dark: 0xFFB340)
            self.init(text: L("导入", "Imported", "インポート"), fill: orange.opacity(0.14), color: orange)
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
    let detail: String
    let license: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17))
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
            Text(L("在本机转换，文件不上传。导入后加进「我的词库」，重新部署约 1 分钟。",
                   "Converted on this iPhone; the file isn't uploaded. It's added to My dictionaries and installs in about a minute.",
                   "この iPhone 上で変換し、ファイルはアップロードしません。読み込むと「マイ辞書」に追加され、約 1 分でインストールします。"))
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
    @ObservedObject private var deployer = RimeDeployer.shared

    private var installed: ExtDict.Installed? { store.installed.first { $0.id == id } }
    private var builtin: ExtDict.Builtin? {
        installed == nil ? ExtDict.availableBuiltins.first { $0.id == id && !store.removedBuiltins.contains($0.id) } : nil
    }
    private var deploying: Bool { deployer.state == .deploying }

    var body: some View {
        List {
            if installed != nil || builtin != nil {
                Section {} header: { summaryCard.dashFormCard() }
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
                DashBigNumber(value: ExtDictStore.countText(ExtDict.builtinManifest[builtin.id]?.entries ?? 0),
                              unit: L("词 · 内置", "words · Built in", "語 · 内蔵"))
                Text(builtin.blurb).font(.system(size: 14)).foregroundStyle(.secondary)
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
        default:
            return L("飞地输入法整理，只收录名称文字，不含游戏 logo 或图片。", "Compiled by Enclave. Names only; no game logos or images.", "Enclave が編集。名前の文字だけで、ゲームのロゴや画像は含みません。")
        }
    }

    private var licenseURL: URL? {
        guard installed?.kind != .imported else { return nil }
        switch license {
        case .thuocl: return URL(string: "https://github.com/thunlp/THUOCL/blob/master/LICENSE")
        case .wiki: return URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")
        default: return nil
        }
    }

    private var deleteNote: String {
        switch installed?.kind {
        case .downloaded:
            return L("删除后要重新部署约 1 分钟，以后可以在「在线词库」里再下载。", "Deleting reinstalls the dictionary (about a minute). You can download it again from Online dictionaries.", "削除すると約 1 分で再インストールします。「オンライン辞書」からいつでもダウンロードし直せます。")
        case .imported:
            return L("删除后要重新部署约 1 分钟。要再用得重新导入文件。", "Deleting reinstalls the dictionary (about a minute). To use it again, import the file again.", "削除すると約 1 分で再インストールします。再び使うにはファイルを読み込み直してください。")
        default:
            return L("删除后要重新部署约 1 分钟。删掉的内置词库会出现在「在线词库」里，点「恢复」就能加回来。", "Deleting reinstalls the dictionary (about a minute). Deleted built-in dictionaries appear under Online dictionaries; tap Restore to add them back.", "削除すると約 1 分で再インストールします。削除した内蔵辞書は「オンライン辞書」に表示され、「戻す」で戻せます。")
        }
    }
}

/// 署名文字：详情页和「关于 › 开源许可」共用（05 许可结论）。
enum ExtDictAttribution {
    static var thuocl: String {
        L("来自 THUOCL 清华大学开放中文词库（github.com/thunlp/THUOCL），飞地输入法转换为 Rime 格式。\n\nCopyright (c) 2016 THUNLP。以 MIT 许可发布。",
          "From THUOCL, the Tsinghua Open Chinese Lexicon (github.com/thunlp/THUOCL), converted to Rime format by Enclave.\n\nCopyright (c) 2016 THUNLP. Released under the MIT License.",
          "THUOCL 清華大学オープン中国語辞書（github.com/thunlp/THUOCL）から、Enclave が Rime 形式に変換しました。\n\nCopyright (c) 2016 THUNLP。MIT ライセンスで公開。")
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
