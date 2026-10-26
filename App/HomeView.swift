import SwiftUI

/// 首页：准备好了显示就绪卡片和当前配置；没准备好换成分步引导。
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    /// 从系统设置回来时重新读一遍键盘状态。
    @State private var refresh = UUID()

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if Readiness.remainingSteps(apiConfigured: store.settings.isConfigured) == 0 {
                        TabTitle(caption: Date.now.formatted(Date.FormatStyle(locale: Loc.locale).month().day().weekday(.wide)),
                                 title: L("摘要", "Summary", "概要"))
                            .padding(.top, 8)
                        Dashboard()
                    } else {
                        Text(L("欢迎使用", "Welcome", "ようこそ")).font(.largeTitle.bold()).padding(.top, 8)
                        OnboardingSteps()
                    }
                }
                // 左右 20，和提示词、接口、设置三页的分组卡片对齐。
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .id(refresh)
            }
            .background(Color(.systemGroupedBackground))
            // 自己画大标题，导航栏标题写「首页」，这样二级页的返回按钮叫「首页」。
            .navigationTitle(L("首页", "Home", "ホーム"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRouter.HomePage.self) { page in
                switch page {
                case .keyboard: KeyboardSettingsView()
                case .pinyin: PinyinView()
                case .commonWords: CommonWordsView()
                case .keyboardWords: KeyboardPhrasesView()
                case .lab: LabView()
                case .scene(let index): SceneView(index: index)
                }
            }
            // 键盘页里的「模糊拼音」。
            .navigationDestination(for: AppRouter.SettingsPage.self) { page in
                if page == .fuzzy { FuzzyPinyinView() }
            }
            .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
        }
    }
}

/// 首页试用最后几天的橙色提醒条（U7）。
private struct TrialBanner: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var unlock = UnlockStore.shared

    var body: some View {
        if case .trial(let days, _) = unlock.access, unlock.access.isEndingSoon {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: 0xC93400))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("试用还剩 \(days) 天", "\(days) days left in your free trial", "無料体験は残り \(days) 日"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("之后每天免费 \(AIAccess.dailyFreeUses) 次，解锁不限次数",
                           "Then \(AIAccess.dailyFreeUses) free a day, or unlock for unlimited",
                           "その後は 1 日 \(AIAccess.dailyFreeUses) 回無料、購入で無制限"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { router.openSettings(.unlock) } label: {
                    Text(L("\(unlock.displayPrice) 解锁", "Unlock \(unlock.displayPrice)", "\(unlock.displayPrice)で購入"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Color(hex: 0xFF8A00)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 1, green: 0.54, blue: 0, alpha: 0.16)
                    : UIColor(red: 1, green: 0xF4 / 255, blue: 0xE5 / 255, alpha: 1)
            })))
        }
    }
}

