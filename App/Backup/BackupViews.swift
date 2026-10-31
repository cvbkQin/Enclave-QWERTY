import SwiftUI
import UIKit
import UniformTypeIdentifiers

// 设置 › 数据 › 备份与恢复（B3 第一步，设计 design/backup/v2/BV0、BV2、BV3、BV4，design/backup/BK7）。

/// 设置主页「数据」分区里的那一行（BK1）。
struct BackupSettingsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemName: "archivebox", color: BackupView.green)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L("备份与恢复", "Backup & Restore", "バックアップと復元"))
                    NewBadge()
                }
                Text(L("换手机时带走设置、风格和词", "Take settings, styles and words to a new iPhone", "機種変更で設定・スタイル・語を引き継ぐ"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let date = BackupPrefs.lastExport {
                Text(date.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct BackupView: View {
    static let green = Color(hex: 0x2BB673)

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared

    @State private var items = BackupPrefs.items
    @State private var counts = BackupCounts.current()
    @State private var exporting = false
    @State private var picking = false
    @State private var opened: OpenedBackup?
    @State private var openError: String?
    @State private var lastExport = BackupPrefs.lastExport

    var body: some View {
        List {
            Section {
                fileCard
            } footer: {
                Text(L("换手机：旧手机「导出」存到 iCloud 云盘，新手机装好后点「恢复」选这个文件。",
                       "New iPhone: Export on the old one and save to iCloud Drive, then tap Restore on the new one and pick that file.",
                       "機種変更：古い iPhone で「書き出す」を iCloud Drive に保存し、新しい iPhone で「復元」からそのファイルを選びます。"))
            }
            Section {
                ForEach(BackupItem.allCases) { item in
                    Toggle(isOn: binding(item)) {
                        BackupItemLabel(item: item, value: countText(item))
                    }
                    .tint(DashColor.ok)
                }
            } header: {
                Text(L("备份内容 · 导出时按这里", "What's included · used when exporting", "バックアップする内容 · 書き出しに使います"))
            } footer: {
                Text(L("接口 Key 和剪贴板记录不会自动带上。导出文件时可以选择带上 Key，要设一个密码。",
                       "API keys and clipboard history aren't included automatically. When exporting you can add keys with a password.",
                       "API キーとクリップボード履歴は自動では含まれません。書き出すときにパスワード付きでキーを含められます。"))
            }
        }
        .navigationTitle(L("备份与恢复", "Backup & Restore", "バックアップと復元"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshLearned() }
        .onAppear { counts.polishStyles = store.settings.styles.count; counts.answerStyles = store.settings.answerStyles.count }
        .onChange(of: router.openedBackup) { _ in openPending() }
        .onAppear { openPending() }
        .sheet(isPresented: $exporting) {
            BackupExportSheet(items: items, counts: counts) { lastExport = BackupPrefs.lastExport }
        }
        .sheet(item: $opened) { box in
            BackupRestoreSheet(file: box.file) {
                counts = BackupCounts.current()
                Task { await refreshLearned() }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [BackupService.contentType, .data]) { result in
            guard case .success(let url) = result else { return }
            load(url, scoped: true)
        }
        .alert(L("打不开这个文件", "Can't open this file", "このファイルを開けません"),
               isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button(L("好", "OK", "OK"), role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }

    private var busy: Bool { deployer.state == .deploying }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "archivebox")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Self.green)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.green.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("本地备份文件", "Backup file", "バックアップファイル")).font(.headline)
                    Text(lastExportText).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            HStack(spacing: 10) {
                Button { exporting = true } label: {
                    Label(L("导出", "Export", "書き出す"), systemImage: "square.and.arrow.up")
                }
                Button { picking = true } label: {
                    Label(L("恢复", "Restore", "復元"), systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(BackupSoftButtonStyle())
            .disabled(busy)
            if busy {
                Text(L("拼音词库正在部署，完成后再导出或恢复。", "The pinyin dictionary is installing. Export or restore when it's done.", "ピンイン辞書をインストール中です。終わってから書き出しや復元をしてください。"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private var lastExportText: String {
        guard let date = lastExport else { return L("还没导出过", "Never exported", "まだ書き出していません") }
        let time = date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        let place = BackupPrefs.lastExportPlace.map { " · " + $0 } ?? ""
        return L("上次导出 ", "Last export ", "前回の書き出し ") + time + place
    }

    private func binding(_ item: BackupItem) -> Binding<Bool> {
        Binding {
            items.contains(item)
        } set: { on in
            if on { items.insert(item) } else { items.remove(item) }
            BackupPrefs.items = items
        }
    }

    private func countText(_ item: BackupItem) -> String? {
        switch item {
        case .settings: return nil
        case .styles: return "\(counts.polishStyles) · \(counts.answerStyles)"
        case .commonWords: return counts.commonWords.formatted()
        case .learnedWords: return counts.learnedWords.map { $0.formatted() } ?? "…"
        case .history: return counts.history.formatted()
        }
    }

    private func refreshLearned() async {
        let count = await Task.detached { LearnedWords.snapshot().map(BackupMerge.learnedCount) }.value
        counts.learnedWords = count ?? 0
    }

    /// 在「文件」或别的 App 里点开 .enclave，跳到这页直接弹恢复。
    private func openPending() {
        guard let url = router.openedBackup else { return }
        router.openedBackup = nil
        load(url, scoped: false, removeAfter: true)
    }

    private func load(_ url: URL, scoped: Bool, removeAfter: Bool = false) {
        Task {
            let result: Result<BackupFile, Error> = await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access { url.stopAccessingSecurityScopedResource() }
                    // 系统拷进 Documents/Inbox 的副本读完就删。
                    if removeAfter, url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                }
                do {
                    let data = try Data(contentsOf: url)
                    return .success(try BackupService.open(data, name: url.lastPathComponent))
                } catch let error as BackupError {
                    return .failure(error)
                } catch {
                    return .failure(BackupError.notBackup)
                }
            }.value
            switch result {
            case .success(let file):
                // 文件选择器刚收起，稍等再弹恢复面板。
                try? await Task.sleep(nanoseconds: 350_000_000)
                opened = OpenedBackup(file: file)
            case .failure(let error):
                openError = error.localizedDescription
            }
        }
    }
}

private struct OpenedBackup: Identifiable {
    let id = UUID()
    let file: BackupFile
}

/// 备份内容一行：标题、灰色说明，右边数量。
private struct BackupItemLabel: View {
    var item: BackupItem
    var value: String?
    var showDetail = true

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if showDetail, let detail = item.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
        }
    }
}

/// 浅紫底紫字的按钮（BV0 导出、恢复）。
struct BackupSoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppColor.purple.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.softFill.opacity(configuration.isPressed ? 0.6 : 1)))
            .contentShape(Rectangle())
    }
}

// MARK: - 导出（BV2、BV3）

struct BackupExportSheet: View {
    var items: Set<BackupItem>
    var counts: BackupCounts
    var onExported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var withKeys = false
    @State private var password = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var failure: String?

    private var keySummary: (count: Int, text: String) { BackupService.keySummary(settings: store.settings) }

    private var canExport: Bool {
        guard !working, !items.isEmpty || withKeys else { return false }
        return !withKeys || (!password.isEmpty && password == confirm)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("按「备份内容」导出", "Exports what's included", "「バックアップする内容」を書き出します"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(summary).font(.body)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Toggle(isOn: $withKeys.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("同时带上接口 Key", "Include API keys", "API キーも含める"))
                            Text(keyDetail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .tint(DashColor.ok)
                    .disabled(keySummary.count == 0)
                    if withKeys {
                        HStack(spacing: 12) {
                            TintIcon(systemName: "lock", color: AppColor.purple)
                            SecureField(L("设一个密码", "Set a password", "パスワードを設定"), text: $password)
                                .textContentType(.newPassword)
                        }
                        SecureField(L("再输一次密码", "Enter it again", "もう一度入力"), text: $confirm)
                            .textContentType(.newPassword)
                            .padding(.leading, 42)
                    }
                } footer: {
                    if withKeys {
                        VStack(alignment: .leading, spacing: 6) {
                            if !confirm.isEmpty, password != confirm {
                                Text(L("两次输入的密码不一样", "The passwords don't match", "パスワードが一致しません")).foregroundStyle(.red)
                            }
                            Label(L("密码忘了只是 Key 恢复不了，其他内容照常恢复。", "If you forget the password, only the keys can't be restored.", "パスワードを忘れても復元できないのはキーだけです。"),
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color(hex: 0xD97706))
                        }
                    }
                }
                Section {
                    Button {
                        export()
                    } label: {
                        if working {
                            HStack(spacing: 8) { ProgressView().tint(.white); Text(L("正在打包…", "Packing…", "まとめています…")) }
                        } else {
                            Text(L("导出", "Export", "書き出す"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canExport)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(failure ?? L("下一步选存到哪里，比如「存储到“文件”」› iCloud 云盘",
                                      "Next, choose where to save it, like Save to Files › iCloud Drive",
                                      "次に保存先を選びます（例：「\"ファイル\"に保存」› iCloud Drive）"))
                        .foregroundStyle(failure == nil ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .navigationTitle(L("导出备份", "Export Backup", "バックアップを書き出す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消", "Cancel", "キャンセル")) { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.66), .large])
    }

    private var summary: String {
        var parts: [String] = []
        for item in BackupItem.allCases where items.contains(item) {
            switch item {
            case .settings: parts.append(item.title)
            case .styles: parts.append(L("润色和问答风格 \(counts.styles) 条", "\(counts.styles) styles", "スタイル \(counts.styles) 件"))
            case .commonWords: parts.append(L("常用词 \(counts.commonWords)", "\(counts.commonWords) words", "ユーザ辞書 \(counts.commonWords)"))
            case .learnedWords:
                parts.append(item.title + (counts.learnedWords.map { " \($0.formatted())" } ?? ""))
            case .history: parts.append(L("AI 历史 \(counts.history) 条", "\(counts.history) history items", "AI 履歴 \(counts.history) 件"))
            }
        }
        return parts.isEmpty ? L("什么都没选", "Nothing selected", "何も選ばれていません") : parts.joined(separator: " · ")
    }

    private var keyDetail: String {
        let summary = keySummary
        guard summary.count > 0 else { return L("还没有填过 Key", "No keys yet", "キーはまだありません") }
        return summary.text + L("，要设一个密码", ". Needs a password", "。パスワードが必要です")
    }

    private func export() {
        working = true
        failure = nil
        let items = items, password = withKeys ? password : nil, origin = BackupService.Origin.current()
        Task {
            let result: Result<URL, Error> = await Task.detached {
                Result { try BackupService.export(items: items, keysPassword: password, origin: origin) }
            }.value
            working = false
            switch result {
            case .success(let url):
                ShareSheet.present(url) { activity in
                    try? FileManager.default.removeItem(at: url)
                    guard let activity else { return }
                    BackupPrefs.lastExport = Date()
                    BackupPrefs.lastExportPlace = ShareSheet.placeName(activity)
                    onExported()
                    dismiss()
                }
            case .failure(let error):
                failure = (error as? BackupError)?.localizedDescription
                    ?? L("没能导出：\(error.localizedDescription)", "Couldn't export: \(error.localizedDescription)", "書き出せませんでした：\(error.localizedDescription)")
            }
        }
    }
}

/// 系统分享面板：从最上层的页面弹出（导出面板本身是一张 sheet）。
enum ShareSheet {
    /// done：用户选了去处并完成时带上那个去处，取消时为 nil。
    @MainActor
    static func present(_ url: URL, done: @escaping (UIActivity.ActivityType?) -> Void) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            done(completed ? activity : nil)
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(controller, animated: true)
    }

    static func placeName(_ activity: UIActivity.ActivityType) -> String? {
        switch activity {
        case .airDrop: return L("隔空投送", "AirDrop", "AirDrop")
        case .mail: return L("邮件", "Mail", "メール")
        case .message: return L("信息", "Messages", "メッセージ")
        default:
            return activity.rawValue.contains("SaveToFiles") || activity.rawValue.contains("DocumentManager")
                ? L("文件", "Files", "ファイル") : nil
        }
    }
}

// MARK: - 恢复（BV4、BK7）

struct BackupRestoreSheet: View {
    let file: BackupFile
    var onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @State private var selected: Set<BackupItem> = []
    @State private var withKeys = false
    @State private var password = ""
    @State private var wrongPassword = false
    @State private var mode: BackupMerge.Mode = .merge
    @State private var confirmReplace = false
    @State private var working = false
    @State private var failure: String?
    @State private var report: BackupReport?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    BackupResultView(report: report)
                } else {
                    form
                }
            }
            .toolbar {
                if report == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("取消", "Cancel", "キャンセル")) { dismiss() }.disabled(working)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("完成", "Done", "完了")) { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(working)
        .onAppear { selected = Set(file.items) }
    }

    private var form: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "doc")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(BackupView.green)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BackupView.green.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        Text(L("来自 ", "From ", "") + file.manifest.device + " · " + file.manifest.exportedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                             + L("", "", " から"))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(file.items) { item in
                    Toggle(isOn: binding(item)) {
                        BackupItemLabel(item: item, value: value(item), showDetail: false)
                    }
                    .tint(DashColor.ok)
                }
                if file.keyCount > 0 {
                    Toggle(isOn: $withKeys.animation()) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("接口 Key", "API keys", "API キー"))
                                Text(L("要输入导出时设的密码", "Needs the password set when exporting", "書き出し時のパスワードが必要です"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("\(file.keyCount)").foregroundStyle(.secondary)
                        }
                    }
                    .tint(DashColor.ok)
                    if withKeys {
                        HStack(spacing: 12) {
                            TintIcon(systemName: "lock", color: AppColor.purple)
                            SecureField(L("备份密码", "Backup password", "バックアップのパスワード"), text: $password)
                                .textContentType(.password)
                                .onChange(of: password) { _ in wrongPassword = false }
                        }
                    }
                }
            } header: {
                Text(L("文件里有", "In this file", "このファイルの内容"))
            } footer: {
                if wrongPassword {
                    Text(L("密码不对，再试一次；不恢复 Key 就关掉这一项。", "Wrong password. Try again, or turn off API keys.", "パスワードが違います。もう一度入力するか、API キーをオフにしてください。"))
                        .foregroundStyle(.red)
                }
            }
            Section {
                Picker("", selection: $mode) {
                    Text(L("合并到现有的", "Merge", "今のデータに追加")).tag(BackupMerge.Mode.merge)
                    Text(L("替换现有的", "Replace", "今のデータを置き換え")).tag(BackupMerge.Mode.replace)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(mode == .merge
                     ? L("词和风格加进来，现有的都保留；设置用备份里的。", "Words and styles are added and nothing is removed. Settings come from the backup.", "語とスタイルを追加し、今のものは残します。設定はバックアップのものを使います。")
                     : L("选中的几项先清空再用备份里的。恢复前会自动留一份现在的数据。", "The selected items are cleared first. A copy of your current data is kept automatically.", "選んだ項目を消してからバックアップで置き換えます。今のデータは自動で控えを残します。"))
            }
            Section {
                Button {
                    if mode == .replace { confirmReplace = true } else { restore() }
                } label: {
                    if working {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text(L("正在恢复…", "Restoring…", "復元しています…")) }
                    } else {
                        Text(L("恢复", "Restore", "復元"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working || (selected.isEmpty && !withKeys) || (withKeys && password.isEmpty))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if let failure {
                    Text(failure).foregroundStyle(.red).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
                }
            }
        }
        .navigationTitle(L("从文件恢复", "Restore from File", "ファイルから復元"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("替换现有的？", "Replace current data?", "今のデータを置き換えますか？"), isPresented: $confirmReplace, titleVisibility: .visible) {
            Button(L("替换", "Replace", "置き換える"), role: .destructive) { restore() }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(L("选中的几项会先清空，再用备份里的。", "The selected items will be cleared, then filled from the backup.", "選んだ項目を消してから、バックアップの内容にします。"))
        }
    }

    private func binding(_ item: BackupItem) -> Binding<Bool> {
        Binding { selected.contains(item) } set: { on in
            if on { selected.insert(item) } else { selected.remove(item) }
        }
    }

    private func value(_ item: BackupItem) -> String? {
        item == .styles ? "\(file.polishStyles) · \(file.answerStyles)" : (item == .settings ? nil : file.count(item)?.formatted())
    }

    private func restore() {
        working = true
        failure = nil
        let file = file, items = selected, password = withKeys ? password : nil, mode = mode, origin = BackupService.Origin.current()
        Task {
            let result: Result<(BackupReport, BackupService.RestoredState), Error> = await Task.detached {
                Result { try BackupService.restore(file, items: items, keysPassword: password, mode: mode, origin: origin) }
            }.value
            working = false
            switch result {
            case .success(let (report, state)):
                apply(state)
                onRestored()
                withAnimation { self.report = report }
            case .failure(BackupError.wrongPassword):
                wrongPassword = true
            case .failure(let error):
                failure = (error as? BackupError)?.localizedDescription
                    ?? L("没能恢复：\(error.localizedDescription)", "Couldn't restore: \(error.localizedDescription)", "復元できませんでした：\(error.localizedDescription)")
            }
        }
    }

    /// App 这边内存里的设置、Key、界面语言跟着换；模糊拼音之类变了就重新部署词库。
    private func apply(_ state: BackupService.RestoredState) {
        if state.settingsChanged, let settings = state.settings {
            store.settings = settings
            if router.language != Loc.setting { router.language = Loc.setting }
        }
        if state.keysChanged {
            store.apiKey = SettingsStore.apiKey ?? ""
            store.answerApiKey = SettingsStore.answerApiKey ?? ""
        }
        RimeDeployer.shared.deployIfNeeded()
    }
}

/// 恢复完（BK7）。
private struct BackupResultView: View {
    let report: BackupReport

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white, BackupView.green)
                    Text(L("已恢复", "Restored", "復元しました")).font(.title2.bold())
                    Text(L("下次打开键盘时生效", "Takes effect next time the keyboard opens", "次にキーボードを開いたときに反映されます"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(report.rows) { row in
                    HStack {
                        Text(row.title)
                        Spacer(minLength: 8)
                        Text(row.value).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } footer: {
                if report.keysRestored == false {
                    Text(L("Key 没有恢复：去「AI › 接口」重新填，或用带 Key 的备份再恢复一次。",
                           "Keys weren't restored. Enter them again under AI › API, or restore again with the password.",
                           "キーは復元していません。「AI › API」で入力し直すか、パスワードを入れてもう一度復元してください。"))
                }
            }
        }
    }
}
