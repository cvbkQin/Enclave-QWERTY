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
            Group {
                // 欢迎页四步（WL4）没全好时整页显示它，没有「跳过」；四步都好换回摘要。只用基础打字的只看前两步。
                if WelcomeSetup.Progress(store: store).allDone(privacyAgreed: router.privacyAgreed) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            TabTitle(caption: Date.now.formatted(Date.FormatStyle(locale: Loc.locale).month().day().weekday(.wide)),
                                     title: L("摘要", "Summary", "概要"), showsBuildBadge: true)
                                .padding(.top, 8)
                            Dashboard()
                        }
                        // 左右 20，和提示词、接口、设置三页的分组卡片对齐。
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    WelcomeSetupView(inGuide: false)
                }
            }
            .id(refresh)
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
                    Text(unlock.unlockTitle)
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
        if needsAISetup { AISetupCard() }
        summaryCard
        apiCard
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            GridCard(icon: "keyboard", title: L("键盘", "Keyboard", "キーボード"), color: DashColor.input,
                     value: store.settings.keyboardLayout.shortTitle,
                     detail: store.settings.fuzzyPinyin.isEmpty ? L("模糊拼音未开", "Fuzzy pinyin off", "あいまい入力オフ") : L("模糊拼音 \(store.settings.fuzzyPinyin.count) 组", "Fuzzy pinyin: \(store.settings.fuzzyPinyin.count)", "あいまい入力 \(store.settings.fuzzyPinyin.count) 組")) { router.openHome(.keyboard) }
            // 词库：拼音（万象，要部署）和英文（内置）两份，圆点看拼音的状态。
            GridCard(icon: "book.closed", title: L("词库", "Dictionaries", "辞書"), color: DashColor.input,
                     // 英文关掉时只写「拼音」；下一行只放拼音状态，窄屏上放得下。
                     value: Predictor.englishEnabled ? L("拼音 · 英文", "Pinyin · English", "ピンイン · 英語") : L("拼音", "Pinyin", "ピンイン"),
                     detail: pinyinStatus.text,
                     dot: pinyinStatus.dot) { router.openHome(.pinyin) }
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

    /// 还没连上 AI（OB8）：同意了隐私政策，接口没配好或者上次测试失败。连接测试通过后就不显示。
    private var needsAISetup: Bool {
        router.privacyAgreed && (!store.settings.isConfigured || store.lastTestOK == false)
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
                    } else {
                        Text(L("填好 API Key 才能用 AI", "Add an API key to use AI", "API キーを入れると AI が使えます"))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
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

/// 拼音词库部署进度。编译没有真实进度，按大约一分钟估一条进度条。
struct DeployCard: View {
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

/// 跳过引导后首页最上面的深紫卡（OB8）：「跟着教程设置」从选服务商开始，「已有 Key」进接口设置页。
struct AISetupCard: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0xFFE9A8))
                Text(L("AI 还没连上", "AI isn't connected yet", "AI はまだつながっていません"))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color(hex: 0xD9D3FF))
            }
            Text(L("填一个你自己的 API Key，\n就能用 AI 润色", "Add your own API key\nto use AI", "自分の API キーを入れると\nAI が使えます"))
                .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(SetupGuide.showsPrice ? "跟着教程大约 3 分钟 · 1 元可调用约 500 次" : L("跟着教程大约 3 分钟", "About 3 minutes with the guide", "ガイドに沿って約 3 分"))
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0xCFC8FF))
            HStack(spacing: 8) {
                Button { router.setupGuide = .provider } label: {
                    Text(L("跟着教程设置", "Follow the Guide", "ガイドで設定"))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0x4A3BD6))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                }
                Button { router.openModel() } label: {
                    Text(L("已有 Key", "I Have a Key", "キーがある"))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.14)))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
            LinearGradient(colors: [Color(hex: 0x2A2160), Color(hex: 0x4A3BD6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: Color(hex: 0x4A3BD6).opacity(0.28), radius: 14, y: 12))
    }
}