/// 首页（PB1 + PH1，B 数据仪表盘）：AI 今天执行了几次和 7 天柱状图，接口一整行，2×2 的键盘 / 拼音词库 / 常用词 / 键盘常用语，最后是使用指引入口。
private struct Dashboard: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var words = CommonWordsModel()
    @StateObject private var phrases = KeyboardPhrasesModel()
    @ObservedObject private var deployer = RimeDeployer.shared
    @ObservedObject private var grammar = GrammarDownloader.shared
    @State private var stats = AIStats.load()
    @State private var lastRequest = UsageStats.polishRecent.last

    var body: some View {
        if !SharedStorage.isShared { SharedConfigBanner() }
        TrialBanner()
        summaryCard
        apiCard
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            GridCard(icon: "keyboard", title: L("键盘", "Keyboard", "キーボード"), color: DashColor.input,
                     value: store.settings.keyboardLayout.shortTitle,
                     detail: store.settings.fuzzyPinyin.isEmpty ? L("模糊拼音未开", "Fuzzy pinyin off", "あいまい入力オフ") : L("模糊拼音 \(store.settings.fuzzyPinyin.count) 组", "Fuzzy pinyin: \(store.settings.fuzzyPinyin.count)", "あいまい入力 \(store.settings.fuzzyPinyin.count) 組")) { router.openHome(.keyboard) }
            GridCard(icon: "book.closed", title: L("拼音词库", "Pinyin", "ピンイン辞書"), color: DashColor.input,
                     value: L("万象拼音", "Wanxiang", "万象ピンイン"), detail: pinyinStatus.text, dot: pinyinStatus.dot) { router.openHome(.pinyin) }
            GridCard(icon: "text.book.closed", title: L("常用词", "My Words", "ユーザ辞書"), color: DashColor.input,
                     value: "\(words.all.count)", detail: wordsDetail) { router.openHome(.commonWords) }
            GridCard(icon: "star.fill", title: L("键盘常用语", "Keyboard Phrases", "キーボードの定型文"), color: DashColor.phrase,
                     value: "\(phrases.phrases.count)",
                     detail: phrases.phrases.isEmpty ? L("还没有，点进去添加", "None yet. Tap to add", "まだありません。タップして追加") : phrases.phrases.prefix(2).joined(separator: " · ")) { router.openHome(.keyboardWords) }
        }
        labEntry
            .onAppear {
                words.reload()
                phrases.reload()
                stats = AIStats.load()
                lastRequest = UsageStats.polishRecent.last
            }
    }

    /// 摘要卡：今天所有提示词的执行次数（不只「润色」那条）、7 天柱状图、本周合计和平均耗时。
    private var summaryCard: some View {
        DashCard {
            DashCardHeader(icon: "sparkles", title: "AI", color: DashColor.ai)
            HStack(alignment: .firstTextBaseline) {
                DashBigNumber(value: "\(stats.today)", unit: L("次 · 今天", "today", "回・今日"))
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("本周 \(stats.week) 次", "\(stats.week) this week", "今週 \(stats.week) 回"))
                    if let average = stats.averageSeconds {
                        Text(L("平均 \(average) 秒", "Avg \(average) s", "平均 \(average) 秒"))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            DashBarChart(values: stats.days, labels: DashBarChart.weekdayLabels())
            if stats.week == 0 {
                Text(DashText.emptyStats).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// 接口一整行：左上「接口」、右上连接状态，大字服务商，后面灰字「模型 · 最近一次 0.8 秒」。
    private var apiCard: some View {
        Button { router.openModel() } label: {
            DashCard {
                HStack(spacing: 6) {
                    DashCardHeader(icon: "cpu", title: L("接口", "API", "API"), color: DashColor.ai)
                    HStack(spacing: 4) {
                        if let dot = modelStatus.dot { Circle().fill(dot).frame(width: 6, height: 6) }
                        Text(modelStatus.text)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(modelStatus.dot ?? DashColor.system)
                    .lineLimit(1)
                    .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.settings.isConfigured ? ProviderName.of(store.settings.baseURL) : L("还没设置", "Not set up", "未設定"))
                        .font(.system(size: 22, weight: .bold)).lineLimit(1).fixedSize()
                    if store.settings.isConfigured {
                        Text(apiDetail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var apiDetail: String {
        var parts = [store.settings.model]
        if let lastRequest, lastRequest.ok {
            let seconds = String(format: "%.1f", Double(lastRequest.ms) / 1000)
            parts.append(L("最近一次 \(seconds) 秒", "Last \(seconds) s", "前回 \(seconds) 秒"))
        }
        return parts.joined(separator: " · ")
    }

    /// 拼音词库格子的状态：已就绪绿点、需要重新部署橙点、部署中灰字；开了整句模型后面加「· 整句模型」。
    private var pinyinStatus: (text: String, dot: Color?) {
        let grammarTag = GrammarModel.isActive ? L(" · 整句模型", " · Sentence model", "・文章モデル") : ""
        switch deployer.state {
        case .deploying: return (L("部署中…", "Installing…", "インストール中…"), nil)
        case .failed: return (L("部署失败", "Install failed", "インストール失敗"), .red)
        default:
            return deployer.needsDeploy
                ? (L("需要重新部署", "Needs reinstall", "再インストールが必要"), .orange)
                : (L("已就绪", "Ready", "準備完了") + grammarTag, DashColor.ok)
        }
    }
    private var labEntry: some View {
        Button { router.openHome(.lab) } label: {
            HStack(spacing: 12) {
                Image(systemName: "flask").font(.system(size: 20, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("使用指引", "Guide", "使い方ガイド")).font(.headline)
                    Text(L("\(LabScene.all.count) 个场景，学会快速、替换和插入", "\(LabScene.all.count) scenes: Quick, Replace and Insert", "\(LabScene.all.count) 個のシーンでクイック・置き換え・挿入")).font(.footnote).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColor.heroGradient))
        }
        .buttonStyle(.plain)
    }

    /// 测试过才知道连不连得上；没配好写灰字「未设置」，没测过写灰字「还没测试」。
    private var modelStatus: (text: String, dot: Color?) {
        guard store.settings.isConfigured else { return (L("未设置", "Not set up", "未設定"), nil) }
        let ok = (L("连接正常", "Connected", "接続済み"), Optional(DashColor.ok))
        let failed = (L("连接失败", "Connection failed", "接続失敗"), Optional(Color.red))
        switch store.test {
        case .success: return ok
        case .failure: return failed
        case .running: return (L("正在测试", "Testing", "テスト中"), .orange)
        case .idle:
            switch store.lastTestOK {
            case true?: return ok
            case false?: return failed
            case nil: return (L("还没测试", "Not tested", "未テスト"), nil)
            }
        }
    }

    private var wordsDetail: String {
        let manual = words.count(.manual), imported = words.count(.imported)
        if manual + imported == 0 { return words.all.isEmpty ? L("还没有，点进去添加", "None yet. Tap to add", "まだありません。タップして追加") : L("来自系统文本替换", "From Text Replacements", "iPhone のユーザ辞書から") }
        return L("手动 \(manual) · 导入 \(imported)", "Added \(manual) · Imported \(imported)", "手動 \(manual)・読み込み \(imported)")
    }
}

/// 首页摘要卡要的数：都从 DailyStats 读。
struct AIStats {
    var days: [Int]
    var today: Int { days.last ?? 0 }
    var week: Int { days.reduce(0, +) }
    var weekMs: Int

    /// 平均耗时，一位小数；本周没成功过时为 nil。
    var averageSeconds: String? {
        week > 0 ? String(format: "%.1f", Double(weekMs) / Double(week) / 1000) : nil
    }

    static func load() -> AIStats {
        AIStats(days: DailyStats.series("polish.done", days: 7).map(\.value),
                weekMs: UsageStats.week("polish.ms"))
    }
}

/// 2×2 的小卡：卡片头、一行大字、一行灰字（可带状态点），点了跳到对应页面。
private struct GridCard: View {
    var icon: String
    var title: String
    var color: Color
    var value: String
    var detail: String
    var dot: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DashCard {
                DashCardHeader(icon: icon, title: title, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(value).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                        Text(detail).font(.caption).foregroundStyle(dot.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary)).lineLimit(1)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
    }
}

/// 开启键盘的三步：添加键盘、允许完全访问、配置模型接口；下面是词库部署进度。首页和「开启键盘指南」共用。
struct OnboardingSteps: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        let done = [Readiness.keyboardAdded, Readiness.fullAccess == true, store.settings.isConfigured]
        let remaining = done.filter { !$0 }.count
        let current = done.firstIndex(of: false)
        VStack(alignment: .leading, spacing: 12) {
            Text(remaining == 0 ? L("三步都完成了，键盘可以用了。", "All three steps are done. Your keyboard is ready.", "3 つのステップが完了しました。キーボードが使えます。") : L("还差 \(remaining) 步就能用 AI 润色，打字现在就能用。", "\(remaining) more steps to use AI Polish. You can already type.", "あと \(remaining) ステップで AI 機能が使えます。入力はすぐに使えます。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(3 - remaining), total: 3).tint(AppColor.purple)
            if !SharedStorage.isShared { SharedConfigBanner() }
            StepCard(number: 1, title: L("添加 Enclave 键盘", "Add the Enclave keyboard", "Enclave キーボードを追加"), done: done[0], current: current == 0) {
                Text(L("打开系统设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选 Enclave。", "Open Settings › General › Keyboard › Keyboards › Add New Keyboard, then choose Enclave.", "設定 › 一般 › キーボード › キーボード › 新しいキーボードを追加 で Enclave を選びます。"))
            }
            StepCard(number: 2, title: L("允许完全访问", "Allow Full Access", "フルアクセスを許可"), done: done[1], current: current == 1) {
                Text(L("键盘要联网才能调用你的模型。进入 Enclave 设置 › 键盘，打开「允许完全访问」。", "The keyboard needs network access to reach your model. Go to Enclave settings › Keyboards and turn on Allow Full Access.", "モデルを使うにはキーボードの通信が必要です。Enclave の設定 › キーボード で「フルアクセスを許可」をオンにします。"))
                Button(L("打开 Enclave 设置", "Open Enclave Settings", "Enclave の設定を開く")) { AppSettings.open() }
                    .buttonStyle(StepButtonStyle(prominent: current == 1))
                Text(Readiness.fullAccess == false ? L("键盘上次出现时完全访问还没打开。", "Full Access was still off the last time the keyboard appeared.", "前回キーボードを表示したとき、フルアクセスはオフでした。") : L("用一次键盘后，这里会自动打勾。", "This gets checked after you use the keyboard once.", "キーボードを一度使うと、自動でチェックが付きます。"))
                    .font(.caption)
                    .foregroundStyle(Readiness.fullAccess == false ? Color.orange : Color.secondary)
            }
            StepCard(number: 3, title: L("配置模型接口", "Set up your model API", "モデル API を設定"), done: done[2], current: current == 2) {
                Text(SharedStorage.usesClipboardConfig
                     ? L("填 API 地址和 Key，或者从剪贴板导入配置。", "Enter the API URL and key, or import settings from the clipboard.", "API の URL とキーを入力するか、クリップボードから設定を読み込みます。")
                     : L("填 API 地址和 Key。", "Enter the API URL and key.", "API の URL とキーを入力します。"))
                Button(L("去配置", "Set up", "設定する")) { router.openModel() }
                    .buttonStyle(StepButtonStyle(prominent: current == 2))
            }
            DeployCard()
        }
    }
}

private struct StepCard<Content: View>: View {
    var number: Int
    var title: String
    var done: Bool
    var current: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.footnote.bold())
                        .foregroundStyle(current ? .white : .secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(current ? AppColor.purple : Color.clear))
                        .overlay(Circle().strokeBorder(current ? Color.clear : Color.secondary.opacity(0.5)))
                }
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
            }
            if !done {
                VStack(alignment: .leading, spacing: 10) { content }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppColor.purple, lineWidth: current ? 1.5 : 0))
    }
}

/// 当前这一步是实心紫色按钮，后面的步骤是淡紫底。
private struct StepButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : AppColor.purple)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(prominent ? AppColor.purple : AppColor.softFill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 拼音词库部署进度。编译没有真实进度，按大约一分钟估一条进度条。
private struct DeployCard: View {
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: "character.book.closed", color: .orange)
            switch deployer.state {
            case .deploying:
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("正在部署拼音词库…", "Installing the pinyin dictionary…", "ピンイン辞書をインストール中…")).font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(deployer.startedAt ?? context.date)
                        HStack {
                            ProgressView(value: min(elapsed / 60, 0.95)).tint(.orange)
                            Text(L("约 \(max(5, 60 - Int(elapsed))) 秒", "About \(max(5, 60 - Int(elapsed))) s", "約 \(max(5, 60 - Int(elapsed))) 秒")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("拼音词库部署失败", "Couldn't install the pinyin dictionary", "ピンイン辞書をインストールできませんでした")).font(.subheadline)
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button(L("重试", "Retry", "再試行")) { deployer.deploy() }.font(.subheadline.weight(.semibold))
            default:
                Text(deployer.needsDeploy ? L("拼音词库还没部署", "Pinyin dictionary not installed", "ピンイン辞書は未インストール") : L("拼音词库已就绪", "Pinyin dictionary ready", "ピンイン辞書の準備ができました")).font(.subheadline)
                Spacer()
                if deployer.needsDeploy {
                    Button(L("部署", "Install", "インストール")) { deployer.deploy() }.font(.subheadline.weight(.semibold))
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
