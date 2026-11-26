import StoreKit
import SwiftUI
import UIKit

/// 设置顶部的 AI 卡（R4，design/app-redesign，11-22 交付）：标题行紫色小方块 +「AI」+ ›，大数字，一条 4pt 细线，一句说明。
/// 卡里不放按钮和格子，整张卡点进解锁页；最后 3 天、今天用完时数字和细线变橙。
struct EnclaveAICard: View {
    @ObservedObject private var unlock = UnlockStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(HIG.accentFill))
                    .accessibilityHidden(true)
                // 备案口径是开发者不提供模型服务，卡片标题只写「AI」。
                Text("AI").font(.headline)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(big)
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .foregroundStyle(warn ? HIG.warning : Color.primary)
                if let unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 6)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(warn ? HIG.warning : HIG.accentFill)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.top, 10)
            .accessibilityHidden(true)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DashColor.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var usesLeft: Int { AIAccess.usesLeftToday }

    /// 橙色：试用最后 3 天、今天的免费次数用完。
    private var warn: Bool {
        switch unlock.access {
        case .notStarted, .expired: return usesLeft == 0
        case .trial: return unlock.access.isEndingSoon
        case .unlocked: return false
        }
    }

    private var big: String {
        switch unlock.access {
        case .notStarted, .expired: return "\(usesLeft)"
        case .trial(let days, _): return "\(days)"
        case .unlocked: return L("不限次数", "Unlimited", "回数無制限")
        }
    }

    private var unit: String? {
        switch unlock.access {
        case .notStarted, .expired: return L("次 · 今天还剩", "left today", "回・今日の残り")
        case .trial: return L("天 · 试用剩余", "days left in trial", "日・無料体験の残り")
        case .unlocked: return nil
        }
    }

    private var progress: CGFloat {
        switch unlock.access {
        case .notStarted, .expired: return CGFloat(usesLeft) / CGFloat(AIAccess.dailyFreeUses)
        case .trial(let days, _): return CGFloat(days) / CGFloat(AIAccess.trialDays)
        case .unlocked: return 1
        }
    }

    private var detail: String {
        let uses = AIAccess.dailyFreeUses
        switch unlock.access {
        case .notStarted, .expired:
            if usesLeft == 0 {
                return L("今天的 \(uses) 次用完了，明天 0 点恢复。", "Today's \(uses) free uses are gone. They come back at midnight.",
                         "今日の \(uses) 回を使い切りました。0 時に戻ります。")
            }
            if unlock.access == .notStarted {
                return L("每天免费 \(uses) 次。可以免费试用 \(AIAccess.trialDays) 天，不限次数。",
                         "\(uses) free uses a day. Try \(AIAccess.trialDays) days unlimited for free.",
                         "1 日 \(uses) 回まで無料。\(AIAccess.trialDays) 日間、回数無制限で無料体験できます。")
            }
            return L("每天免费 \(uses) 次，明天 0 点恢复。一次买断，不限次数。", "\(uses) free uses a day, reset at midnight. Pay once for unlimited.",
                     "1 日 \(uses) 回まで無料、0 時にリセット。買い切りで回数無制限。")
        case .trial(_, let ends):
            let day = Loc.monthDay(AIAccess.lastTrialDay(ends: ends))
            return L("用到 \(day)，之后每天免费 \(uses) 次。", "Until \(day), then \(uses) free uses a day.",
                     "\(day)まで。その後は 1 日 \(uses) 回まで無料。")
        case .unlocked:
            return L("已买断。谢谢支持。", "Purchased. Thank you for your support.", "購入済みです。ありがとうございます。")
        }
    }
}

/// 设置（IA5；11-26 对齐清单第 96 条重排，顺序固定）：AI 卡；同步（同步与备份）；通用（语言、日间 / 夜间）；上手（首次设置、功能演示）；反馈；隐私、关于；测试工具（内测、公测版）。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if router.wideLayout {
            // iPad 宽屏（PA3 ⑤）：左边设置列表，右边打开选中的那一页；子页面内容照 iPhone，最宽 640（解锁页 560）。
            SettingsSplitView {
                settingsList
            } destination: { page in
                destination(page)
                    .padReadable(maxWidth: page == .unlock ? PadWidth.unlock : PadWidth.content)
            }
        } else {
            NavigationStack(path: $router.settingsPath) {
                settingsList
                    .navigationDestination(for: AppRouter.SettingsPage.self) { destination($0) }
            }
        }
    }

    /// iPad 两栏时左边选中的那一行：settingsPath 的第一项（NavigationLink(value:) 点了就换右边）。
    private var sidebarSelection: Binding<AppRouter.SettingsPage?> {
        Binding(get: { router.settingsPath.first }, set: { page in
            router.settingsPath = page.map { [$0] } ?? []
        })
    }

    @ViewBuilder
    private var settingsList: some View {
        Group {
            if router.wideLayout {
                List(selection: sidebarSelection) { sections }
            } else {
                List { sections }
            }
        }
        .pinnedTabTitle(caption: "\(L("飞地输入法", "Enclave", "Enclave")) \(AboutView.devLabel ?? AboutView.version)", title: L("设置", "Settings", "設定"))
        .navigationTitle(L("设置", "Settings", "設定"))
        .tabRootPage()
    }

    @ViewBuilder
    private func destination(_ page: AppRouter.SettingsPage) -> some View {
        switch page {
        case .setup: FirstSetupView()
        case .scratchPad: ScratchPadView()
        case .testTools: TestToolsView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        case .unlock: UnlockView()
        case .language: LanguageView()
        case .privacyPolicy: PrivacyPolicyView()
        case .licenses: LicensesView()
        case .diagnostics: DiagnosticsView()
        case .feedback: FeedbackFormView()
        case .backup: BackupView()
        case .tour: TourChaptersView()
        }
    }

    @ViewBuilder
    private var sections: some View {
        Section {
        } header: {
            VStack(spacing: 12) {
                // 整张卡可点，不要列表行的箭头。
                // 内测版没有试用和解锁：换成内置接口今天的用量。
                if BuiltinAPI.isInternalBuild {
                    BuiltinUsageCard()
                } else {
                    Button { router.settingsPath = [.unlock] } label: {
                        EnclaveAICard()
                            // iPad 两栏：右边是解锁页时卡片描一圈紫边（PA3 ⑤）。
                            .overlay {
                                if router.wideLayout && (router.settingsPath.first ?? .unlock) == .unlock {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HIG.accentFill, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                // 「App 与键盘共享配置」不再占一行，不可用时才显示横幅。
                if SharedStorage.usesClipboardConfig && !SharedStorage.isShared { SharedConfigBanner() }
            }
            .dashFormCard()
        }
        // 同步（对齐清单第 96 条，design/settings-order SO1 ②）：紧跟 AI 卡；顺序固定为 AI、同步、通用、上手、反馈、隐私和关于。
        Section {
            NavigationLink(value: AppRouter.SettingsPage.backup) { BackupSettingsRow() }
        } header: {
            Text(L("同步", "Sync", "同期"))
        }
        Section {
            NavigationLink(value: AppRouter.SettingsPage.language) {
                DashRow(icon: "globe", color: DashColor.input, title: L("语言", "Language", "言語"),
                        value: router.language == .system ? L("跟随 \(DeviceName.current)", DeviceName.current, "\(DeviceName.current) に従う") : router.language.nativeName)
            }
            Picker(selection: $store.settings.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            } label: {
                DashRow(icon: "circle.lefthalf.filled", color: DashColor.input, title: L("日间 / 夜间", "Appearance", "外観"))
            }
            .pickerStyle(.menu)
        } header: {
            Text(L("通用", "General", "一般"))
        } footer: {
            Text(L("只改飞地输入法 App。键盘跟着正在打字的 App 变深浅，和系统键盘一样。", "Applies to the Enclave app. The keyboard matches the app you are typing in, like the system keyboard.", "Enclave App に適用されます。キーボードは入力中の App に合わせて変わります。"))
        }
        // 上手：首次设置（欢迎页四步）、功能演示（「使用指引」11-26 去掉，对齐清单第 96 条）。
        Section {
            NavigationLink(value: AppRouter.SettingsPage.setup) {
                let left = setupStepsLeft
                HStack(spacing: 12) {
                    TintIcon(systemName: "checklist", color: DashColor.ai)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("首次设置", "First-time setup", "初期設定"))
                        Text(L("输入法、完全访问、AI", "Keyboard, Full Access, AI", "キーボード・フルアクセス・AI"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(left == 0 ? L("已完成", "Done", "完了") : L("还差 \(left) 步", "\(left) left", "あと \(left) ステップ"))
                        .foregroundStyle(left == 0 ? Color.secondary : Color(hex: 0xD97706))
                        .lineLimit(1)
                }
            }
            // 功能演示（T95，OG2 ③）：章节页，点一章只看这一章，「从头播放」放 14 步（模拟键盘、预设结果，不调用 API）。
            NavigationLink(value: AppRouter.SettingsPage.tour) {
                DashRow(icon: "hand.tap", color: DashColor.ai, title: L("功能演示", "Feature Tour", "機能デモ"),
                        value: L("约 3 分钟", "About 3 min", "約 3 分"))
            }
        } header: {
            Text(L("上手", "Getting started", "はじめに"))
        }
        // 正式版、公测版（FB1）；内测版换成「诊断与反馈」，两者不同时出现。
        if CrashLog.isEnabled {
            Section {
                NavigationLink(value: AppRouter.SettingsPage.diagnostics) { DiagnosticsRow() }
            } header: {
                Text(L("反馈", "Feedback", "フィードバック"))
            } footer: {
                Text(L("内测版专有。闪退和异常退出的记录只存在手机上。", "Beta only. Crash and exit records stay on this iPhone.", "ベータ版のみ。クラッシュと異常終了の記録はこの iPhone にだけ保存されます。"))
            }
        } else {
            Section {
                NavigationLink(value: AppRouter.SettingsPage.feedback) {
                    DashRow(icon: "envelope", color: DashColor.ai, title: L("反馈问题", "Send Feedback", "フィードバック"))
                }
            } header: {
                Text(L("反馈", "Feedback", "フィードバック"))
            } footer: {
                Text(L("在 App 里填好直接提交给开发者，不用打开邮件。", "Fill it in and send it to the developer right here, no email needed.", "App 内で入力してそのまま開発者に送れます。メールは不要です。"))
            }
        }
        Section {
            NavigationLink(value: AppRouter.SettingsPage.privacy) {
                DashRow(icon: "lock", color: DashColor.system, title: L("隐私", "Privacy", "プライバシー"),
                        value: router.privacyAgreed ? L("已同意", "Agreed", "同意済み") : L("未同意", "Not agreed", "未同意"))
            }
            NavigationLink(value: AppRouter.SettingsPage.about) {
                DashRow(icon: "info.circle", color: DashColor.system, title: L("关于飞地输入法", "About Enclave", "Enclave について"), value: AboutView.devLabel ?? AboutView.version)
            }
        }
        if AccessTestSection.shows {
            AccessTestSection()
        }
        if BuiltinAPI.showsTesterTools {
            Section {
                NavigationLink(value: AppRouter.SettingsPage.testTools) {
                    HStack(spacing: 12) {
                        TintIcon(systemName: "keyboard", color: DashColor.phrase)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(L("测试工具", "Test tools", "テストツール"))
                                TestBadge()
                            }
                            Text(L("打字速度、压力测试", "Typing speed, stress test", "入力の速さ・負荷テスト"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } footer: {
                Text(L("只在内测版、公测版显示。", "Shown only in beta builds.", "ベータ版でのみ表示されます。"))
            }
        }
    }

    /// 首次设置还差几步：只用基础打字（没同意隐私政策）的只算前两步。
    private var setupStepsLeft: Int {
        let progress = WelcomeSetup.Progress(store: store)
        let steps = router.privacyAgreed ? progress.done : Array(progress.done.prefix(2))
        return steps.filter { !$0 }.count
    }
}

/// 设置 › 首次设置：欢迎页四步（D1），做完或「先跳过」回到设置。
struct FirstSetupView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        WelcomeSetupView(inGuide: true) {
            if !router.settingsPath.isEmpty { router.settingsPath.removeLast() }
        }
        .navigationTitle(L("首次设置", "First-time setup", "初期設定"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 设置 › 测试工具（IA6）：打字速度、压力测试两张卡，只在内测版、公测版有入口。
struct TestToolsView: View {
    var body: some View {
        DashPage {
            TypingSpeedCard()
            if PopupLog.enabled { PopupLogCard() }
            StressTestCard()
            #if DEBUG
            // 输入框测试台：只在开发版（内测、公测包里没有）。
            NavigationLink { HostCompatBench() } label: {
                DashCard {
                    HStack {
                        Text("输入框测试台").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    Text("12 种输入框，模仿亚朵、闲鱼、网页等会出问题的 App").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            #endif
        }
        .navigationTitle(L("测试工具", "Test tools", "テストツール"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 「测试工具」后面的橙色小标签：高 18、圆角 6、字 11 半粗。
private struct TestBadge: View {
    var body: some View {
        Text(L("测试", "Test", "テスト"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(light: 0x9A4D00, dark: 0xF2A65E))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(light: 0xFDEBD8, dark: 0x3A2612)))
    }
}

// MARK: - 模型接口

/// 接口配置页（11-03 重排 CF1–CF5，AI 页接口卡「接口配置 ›」点进来）：
/// 状态卡（正在用的配置 +「测试」）→（问答）「和润色用同一个配置」→ 我的配置（一开始是空的，CF1）→「＋ 添加配置」。
/// 点一条换成用它；点 › 编辑（CF3）；左滑删除。润色、问答共用一组配置，各选各的。
struct ModelSettingsView: View {
    /// 问答接口；false 是润色接口。
    let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    /// 没同意隐私政策时点「测试」：和键盘里的锁卡片一样，先去同意。
    @State private var needsPrivacy = false
    @State private var importResult: Bool?
    @State private var sheet: ConfigSheet?
    /// 开着 Key 同步时左滑删方案：先确认（B11），其他设备上的方案和 Key 也会删。
    @State private var deleting: SavedAPI?
    /// 「添加配置」里点了教程：弹层收起后再打开教程。
    @State private var pendingTutorial: Provider?

    /// 弹层：添加（先选服务商再进新建页）或编辑某一条。
    enum ConfigSheet: Identifiable {
        case add
        case edit(SavedAPI)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let item): return item.id.uuidString
            }
        }
    }

    /// 内测版：接口统一用自带的，这一页只能看。测试连接、联网调用、调用偏好在 AI 页。
    private var locked: Bool { BuiltinAPI.isInternalBuild }

    /// 问答页且和润色分开：这一页管问答自己的接口。
    private var ownAnswer: Bool { answer && store.settings.separateAnswer }
    /// 下面的配置列表显示不显示（问答页打开「和润色用同一个配置」时收起）。
    private var showsDetails: Bool { !answer || store.settings.separateAnswer }

    var body: some View {
            Form {
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        statusCard
                        if locked { InternalLockNotice() }
                    }
                    .dashFormCard()
                }
                if answer {
                    Section {
                        SameAPIToggle(locked: locked)
                    }
                }
                if showsDetails {
                    if store.savedAPIs.isEmpty {
                        Section {
                        } header: {
                            EmptyConfigCard(locked: locked) { sheet = .add }.dashFormCard()
                        } footer: {
                            Text(L("配置只存在这台 iPhone 上，API Key 放在钥匙串里。", "Setups stay on this iPhone; API keys are kept in the keychain.", "設定はこの iPhone にだけ保存され、API キーはキーチェーンに入ります。"))
                        }
                    } else {
                        configsSection
                    }
                }
                if SharedStorage.usesClipboardConfig {
                    Section {
                        Button(importResult == false ? L("剪贴板里没有飞地输入法配置", "No Enclave settings on the clipboard", "クリップボードに Enclave の設定がありません") : importResult == true ? L("已导入", "Imported", "読み込みました") : L("从剪贴板导入配置", "Import settings from clipboard", "クリップボードから設定を読み込む")) {
                            importConfig()
                        }
                        .font(.footnote)
                        .foregroundStyle(importResult == false ? Color.orange : AppColor.purple)
                        .lockedRow(locked)
                    }
                }
            }
        .navigationTitle(answer ? L("问答接口", "Q&A API", "質問の API") : L("润色接口", "Polish API", "整える API"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.migrateConfigsIfNeeded() }
        .alert(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"), isPresented: $needsPrivacy) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("阅读并同意", "Read and Agree", "読んで同意する")) { router.showsPrivacyWelcome = true }
        } message: {
            Text(L("同意后才能测试接口和使用 AI。拼音输入不受影响。", "Agree first to test the API and use AI. Pinyin input still works.", "同意すると API のテストと AI が使えます。ピンイン入力はそのまま使えます。"))
        }
        .alert(SyncedDeleteText.title(deleting?.name ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { item in
            Button(L("删除", "Delete", "削除"), role: .destructive) { store.deleteSavedAPI(item.id) }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: { _ in
            Text(SyncedDeleteText.message)
        }
        .sheet(item: $sheet, onDismiss: {
            if let provider = pendingTutorial {
                pendingTutorial = nil
                router.openTutorial(provider, answer: answer)
            }
        }) { which in
            Group {
                switch which {
                case .add:
                    NavigationStack(path: $addPath) {
                        AddConfigSheet { template in
                            addPath = [template]
                        } onTutorial: { openTutorial($0) }
                        .navigationDestination(for: ConfigTemplate.self) { template in
                            ConfigEditor(existing: nil, template: template, answer: answer,
                                         onTutorial: { openTutorial($0) }, onClose: { sheet = nil })
                        }
                    }
                case .edit(let item):
                    NavigationStack {
                        ConfigEditor(existing: item, template: ConfigTemplate.of(item), answer: answer,
                                     onTutorial: { openTutorial($0) }, onClose: { sheet = nil })
                    }
                }
            }
            .environmentObject(store)
            .environmentObject(router)
            .onAppear { addPath = [] }
        }
    }

    /// 添加弹层里从服务商列表推到新建页。
    @State private var addPath: [ConfigTemplate] = []

    private func openTutorial(_ template: ConfigTemplate) {
        pendingTutorial = template.provider
        sheet = nil
    }

    // MARK: 状态卡

    /// 状态卡：logo 42×42 + 服务商 + 灰字模型；「● 连接正常 · 1.0 秒」（问答页能联网再加蓝字「可联网」）；右边「测试」。
    /// 还没配置（CF1）：灰「?」+「还没有配置 / 润色要先接上一个大模型」，「测试」半透明点不了。正在用的存成了配置就写配置的名字。
    private var statusCard: some View {
        let configured = ownAnswer ? store.settings.usesAnswerEndpoint : store.settings.isConfigured
        let url = ownAnswer ? store.settings.answerBaseURL : store.settings.baseURL
        let modelName = ownAnswer ? store.settings.answerModel : store.settings.model
        let state = ownAnswer ? store.answerTest : store.test
        let status = statusLine(configured: configured, state: state)
        return HStack(spacing: 12) {
            if configured {
                ProviderLogo(provider: Provider.detect(url), size: 42, corner: 11)
            } else {
                Text("?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemFill)))
            }
            VStack(alignment: .leading, spacing: 3) {
                // 服务商和模型一行放得下就一行（AC1），窄屏（SE）放不下时模型换到下一行，不截断。
                let name = Text(configured ? (store.currentSavedAPI(answer: ownAnswer)?.name ?? ProviderName.of(url, model: modelName)) : L("还没有配置", "Not set up yet", "まだ設定されていません"))
                    .font(.system(size: 20, weight: .bold))
                let modelText = Text(modelName).font(.system(size: 14)).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        name.lineLimit(1).fixedSize()
                        if configured { modelText.lineLimit(1).fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        name.lineLimit(1).minimumScaleFactor(0.7)
                        if configured { modelText.lineLimit(1).truncationMode(.middle) }
                    }
                }
                if configured {
                    HStack(spacing: 5) {
                        Circle().fill(status.color).frame(width: 8, height: 8)
                        Text(status.text).foregroundStyle(status.color).lineLimit(1)
                        // 「可联网」按联网测试结果（CF5），不再按服务商判断。
                        if answer, WebSearchProbe.stored(baseURL: url, model: modelName) == .online {
                            Text("·").foregroundStyle(.secondary)
                            Text(L("可联网", "Web", "ウェブ可")).foregroundStyle(Color(hex: 0x0A84FF))
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    if let error = status.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(answer ? L("问答要先接上一个大模型", "Connect a model for Q&A first", "質問にはまずモデルをつなぎます")
                         : L("润色要先接上一个大模型", "Connect a model for Polish first", "整えるにはまずモデルをつなぎます"))
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            Button {
                if router.privacyAgreed {
                    Task { ownAnswer ? await store.runAnswerTest() : await store.runTest() }
                } else {
                    needsPrivacy = true
                }
            } label: {
                Group {
                    if state == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("测试", "Test", "テスト"))
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                // 点不了时（还没配置）浅紫字、浅紫底，深色下也看得出是个按钮（不整体调透明度，深色下会几乎看不见）。
                .foregroundStyle(configured ? DashColor.ai : DashColor.ai.opacity(0.45))
                .padding(.horizontal, 16)
                .frame(minWidth: 60, minHeight: 34)
                .background(Capsule().fill(DashColor.ai.opacity(configured ? 0.12 : 0.16)))
            }
            .buttonStyle(.plain)
            .disabled(!configured || state == .running)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
    }

    private func statusLine(configured: Bool, state: AppStore.TestState) -> (text: String, color: Color, error: String?) {
        func connected(_ seconds: Double?) -> (String, Color, String?) {
            let text = L("连接正常", "Connected", "接続 OK")
            guard let seconds else { return (text, DashColor.ok, nil) }
            return (text + " · " + L("\(String(format: "%.1f", seconds)) 秒", "\(String(format: "%.1f", seconds)) s", "\(String(format: "%.1f", seconds)) 秒"), DashColor.ok, nil)
        }
        switch state {
        case .running: return (L("正在测试…", "Testing…", "テスト中…"), .orange, nil)
        case .failure(let message): return (L("连不上", "Can't connect", "接続できません"), .red, message)
        case .success(_, let seconds): return connected(seconds)
        case .idle: break
        }
        if !ownAnswer, store.lastTestOK == true { return connected(nil) }
        if !ownAnswer, store.lastTestOK == false { return (L("连不上", "Can't connect", "接続できません"), .red, nil) }
        return (L("还没测试", "Not tested", "未テスト"), DashColor.system, nil)
    }

    // MARK: 我的配置（CF4、CF5）

    private var configsSection: some View {
        let current = store.currentSavedAPI(answer: answer)
        return Section {
            ForEach(store.savedAPIs) { item in
                ConfigRow(item: item, current: (!answer || ownAnswer) && item.id == current?.id, answer: answer) {
                    guard item.id != current?.id || (answer && !ownAnswer) else { return }
                    store.applySavedAPI(item, answer: answer)
                } onEdit: {
                    sheet = .edit(item)
                }
                .lockedRow(locked)
                .swipeActions(edge: .trailing, allowsFullSwipe: !locked) {
                    if !locked {
                        Button(role: .destructive) {
                            if Keychain.syncsToICloud { deleting = item } else { store.deleteSavedAPI(item.id) }
                        } label: {
                            Text(L("删除", "Delete", "削除"))
                        }
                    }
                }
            }
            Button { sheet = .add } label: {
                Label(L("添加配置", "Add setup", "設定を追加"), systemImage: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DashColor.ai)
            }
            .lockedRow(locked)
        } header: {
            Text(L("我的配置", "My setups", "保存した設定"))
        } footer: {
            Text(answer
                 ? L("标签来自你在配置里点的「联网 · 测试」。不能联网的灰着，也可以选，只是答不了最新消息；没测过的点进去测一下。",
                     "Tags come from the Web search test inside each setup. Grey ones can't search but still work, just not for the latest news. Open an untested one to test it.",
                     "タグは各設定の「Web 検索・テスト」の結果です。グレーは検索できませんが選べます。未テストのものは開いてテストしてください。")
                 : L("点一条换成用它；点 › 编辑；左滑删除。润色和问答用的是同一组配置，各选各的。",
                     "Tap one to switch to it; tap › to edit; swipe left to delete. Polish and Q&A share these setups and pick their own.",
                     "タップで切り替え、› で編集、左スワイプで削除。整えると質問は同じ設定一覧からそれぞれ選びます。"))
        }
    }

    private func importConfig() {
        guard let string = UIPasteboard.general.string, SettingsStore.importString(string) else {
            importResult = false
            return
        }
        store.reload()
        importResult = true
    }
}

/// 「联网调用」那一行：🌐 紫色图标 + 17pt 标题。
private struct WebSearchLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(AppColor.purple)
            configuration.title
        }
    }
}

/// 内测版接口页顶上的说明。
struct InternalLockNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(.systemGray)))
            Text(L("内测版的接口由开发者统一提供，这一页只能查看，灰色带锁的地方都不能改。「接口和提示词」页的「测试连接」「联网调用」和「调用偏好」可以用。内置接口每天可以润色 100 次、问答 50 次。",
                   "In the beta, the API is provided for you, so this page is view-only. Gray areas with a lock can't be changed. On the API & Prompts tab you can still tap Test and change Web search and Search preference. The built-in API allows 100 polishes and 50 answers a day.",
                   "ベータ版では API はあらかじめ用意されているため、このページは表示のみです。鍵の付いたグレーの部分は変更できません。「API とプロンプト」タブの「接続テスト」「ウェブ検索」「検索の頻度」は使えます。内蔵 API は 1 日に整える 100 回・回答 50 回まで使えます。"))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray5)))
    }
}

/// 「和润色用同一个接口」（AI › 问答页；问答接口详情里没分开时也有一个）。副标题按润色那家写能不能联网。
struct SameAPIToggle: View {
    @EnvironmentObject private var store: AppStore
    var locked: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { !store.settings.separateAnswer }, set: { store.settings.separateAnswer = !$0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("和润色用同一个配置", "Same setup as Polish", "整えると同じ設定"))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .tint(AppColor.purple)
        .lockedRow(locked)
    }

    /// 「打开后问答也用 DeepSeek，不能联网搜索」。
    private var subtitle: String {
        guard store.settings.isConfigured else { return L("润色还没设置", "Polish isn't set up", "整えるは未設定") }
        let name = store.currentSavedAPI(answer: false)?.name ?? ProviderName.of(store.settings.baseURL, model: store.settings.model)
        return L("打开后问答也用「\(name)」", "When on, Q&A also uses “\(name)”", "オンにすると質問も「\(name)」を使います")
    }
}

/// 小锁：灰底白锁的小圆。
struct LockBadge: View {
    var size: CGFloat = 20
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(.systemGray)))
            .accessibilityLabel(L("内测版不可修改", "Locked in the beta", "ベータ版では変更不可"))
    }
}

extension View {
    /// 内测版不能改的一行：点不动、字变淡，整行盖一层半透明灰，右边一把小锁。
    @ViewBuilder
    func lockedRow(_ locked: Bool) -> some View {
        if locked {
            // 右边给锁让出位置，值的最后几个字不被挡住。
            self.padding(.trailing, 20)
                .disabled(true)
                .opacity(0.45)
                .overlay(alignment: .trailing) { LockBadge(size: 18).offset(x: 6) }
                .listRowBackground(Color(.systemGray4).opacity(0.55))
        } else {
            self
        }
    }

    /// 内测版不能改的一整块（服务商格子）：盖一个半透明灰色圆角框，中间一把锁。
    @ViewBuilder
    func lockedBox(_ locked: Bool) -> some View {
        if locked {
            self.disabled(true)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray3).opacity(0.55))
                        HStack(spacing: 6) {
                            LockBadge(size: 22)
                            Text(L("内测版不可修改", "Locked in the beta", "ベータ版では変更不可"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Color(.systemBackground).opacity(0.9)))
                    }
                }
        } else {
            self
        }
    }
}

/// 服务商 logo：品牌色圆角方块 + 首字（AC1 的占位样式；没有放各家官方图标，图标要授权）。
/// 自定义是灰底「＋」。
struct ProviderLogo: View {
    var provider: Provider
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(color)
            if provider == .custom {
                Image(systemName: "plus").font(.system(size: size * 0.5, weight: .bold))
            } else {
                Text(letter).font(.system(size: size * 0.5, weight: .bold))
            }
        }
        .foregroundStyle(provider == .kimi ? Color(light: 0xFFFFFF, dark: 0x111111) : Color.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var letter: String {
        switch provider {
        case .deepseek: return "D"
        case .openai: return "O"
        case .kimi: return "K"
        case .qwen: return L("通", "Q", "Q")
        case .glm: return L("智", "Z", "Z")
        case .hunyuan: return L("混", "H", "H")
        case .ollama: return "O"
        case .custom: return "+"
        }
    }

    private var color: Color {
        switch provider {
        case .deepseek: return Color(hex: 0x4D6BFE)
        // Kimi：浅色黑底白字，深色反过来白底黑字（AC1 深色图）。
        case .kimi: return Color(light: 0x111111, dark: 0xFFFFFF)
        case .qwen: return Color(hex: 0x615CED)
        case .glm: return Color(hex: 0x3366FF)
        case .hunyuan: return Color(hex: 0x0052D9)
        case .openai, .ollama: return Color(light: 0x111111, dark: 0x3A3A3C)
        case .custom: return Color(hex: 0x8E8E93)
        }
    }
}

// MARK: - 键盘

/// 「键盘」标签（IA2）：全部打字设置，二级页是模糊拼音、词库、常用词、键盘常用语、按键判定。
struct KeyboardTab: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.keyboardPath) {
            KeyboardSettingsView()
                // 子页面内容照 iPhone，iPad 宽屏时最宽 640 居中。
                .navigationDestination(for: AppRouter.KeyboardPage.self) { page in
                    Group {
                        switch page {
                        case .fuzzy: FuzzyPinyinView()
                        case .doublePinyin: DoublePinyinView()
                        case .doublePinyinPractice: DoublePinyinPracticeView()
                        case .pinyin: PinyinView()
                        case .commonWords: CommonWordsView()
                        case .keyboardWords: KeyboardPhrasesView()
                        case .touch: TouchCalibrationView()
                        }
                    }
                    .padReadable(router.wideLayout)
                }
                .navigationDestination(for: AppRouter.ExtDictGroupPage.self) { group in
                    Group {
                        switch group {
                        case .hot: HotDictsView()
                        case .imported: ImportedDictsView()
                        }
                    }
                    .padReadable(router.wideLayout)
                }
                .navigationDestination(for: AppRouter.ExtDictPage.self) { page in
                    ExtDictDetailView(id: page.id).padReadable(router.wideLayout)
                }
        }
    }
}

/// 键盘标签的内容：主要语言、中文布局、拼音、英文、按键、词库和常用词。AI 相关的三组在 AI 标签（KeyboardAISection）。
struct KeyboardSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var deployer = RimeDeployer.shared
    @StateObject private var words = CommonWordsModel()
    @StateObject private var phrases = KeyboardPhrasesModel()
    @State private var touchEnabled = TouchCalibration.isEnabled
    @State private var touchKeys = TouchCalibration.summary.keys
    /// 从系统设置回来时重新读一遍完全访问。
    @State private var refresh = UUID()

    var body: some View {
        // iPad 宽屏（PA3 ⑥）：两列。左边键盘状态、主要语言、中文布局，右边拼音、英文、按键、词库和常用词；竖屏一列、最宽 640。
        PadColumns {
            // 读一下 refresh：从系统设置回来时 body 重算，完全访问的横幅跟着出现或消失。
            let _ = refresh
            // B 卡片放在 Section 的 header 里，分组的大圆角裁不到，四角完整（见 dashFormCard）。
            // 只在没开完全访问时放这一组：空的 header 会在标题下面多出约 40pt 空白。
            if KeyboardStatus.fullAccess == false {
                Section {
                } header: {
                    NotSyncedBanner()
                        .dashFormCard()
                }
            }
            // 主要语言（EM1/EM2）：小标题 + 白卡里的三段选择，脚注随选项变。
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("主要语言", "Primary language", "主な言語"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    Picker(L("主要语言", "Primary language", "主な言語"), selection: $store.settings.inputLanguage) {
                        ForEach(InputLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
                }
                .dashFormCard()
            } footer: {
                Text(languageFooter)
            }
            if store.settings.inputLanguage != .englishOnly {
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("中文布局", "Chinese layout", "中国語の配列"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        HStack(spacing: 12) {
                            ForEach([KeyboardLayout.nineKey, .qwerty]) { layout in
                                LayoutCard(layout: layout, selected: store.settings.keyboardLayout == layout,
                                           detail: layoutDetail(layout)) {
                                    store.settings.keyboardLayout = layout
                                }
                            }
                        }
                    }
                    .dashFormCard()
                } footer: {
                    // 选全键盘时下面紧接着「打法」，不写脚注（KS2）。
                    if store.settings.keyboardLayout == .nineKey {
                        Text(L("英文总是用全键盘。全拼 / 双拼在选全键盘后出现。", "English always uses QWERTY. Full / double pinyin appears once you choose QWERTY.",
                               "英語は常に QWERTY です。全拼 / 双拼は QWERTY を選ぶと表示されます。"))
                    }
                }
                // 打法（KS2）：全拼 / 双拼只对全键盘生效，选全键盘才出现；选双拼再多一行进「双拼方案」。
                if store.settings.keyboardLayout == .qwerty {
                    Section {
                        HStack {
                            Text(L("打法", "Typing", "入力方式"))
                            Spacer(minLength: 12)
                            Picker(L("打法", "Typing", "入力方式"), selection: doubleOn) {
                                Text(L("全拼", "Full", "全拼")).tag(false)
                                Text(L("双拼", "Double", "双拼")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        if let scheme = store.settings.doublePinyin {
                            NavigationLink(value: AppRouter.KeyboardPage.doublePinyin) {
                                HStack {
                                    Text(L("双拼方案", "Double pinyin scheme", "双拼の方式"))
                                    Spacer()
                                    Text(scheme.shortTitle).foregroundStyle(.secondary)
                                }
                            }
                        }
                        // 「，。」键（PU2 ③，对齐清单第 80 条）：放空格左边还是右边，默认右边。只管键盘排法，不用重新部署。
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("「，。」键", "「，。」 key", "「，。」キー"))
                                Text(L("点出逗号，上滑出句号", "Tap for a comma, swipe up for a period", "タップで読点、上フリックで句点"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Picker(L("「，。」键", "「，。」 key", "「，。」キー"), selection: $store.settings.quickPunctSide) {
                                ForEach(QuickPunctSide.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            DictionaryDeployStatus()
                            Text(typingFooter)
                            Text(L("「，。」键只对全键盘生效；九宫格本来就有「，。?!」键。",
                                   "The 「，。」 key is QWERTY only; 9-key already has a 「，。?!」 key.",
                                   "「，。」キーは QWERTY のみです。10キーにはもともと「，。?!」キーがあります。"))
                        }
                    }
                }
            }
            // iPad（PA3 ⑥）：九键靠哪边、11 寸字母上的数字和符号，只在 iPad 上显示。
            if UIDevice.current.userInterfaceIdiom == .pad {
                Section {
                    if store.settings.inputLanguage != .englishOnly {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("九键位置", "9-key side", "10キーの位置"))
                                Text(L("九键靠哪边，另一边放 AI 栏、联想和候选", "Styles, suggestions and candidates go on the other side",
                                       "反対側に AI バー、予測、候補を表示"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Picker(L("九键位置", "9-key side", "10キーの位置"), selection: $store.settings.nineKeySide) {
                                ForEach(NineKeySide.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }
                    Toggle(isOn: $store.settings.padLetterHints) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("字母上的数字和符号", "Numbers and symbols on letters", "文字キーの数字と記号"))
                            Text(L("下滑输入，和 iPad 原生一样", "Swipe down to type them, like the iPad keyboard",
                                   "下にスワイプして入力（iPad 標準と同じ）"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(store.settings.inputLanguage != .englishOnly ? L("9 键（iPad）", "9-key (iPad)", "10キー（iPad）") : "iPad")
                } footer: {
                    Text(L("只在 iPad 上显示。字母上的数字和符号只在 11 寸的 26 键上有（13 寸本来就有数字行）；浮动键盘不分左右、不画小字。",
                           "iPad only. Numbers on letters appear on the 11-inch QWERTY layout (13-inch has a number row); the floating keyboard is unaffected.",
                           "iPad のみ。文字キーの数字は 11 インチの QWERTY に表示されます（13 インチには数字列があります）。フローティングキーボードには影響しません。"))
                }
            }
        } right: {
            let _ = refresh
            if store.settings.inputLanguage != .englishOnly {
                // 拼音组最上面是拼音显示（F12，KS1 ②）：上方一行（默认，同 iOS 原生）/ 侧边。键盘上长按「中/英」也能切。
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("拼音", "Pinyin", "ピンイン"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        HStack(spacing: 12) {
                            ForEach(PinyinDisplay.allCases) { display in
                                PinyinDisplayCard(display: display, selected: store.settings.pinyinDisplay == display) {
                                    store.settings.pinyinDisplay = display
                                }
                            }
                        }
                    }
                    .dashFormCard()
                } footer: {
                    Text(L("拼音显示：受 iOS 系统限制，选「上方一行」时拼音那一行和上面系统留的边加起来会显得比较宽，介意的话建议选「侧边」：没有拼音那一行，键盘矮一点，展开回答卡时也不留空白。在键盘上长按「中/英」也能切换。",
                           "Pinyin display: due to an iOS limitation, Row above adds a pinyin row on top of the system's own margin, so it can look wide. If that bothers you, choose Side: there's no pinyin row, the keyboard is shorter and the answer card has no gap. You can also long-press 中/英 on the keyboard to switch.",
                           "ピンインの表示：iOS の制限により、「上の行」ではピンインの行とシステムの余白が重なって幅広く見えることがあります。気になる場合は「横」をおすすめします。ピンインの行がなく、キーボードが少し低くなり、回答カードを開いても隙間がありません。キーボードの「中/英」を長押ししても切り替えられます。"))
                }
                Section {
                    NavigationLink(value: AppRouter.KeyboardPage.fuzzy) {
                        HStack {
                            Text(L("模糊拼音", "Fuzzy pinyin", "あいまい入力"))
                            Spacer()
                            Text(store.settings.fuzzyPinyin.isEmpty ? L("未开启", "Off", "オフ") : L("已开 \(store.settings.fuzzyPinyin.count) 组", "\(store.settings.fuzzyPinyin.count) on", "\(store.settings.fuzzyPinyin.count) 組オン"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    CorrectionToggles()
                    PredictionToggle()
                    EmojiToggle()
                    // B5：拼音组最后一行（TC1），默认关，第一个版本带「新」。
                    Toggle(isOn: $store.settings.traditionalOutput) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(L("繁体输出", "Traditional Chinese output", "繁体字で出力"))
                                NewBadge()
                            }
                            Text(L("候选和上屏都是繁体字，例：输入法 → 輸入法", "Candidates and typed text use Traditional characters, e.g. 输入法 → 輸入法",
                                   "候補と確定する文字が繁体字になります。例：输入法 → 輸入法"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(CorrectionToggles.footnote + "\n\n" + L("繁体输出：还是用拼音打，模糊拼音、纠错、联想都照常；常用词和学到的词也会显示成繁体。只转换你打出的字，AI 润色和回答的结果不转换。",
                                                              "Traditional output: you still type pinyin, and fuzzy pinyin, autocorrect and predictions work as usual. Your words and learned words show in Traditional too. Only what you type is converted; AI polish and answers are not.",
                                                              "繁体字で出力：入力はピンインのままで、あいまい入力・自動修正・予測もそのまま使えます。ユーザ辞書や学習した語も繁体字で表示されます。変換するのは入力した文字だけで、AI の整え・回答の結果は変換しません。"))
                }
            }
            Section(L("英文", "English", "英語")) {
                EnglishSuggestionsToggle()
                Toggle(isOn: $store.settings.autoCapitalize) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("句首自动大写", "Auto-capitalization", "文頭を自動で大文字に"))
                        Text(L("句子开头的第一个字母自动大写", "Capitalizes the first letter of each sentence", "文の最初の文字を自動で大文字にします"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L("按键和外观", "Keys & appearance", "キーと外観")) {
                NavigationLink(value: AppRouter.KeyboardPage.touch) {
                    HStack {
                        Text(L("按键判定", "Key detection", "キーの判定"))
                        Spacer()
                        Text(touchEnabled ? L("按手指习惯 · \(touchKeys) 个键", "Learned · \(touchKeys) keys", "癖に合わせる・\(touchKeys) キー") : L("未开启", "Off", "オフ"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Toggle(L("按键震动", "Haptics", "触覚"), isOn: $store.settings.keyHaptics)
                Toggle(isOn: $store.settings.keySound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("按键声音", "Sounds", "サウンド"))
                        Text(L("手机静音时不响", "Silent when the iPhone is muted", "消音モードでは鳴りません")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // #19 测试：键盘底色用系统毛玻璃。真机在 Chrome 里切回时看有没有系统按键残影，有的话关掉。
                Toggle(isOn: $store.settings.keyboardGlass) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("毛玻璃背景（测试）", "Frosted background (test)", "すりガラス背景（テスト）"))
                        Text(L("键盘底色透出后面的颜色，和系统那截玻璃接上", "The keyboard lets the colors behind it show through and blends with the system glass",
                               "キーボードの背景に後ろの色が透け、システムのガラス部分となじみます"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L("词库和常用词", "Dictionaries & words", "辞書とユーザ辞書")) {
                NavigationLink(value: AppRouter.KeyboardPage.pinyin) {
                    let status = pinyinStatus
                    HStack(spacing: 12) {
                        TintIcon(systemName: "book.closed", color: DashColor.input)
                        Text(L("词库", "Dictionaries", "辞書"))
                        Spacer(minLength: 8)
                        Circle().fill(status.color).frame(width: 7, height: 7)
                        Text(status.text).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                NavigationLink(value: AppRouter.KeyboardPage.commonWords) {
                    DashRow(icon: "text.book.closed", color: DashColor.input, title: L("常用词", "My Words", "ユーザ辞書"), value: "\(words.all.count)")
                }
                NavigationLink(value: AppRouter.KeyboardPage.keyboardWords) {
                    DashRow(icon: "star.fill", color: DashColor.phrase, title: L("键盘常用语", "Keyboard Phrases", "キーボードの定型文"), value: "\(phrases.phrases.count)")
                }
            }
            ClipboardSettingsSection(refresh: refresh)
        }
        .tint(AppColor.purple)
        .pinnedTabTitle(caption: caption, title: L("键盘", "Keyboard", "キーボード"))
        .navigationTitle(L("键盘", "Keyboard", "キーボード"))
        .tabRootPage()
        .onAppear {
            // 键盘里改的（iPad 9 键换边、长按中/英换布局）存在共用设置里，进这一页时重读一次（第 86 条）。
            store.reloadSettings()
            words.reload()
            phrases.reload()
            touchEnabled = TouchCalibration.isEnabled
            touchKeys = TouchCalibration.summary.keys
        }
        .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
    }

    /// 标题上的灰字：「九宫格 · 中文」（布局 · 主要语言）。
    private var caption: String {
        let layout = store.settings.inputLanguage == .englishOnly ? KeyboardLayout.qwerty : store.settings.keyboardLayout
        let double = layout == .qwerty && store.settings.inputLanguage != .englishOnly && store.settings.doublePinyin != nil
        return ([layout.shortTitle] + (double ? [L("双拼", "Double pinyin", "双拼")] : []) + [store.settings.inputLanguage.title]).joined(separator: " · ")
    }

    /// 选全键盘时卡片下面的小字；九宫格那张放一行空白，两张一样高。选九宫格时都不写（KS2）。
    private func layoutDetail(_ layout: KeyboardLayout) -> Text? {
        guard store.settings.keyboardLayout == .qwerty else { return nil }
        return layout == .qwerty ? qwertyDetail : Text(" ")
    }

    /// 全键盘卡片下面的小字：「全拼」或「双拼 · 小鹤」（方案名紫色）。
    private var qwertyDetail: Text {
        guard let scheme = store.settings.doublePinyin else { return Text(L("全拼", "Full pinyin", "全拼")) }
        return Text(L("双拼 · ", "Double · ", "双拼・")) + Text(scheme.shortTitle).foregroundColor(AppColor.purple)
    }

    /// 打法：全拼 / 双拼。换了要重新部署词库（几秒）；切回全拼时记着方案，再切双拼还是它。
    private var doubleOn: Binding<Bool> {
        Binding(get: { store.settings.doublePinyin != nil },
                set: { on in
                    let scheme = on ? DoublePinyin.lastChosen : nil
                    guard scheme != store.settings.doublePinyin else { return }
                    if let current = store.settings.doublePinyin { DoublePinyin.lastChosen = current }
                    store.settings.doublePinyin = scheme
                    deployer.deploy()
                })
    }

    private var typingFooter: String {
        if store.settings.doublePinyin != nil {
            return L("双拼只对全键盘生效，九宫格照旧打全拼。方案、键上提示、预览都在「双拼方案」里。",
                     "Double pinyin only applies to QWERTY; 9-key still uses full pinyin. Scheme, key hints and preview are under Double pinyin scheme.",
                     "双拼は QWERTY だけに適用され、10キーは全拼のままです。方式・キーのヒント・プレビューは「双拼の方式」にあります。")
        }
        let example = ["ni", "hao"].compactMap(DoublePinyin.lastChosen.code(for:)).joined()
        return L("全拼「你好」打 nihao。双拼每个字只按两个键（\(DoublePinyin.lastChosen.title)里打 \(example)），选双拼后可以挑方案。九宫格照旧打全拼。",
                 "Full pinyin types 你好 as nihao. Double pinyin takes two keys per character (\(example) in \(DoublePinyin.lastChosen.title)); pick a scheme after choosing Double. 9-key still uses full pinyin.",
                 "全拼では「你好」を nihao と入力します。双拼は 1 文字 2 キー（\(DoublePinyin.lastChosen.title)では \(example)）で、双拼を選ぶと方式を選べます。10キーは全拼のままです。")
    }

    /// 词库那行：已就绪绿点、需要重新部署橙点、部署中灰点。
    private var pinyinStatus: (text: String, color: Color) {
        switch deployer.state {
        case .deploying: return (L("部署中…", "Installing…", "インストール中…"), DashColor.system)
        case .failed: return (L("部署失败", "Install failed", "インストール失敗"), .red)
        default:
            return deployer.needsDeploy
                ? (L("需要重新部署", "Needs reinstall", "再インストールが必要"), .orange)
                : (L("已就绪", "Ready", "準備完了"), DashColor.ok)
        }
    }

    private var languageFooter: String {
        switch store.settings.inputLanguage {
        case .chinese: return L("打开键盘先是拼音，按「中/英」切到英文。", "The keyboard opens in pinyin. Tap 中/英 for English.", "キーボードはピンインで開きます。「中/英」で英語に切り替えます。")
        case .englishFirst: return L("打开键盘先是英文，按「中/英」切到拼音。", "The keyboard opens in English. Tap 中/英 for pinyin.", "キーボードは英語で開きます。「中/英」でピンインに切り替えます。")
        case .englishOnly: return L("只有英文全键盘，不打拼音。「中/英」键换成逗号，长按出 ' ? !", "English QWERTY only, no pinyin. The 中/英 key becomes a comma; hold it for ' ? !", "英語の QWERTY のみで、ピンインは使いません。「中/英」キーはカンマになり、長押しで ' ? ! が出ます。")
        }
    }
}

/// 键盘 › 按键判定：原来键盘页里的那张卡（学到的格子、开关、重置）。
struct TouchCalibrationView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            TouchCalibrationSection(layout: store.settings.inputLanguage == .englishOnly ? .qwerty : store.settings.keyboardLayout)
        }
        .tint(AppColor.purple)
        .navigationTitle(L("按键判定", "Key detection", "キーの判定"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// AI › 接口页最下面「键盘里的 AI」：结果卡左边的按钮 ›、处理长文本、润色时的发光动画（润色和问答共用）。
struct KeyboardAISection: View {
    @EnvironmentObject private var store: AppStore
    /// 打开「处理长文本」前的二次确认。
    @State private var confirmLongText = false

    var body: some View {
        Section {
            NavigationLink(value: AppRouter.AIPage.resultKey) {
                HStack {
                    Text(L("结果卡左边的按钮", "Button beside the result", "結果の左のボタン"))
                    Spacer(minLength: 8)
                    Text(resultKeySummary).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            // 打开要再确认一次：长文本处理慢、更容易改错，替换的范围也更大。
            Toggle(isOn: Binding(get: { store.settings.longText },
                                 set: { on in if on { confirmLongText = true } else { store.settings.longText = false } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("处理长文本", "Process long text", "長い文章も処理"))
                    Text(L("关着时 AI 只读光标前约 100 字", "When off, AI reads about 100 characters before the cursor", "オフのとき AI はカーソル前の約 100 字だけを読みます"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $store.settings.polishAnimation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("润色时的发光动画", "Glow while polishing", "整えるときの光るアニメーション"))
                    Text(L("系统开了「减弱动态效果」时自动关闭", "Turns off automatically with Reduce Motion", "「視差効果を減らす」がオンのときは自動でオフ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("键盘里的 AI", "AI on the keyboard", "キーボードの AI"))
        } footer: {
            Text(L("没选中文字时，AI 只处理光标前约 100 字，按整句截取；打开「处理长文本」后约 200 字。文字越长越慢、越容易改错，替换前请看一遍结果。替换只换送去处理的那一段，其余不动；要处理整段，先全选再点 ✨。",
                   "With nothing selected, AI handles about 100 characters before the cursor, cut at whole sentences; about 200 with Process long text on. Longer text is slower and easier to get wrong, so check the result first. Replace only changes the part that was sent; to handle a whole passage, select it first, then tap ✨.",
                   "何も選択していないとき、AI はカーソル前の約 100 字を文単位で処理します。「長い文章も処理」がオンなら約 200 字。長いほど遅く、誤りやすいので、置き換える前に結果を確認してください。置き換えは送った部分だけで、残りはそのままです。全体は全選択してから ✨ をタップします。"))
        }
        .tint(AppColor.purple)
        .alert(L("打开「处理长文本」？", "Turn on Process long text?", "「長い文章も処理」をオンにしますか？"), isPresented: $confirmLongText) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("打开", "Turn On", "オンにする")) { store.settings.longText = true }
        } message: {
            Text(L("AI 每次会读光标前约 200 字。文字越长，生成越慢、越容易改错，替换的范围也越大。替换前请先看一遍结果，不对可以撤销。",
                   "AI will read about 200 characters before the cursor. Longer text is slower, more likely to be changed by mistake, and Replace changes more at once. Check the result before replacing; you can undo.",
                   "AI はカーソル前の約 200 字を読みます。長いほど時間がかかり、誤って書き換えられやすく、置き換える範囲も広くなります。置き換える前に結果を確認してください。取り消しもできます。"))
        }
    }

    /// 右边灰字：「替换 · 上滑插入」。
    private var resultKeySummary: String {
        let settings = store.settings
        let primary = settings.resultKeyPrimary
        let direction: String
        if settings.resultKeySwipe == .pop {
            direction = L("下划", "down: ", "下へ")
        } else {
            direction = settings.resultKeyWheelUp ? L("上滑", "up: ", "上へ") : L("下滑", "down: ", "下へ")
        }
        return "\(primary.title) · \(direction)\(primary.other.title)"
    }
}

/// AI › 结果卡左边的按钮：原来键盘页里的两张卡和脚注。
struct ResultKeySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
            } header: {
                HStack(spacing: 12) {
                    ForEach(ResultKeyAction.allCases) { action in
                        ResultKeyCard(action: action, settings: store.settings,
                                      selected: store.settings.resultKeyPrimary == action) {
                            store.settings.resultKeyPrimary = action
                        }
                    }
                }
                .dashFormCard()
            } footer: {
                Text(resultKeyFooter)
            }
        }
        .tint(AppColor.purple)
        .navigationTitle(L("结果卡左边的按钮", "Button beside the result", "結果の左のボタン"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 点一下做什么、怎么换到另一个，随设置变。
    private var resultKeyFooter: String {
        let settings = store.settings
        let tap = settings.resultKeyPrimary == .replace
            ? L("点一下把结果换掉输入框里的话", "Tap to replace the text in the field with the result", "タップで入力欄の文を結果に置き換えます")
            : L("点一下把结果接在输入框里的话后面", "Tap to add the result after the text in the field", "タップで入力欄の文の後ろに結果を追加します")
        let other = settings.resultKeyPrimary.other
        let detail = other == .insert
            ? L("插入（接在原来的话后面）", "insert (add it after the existing text)", "挿入（元の文の後ろに追加）")
            : L("替换（换掉原来的话）", "replace (swap out the existing text)", "置き換え（元の文と入れ替え）")
        let swipe = L("按住往上推", "Hold and push up to ", "長押しで上に押すと")
        return L("\(tap)；\(swipe)\(detail)。", "\(tap). \(swipe)\(detail).", "\(tap)。\(swipe)\(detail)。")
    }

}

/// 布局选择卡片：上面一张简化的键盘图示，下面名称和勾选圈。功能演示首页也用（T95）。
struct LayoutCard: View {
    var layout: KeyboardLayout
    var selected: Bool
    /// 名称下面的小字（全键盘：「全拼」或「双拼 · 小鹤」，KS2）。
    var detail: Text? = nil
    /// 图示高度：演示首页要一屏放下，矮屏收到 50。
    var illustrationHeight: CGFloat = 76
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                illustration
                    .padding(8)
                    .frame(height: illustrationHeight)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray5)))
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(layout.shortTitle).font(.subheadline.weight(.semibold))
                        if let detail { detail.font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppColor.purple : Color.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? AppColor.purple : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var illustration: some View {
        let rows = layout == .nineKey ? [4, 4, 4, 4] : [10, 9, 7, 5]
        return VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(.systemBackground))
                    }
                }
                .padding(.horizontal, layout == .qwerty && count < 10 ? CGFloat(10 - count) * 3 : 0)
            }
        }
    }
}

/// 「拼音显示」二选一卡片（F12，SM3）：上面画出拼音在哪（上方一行 / 左边一列），下面名称、说明和勾选圈。
private struct PinyinDisplayCard: View {
    var display: PinyinDisplay
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                illustration
                    .padding(8)
                    .frame(height: 76)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray5)))
                HStack {
                    Text(display.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppColor.purple : Color.secondary)
                }
                Text(display == .row
                     ? L("候选栏上面单独一行，和 iOS 原生一样", "A row above the candidates, like iOS", "候補の上に 1 行、iOS と同じ")
                     : L("九宫格在左边一列选，全键盘点左边的拼音键", "10-key: left column. QWERTY: pinyin key on the left", "10キーは左の列、QWERTY は左のピンインキー"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? AppColor.purple : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var illustration: some View {
        let accent = AppColor.purple.opacity(0.35)
        let key = RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(.systemBackground))
        return VStack(spacing: 3) {
            if display == .row {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(accent).frame(height: 8)
            }
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 3) {
                    if display == .side && row < 3 {
                        Color.clear
                    } else {
                        key
                    }
                    ForEach(0..<4, id: \.self) { _ in key }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if display == .side {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(accent)
                        .frame(width: (geo.size.width - 12) / 5, height: (geo.size.height - 9) / 4 * 3 + 6)
                }
            }
        }
    }
}

/// 「结果卡左边的按钮」二选一卡片（SET1、SET2）：上面画出键和结果卡的样子、往哪滑换成什么，下面名称和勾选圈。
private struct ResultKeyCard: View {
    var action: ResultKeyAction
    var settings: EnclaveSettings
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        miniKey
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(AppColor.purple.opacity(0.35), lineWidth: 1))
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Capsule().fill(AppColor.purple.opacity(0.18)).frame(height: 5)
                                    Capsule().fill(AppColor.purple.opacity(0.18)).frame(width: 40, height: 5)
                                }
                                .padding(8)
                            }
                    }
                    .frame(height: 44)
                    HStack(spacing: 3) {
                        Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .semibold))
                        Text(hint).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray5)))
                HStack {
                    Text(action.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppColor.purple : Color.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? AppColor.purple : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var pop: Bool { settings.resultKeySwipe == .pop }
    private var up: Bool { !pop && settings.resultKeyWheelUp }

    private var hint: String {
        let other = action.other.title
        if pop { return L("往下划：下方弹出\(other)", "Slide down: pop up \(other)", "下へ：\(other)") }
        return up ? L("往上滑：\(other)", "Slide up: \(other)", "上へ：\(other)")
                  : L("往下滑：\(other)", "Slide down: \(other)", "下へ：\(other)")
    }

    /// 缩小的键：主功能在正中，滚轮时另一个在边上露一点，弹出时下面一个 ▾。
    private var miniKey: some View {
        let colors: [Color] = action == .replace
            ? [Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255), Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)]
            : [Color(red: 0x0E / 255, green: 0x74 / 255, blue: 0x90 / 255), Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)]
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            label(action).offset(y: pop ? -4 : 0)
            if pop {
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.white).offset(y: 12)
            } else {
                label(action.other).opacity(0.5).blur(radius: 0.6).offset(y: up ? 17 : -17)
            }
        }
        .frame(width: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func label(_ action: ResultKeyAction) -> some View {
        HStack(spacing: 2) {
            Image(systemName: action.systemImage).font(.system(size: 8, weight: .bold))
            Text(action.title).font(.system(size: 10, weight: .bold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
    }
}

// MARK: - 模糊拼音

struct FuzzyPinyinView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared
    @State private var selection: Set<FuzzyPinyin> = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                NotSyncedBanner()
                header(L("快速选择", "Presets", "プリセット"))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([FuzzyPinyin.Preset.off, .retroflex, .nasal]) { presetChip($0) }
                    }
                    presetChip(.southern)
                }
                header(L("声母", "Initials", "声母"))
                grid(FuzzyPinyin.initials)
                header(L("韵母", "Finals", "韻母"))
                grid(FuzzyPinyin.finals)
                Text(L("例：开了 z = zh，打 zi 也会出「知」。开得越多，候选越杂，按自己的口音选几组就好。", "Example: with z = zh on, typing zi also gives 知. More pairs mean noisier candidates, so pick just the ones that match your accent.", "例：z = zh をオンにすると zi でも「知」が出ます。増やすほど候補が増えるので、なまりに合うものだけ選びましょう。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Button(deployer.state == .deploying ? L("正在部署…", "Installing…", "インストール中…") : L("应用并重新部署词库", "Apply and reinstall dictionary", "適用して辞書を再インストール")) {
                    store.settings.fuzzyPinyin = selection
                    deployer.deploy()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(deployer.state == .deploying || (selection == store.settings.fuzzyPinyin && !deployer.needsDeploy))
                .padding(.top, 8)
                Group {
                    if case .failed(let message) = deployer.state {
                        Text(message).foregroundStyle(.red)
                    } else if deployer.state == .done && selection == store.settings.fuzzyPinyin {
                        Text(L("已生效，切回键盘就能用。", "Done. Switch back to the keyboard to use it.", "反映されました。キーボードに戻ると使えます。")).foregroundStyle(.green)
                    } else {
                        Text(L("改动后要重新部署一次词库才生效，\(RimeDeployer.durationText)。", "Changes take effect after reinstalling the dictionary, \(RimeDeployer.durationText).", "変更は辞書の再インストール後に反映されます（\(RimeDeployer.durationText)）。")).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("模糊拼音", "Fuzzy pinyin", "あいまい入力"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            selection = store.settings.fuzzyPinyin
            loaded = true
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
    }

    private func presetChip(_ preset: FuzzyPinyin.Preset) -> some View {
        let on = selection == preset.groups
        return Button { selection = preset.groups } label: {
            Text(preset.title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(on ? AppColor.purple : Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private func grid(_ items: [FuzzyPinyin]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            ForEach(items) { item in
                let on = selection.contains(item)
                Button {
                    if on { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    HStack {
                        Text(item.title).font(.body.monospaced())
                            .foregroundStyle(on ? AppColor.purple : Color.primary)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? AppColor.purple : Color.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? AppColor.softFill : Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(on ? AppColor.purple : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 双拼

/// 双拼方案（KS2 ③，原「全键盘拼音」页）：只有「打法」选了双拼才进得来。全拼 / 双拼的切换在上一页。
/// 换方案马上重新部署词库（几秒），不用再点按钮；键上提示只是键盘的显示，不用部署。
struct DoublePinyinView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared
    /// 要分享的键位图（临时文件）；有值时弹系统分享面板。
    @State private var keymap: KeymapFile?

    var body: some View {
        Form {
            if KeyboardStatus.fullAccess == false {
                Section {
                } header: {
                    NotSyncedBanner()
                        .dashFormCard()
                }
            }
            if let current = store.settings.doublePinyin {
                // SP5：方案 → 键上提示 → 键盘预览 → 零声母 → 保存键位图 → 练习 → 输入。
                Section {
                    ForEach(DoublePinyin.allCases) { scheme in
                        Button { apply(scheme) } label: {
                            HStack {
                                Text(scheme.title).foregroundStyle(Color.primary)
                                Spacer()
                                if scheme == current {
                                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(AppColor.purple)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L("方案", "Scheme", "方式"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("换方案会重新部署词库，几秒钟。", "Changing the scheme reinstalls the dictionary, which takes a few seconds.",
                               "方式を変えると辞書を再インストールします（数秒）。"))
                        DictionaryDeployStatus()
                        // 键盘没开完全访问时读不到 App 的设置，也读不到双拼词库，照旧打全拼；键盘那边没法知道用户选了双拼，只能在这里说（双拼调研 P1）。
                        if KeyboardStatus.fullAccess != true {
                            Text(L("双拼要在键盘开了「允许完全访问」后才生效；没开时键盘照旧打全拼，键上也没有提示。",
                                   "Double pinyin works only after you turn on Allow Full Access for the keyboard. Until then the keyboard types full pinyin with no key hints.",
                                   "双拼はキーボードの「フルアクセスを許可」をオンにすると有効になります。オフのあいだは全拼で入力され、キーのヒントも表示されません。"))
                        }
                    }
                }
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("键上提示", "Key hints", "キーのヒント"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        Picker(L("键上提示", "Key hints", "キーのヒント"), selection: $store.settings.doublePinyinHintMode) {
                            ForEach(DoublePinyinHintMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .dashFormCard()
                } footer: {
                    Text(hintFooter)
                }
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("键盘里看起来", "On the keyboard", "キーボードでの表示"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        DoublePinyinPreview(scheme: current, mode: store.settings.doublePinyinHintMode)
                    }
                    .dashFormCard()
                } footer: {
                    Text(L("拼写栏照旧显示完整拼音（ni hao），旁边灰色小字是你按的键。不想用双拼：回上一页把「打法」换回全拼。",
                           "The pinyin row still shows the full pinyin (ni hao), with the keys you pressed in small gray text. To stop using double pinyin, go back and set Typing to Full.",
                           "ピンイン行には完全なピンイン（ni hao）が表示され、横に押したキーが小さな灰色で出ます。双拼をやめるには、前のページで「入力方式」を全拼に戻します。"))
                }
                Section {
                    ZeroInitialCard(scheme: current)
                }
                Section {
                    Button { shareKeymap(current) } label: {
                        Label(L("分享键位图", "Share layout image", "キー配置の画像を共有"), systemImage: "square.and.arrow.up")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppColor.purple)
                            .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(L("一张竖图，带整张键位和零声母，可以存到「文件」、打印或发给别人对照。",
                           "A tall image with the full layout and the no-initial syllables. Save it to Files, print it, or send it.",
                           "キー配置と声母のない音節をまとめた縦長の画像です。「ファイル」に保存したり、印刷したり、送ったりできます。"))
                }
                Section {
                    NavigationLink(value: AppRouter.KeyboardPage.doublePinyinPractice) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("双拼练习", "Practice", "双拼の練習"))
                                Text(L("基础 · 词组 · 短句，按错马上提示", "Basics · words · sentences, with instant feedback", "基礎・単語・短文、間違えるとすぐ表示"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DoublePinyinPracticeStore.summary)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("练习", "Practice", "練習"))
                }
                Section {
                    Toggle(isOn: mixFull) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("也认全拼", "Also accept full pinyin", "全拼も受け付ける"))
                            Text(L("双拼时打 zhangsan 这样的全拼也能出字", "Full pinyin like zhangsan also works in double pinyin", "双拼でも zhangsan のような全拼で入力できます"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("输入", "Input", "入力"))
                } footer: {
                    Text(L("默认关。三个字母以上的全拼常和双拼撞车（比如 shi 会被当成「sang + i」），开了以后候选可能变乱。只是偶尔想打全拼，点拼写栏里的全拼就能上屏字母。",
                           "Off by default. Full pinyin of three or more letters often clashes with double pinyin (shi reads as sang + i), so candidates may get messy. To type pinyin letters once in a while, tap the pinyin in the pinyin row.",
                           "初期設定はオフ。3 文字以上の全拼は双拼とぶつかりやすく（shi が「sang + i」と読まれるなど）、オンにすると候補が乱れることがあります。たまに全拼を入れたいだけなら、ピンイン行のピンインをタップすると文字のまま入力できます。"))
                }
            }
        }
        .sheet(item: $keymap) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .navigationTitle(L("双拼方案", "Double pinyin scheme", "双拼の方式"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 键上提示的脚注随档位变（SP5）。
    private var hintFooter: String {
        switch store.settings.doublePinyinHintMode {
        case .off:
            return L("键上不写字，和全拼一样。", "Keys show only letters, like full pinyin.", "キーには文字だけを表示します（全拼と同じ）。")
        case .fixed:
            return L("每个键上一直写着它的韵母和 zh / ch / sh，熟练以后可以关掉。",
                     "Each key always shows its finals and zh / ch / sh. Turn them off once you know the layout.",
                     "各キーに韻母と zh / ch / sh を常に表示します。慣れたらオフにできます。")
        case .dynamic:
            return L("该按声母时只写 zh / ch / sh；按完声母，每个键只写能和它拼上的韵母，拼不上的键变淡。",
                     "Before an initial, only zh / ch / sh are shown. After an initial, each key shows only the final that fits, and keys that don't fit fade.",
                     "声母の前は zh / ch / sh だけを表示。声母を押すと、各キーには組み合わせられる韻母だけを表示し、合わないキーは薄くなります。")
        }
    }

    /// 当前方案、当前深浅色的键位图（SP8）写成临时 PNG，弹系统分享面板（存到文件、打印、隔空投送）。
    /// 不直接存相册：那要申请照片权限，分享面板里也去掉了「存储图像」。
    private func shareKeymap(_ scheme: DoublePinyin) {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        guard let image = DoublePinyinKeymapPoster.render(scheme: scheme, dark: dark), let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(L("\(scheme.title)键位图", "\(scheme.title) layout", "\(scheme.title) キー配置") + ".png")
        do { try data.write(to: url, options: .atomic) } catch { return }
        keymap = KeymapFile(url: url)
    }

    /// 也能打全拼：和换方案一样要重新部署。
    private var mixFull: Binding<Bool> {
        Binding(get: { store.settings.doublePinyinMixFull },
                set: { value in
                    guard value != store.settings.doublePinyinMixFull else { return }
                    store.settings.doublePinyinMixFull = value
                    deployer.deploy()
                })
    }

    private func apply(_ scheme: DoublePinyin) {
        DoublePinyin.lastChosen = scheme
        guard scheme != store.settings.doublePinyin else { return }
        store.settings.doublePinyin = scheme
        deployer.deploy()
    }
}

extension DoublePinyin {
    /// 最近选的双拼方案：「打法」切回全拼再切双拼时还是它（App 自己的 UserDefaults）。
    static var lastChosen: DoublePinyin {
        get { UserDefaults.standard.string(forKey: "doublePinyin.lastScheme").flatMap(DoublePinyin.init(rawValue:)) ?? .flypy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "doublePinyin.lastScheme") }
    }
}

/// 换了打法或双拼方案要重新部署词库：部署中、失败时在脚注里说一句；需要重新部署时给个按钮。
struct DictionaryDeployStatus: View {
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        switch deployer.state {
        case .deploying:
            Text(L("正在重新部署词库，\(RimeDeployer.durationText)…", "Reinstalling the dictionary, \(RimeDeployer.durationText)…", "辞書を再インストールしています（\(RimeDeployer.durationText)）…"))
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        default:
            if deployer.needsDeploy {
                Button(L("重新部署词库", "Reinstall dictionary", "辞書を再インストール")) { deployer.deploy() }
                    .font(.footnote)
            }
        }
    }
}

/// 设置页里的键盘预览：和键盘里一样的提示样式（SP2 A：韵母小字在字母上方居中，zh/ch/sh 紫色在第一行）。
/// 跟着档位变（SP5）：关时只有字母，跟着按键变时是「该按声母」的样子（只有 zh / ch / sh）。
private struct DoublePinyinPreview: View {
    let scheme: DoublePinyin
    let mode: DoublePinyinHintMode
    private var hints: Bool { mode != .off }
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 5) {
                    if row.count == 7 { key(Image(systemName: "shift")).frame(width: 34) }
                    ForEach(Array(row), id: \.self) { letter in
                        letterKey(letter).frame(maxWidth: .infinity)
                    }
                    if row.count == 7 { key(Image(systemName: "delete.left")).frame(width: 34) }
                }
                .padding(.horizontal, row.count == 9 ? 14 : 0)
            }
            HStack(spacing: 5) {
                key(Text("123")).frame(width: 40)
                key(Text("中/英")).frame(width: 40)
                key(Text(L("空格", "space", "空白"))).frame(maxWidth: .infinity)
                key(Text(L("执行", "go", "実行")).foregroundStyle(.white), fill: AppColor.purple).frame(width: 80)
            }
            .font(.system(size: 14))
        }
        .frame(height: 196)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray4)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(scheme.title)键盘预览", "\(scheme.title) keyboard preview", "\(scheme.title) のキーボードのプレビュー"))
    }

    private func letterKey(_ letter: Character) -> some View {
        // 开着提示时每个键都按「小字 + 贴下边的字母」排，没有小字的键（a、e）上面空着，和键盘里一样。
        let lines = scheme.hints(for: mode == .dynamic ? .initial : .all)[letter] ?? []
        return ZStack {
            if !hints {
                Text(String(letter)).font(.system(size: 19))
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(lines, id: \.self) { line in
                            let initial = ["zh", "ch", "sh"].contains(line)
                            Text(line)
                                .font(.system(size: 7, weight: initial ? .bold : .medium))
                                .foregroundStyle(initial ? AppColor.purple : Color.secondary)
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    Text(String(letter)).font(.system(size: 17)).padding(.bottom, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.systemBackground)))
    }

    private func key(_ content: some View, fill: Color = Color(.systemBackground)) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}

// MARK: - 拼音词库

struct PinyinView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared
    @State private var size: Int64?
    @ObservedObject private var grammar = GrammarDownloader.shared
    @State private var confirmDeleteGrammar = false
    /// 整句模型的下载地址，空着就用默认地址（大陆店面 enclavekb.cn，其他 GitHub）。
    @State private var grammarURL = GrammarModel.customDownloadURL ?? ""
    /// 下载地址框平时收起；填过自定义地址或下载失败过就直接展开。
    @State private var showsGrammarURL = GrammarModel.customDownloadURL != nil

    /// 上面三张卡照旧；下面是扩展词库的概况两行（第 49 条），点进热门词库、导入的词库。
    var body: some View {
        List {
            Section {} header: {
                VStack(spacing: 12) {
                    dictionaryCard
                    grammarCard
                    englishCard
                }
                .dashFormCard()
            }
            ExtDictOverviewSection()
        }
        .navigationTitle(L("词库", "Dictionaries", "辞書"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deployer.state) {
            size = await Task.detached { RimeDeployer.diskSize() }.value
        }
        .onAppear {
            grammar.refresh()
        }
        .confirmationDialog(L("删除整句模型？", "Delete the sentence model?", "文章モデルを削除しますか？"), isPresented: $confirmDeleteGrammar, titleVisibility: .visible) {
            Button(L("删除", "Delete", "削除"), role: .destructive) { grammar.delete() }
        }
    }

    // MARK: - 万象拼音

    private var dictionaryCard: some View {
        let status = PinyinStatus.current(deployer)
        return DashCard {
            DashCardHeader(icon: "character.book.closed", title: L("万象拼音", "Wanxiang Pinyin", "万象ピンイン"), color: DashColor.input)
            VStack(alignment: .leading, spacing: 8) {
                Text("● " + status.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(status.color)
                Text(L("在本机编译，键盘要开「允许完全访问」才能读到。", "Built on this iPhone. The keyboard needs Allow Full Access to read it.", "この iPhone 上で作成します。キーボードが読むには「フルアクセスを許可」が必要です。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                if case .failed(let message) = deployer.state {
                    Text(message).font(.system(size: 13)).foregroundStyle(.red)
                }
                HStack(spacing: 8) {
                    Button(deployer.state == .deploying ? L("正在部署…", "Installing…", "インストール中…") : L("重新部署词库", "Reinstall dictionary", "辞書を再インストール")) { deployer.deploy() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(deployer.state == .deploying)
                    if deployer.state == .deploying { ProgressView() }
                }
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let date = RimeDeployer.deployedAt, !deployer.needsDeploy {
            parts.append(L("\(Loc.monthDay(date)) 部署", "Installed \(Loc.monthDay(date))", "\(Loc.monthDay(date))にインストール"))
        }
        if let size, size > 0 {
            parts.append(L("约 ", "About ", "約 ") + ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if !store.settings.fuzzyPinyin.isEmpty {
            parts.append(L("模糊拼音 \(store.settings.fuzzyPinyin.count) 组", "\(store.settings.fuzzyPinyin.count) fuzzy pairs", "あいまい入力 \(store.settings.fuzzyPinyin.count) 組"))
        }
        return parts.isEmpty ? L("万象拼音词库，CC BY 4.0", "Wanxiang Pinyin, CC BY 4.0", "万象ピンイン、CC BY 4.0") : parts.joined(separator: " · ")
    }

    // MARK: - 整句模型

    /// 下载后整句首选更准。下载中大数字是进度，下完是大小。
    private var grammarCard: some View {
        DashCard {
            DashCardHeader(icon: "sparkles", title: L("整句模型", "Sentence model", "文章モデル"), color: DashColor.input, note: "CC BY 4.0")
            VStack(alignment: .leading, spacing: 10) {
                switch grammar.state {
                case .downloading(let received, let expected):
                    DashBigNumber(value: "\(Int(Double(received) / Double(max(expected, 1)) * 100))",
                                    unit: L("% · 正在下载", "% · Downloading", "% · ダウンロード中"))
                    ProgressView(value: Double(received), total: Double(max(expected, 1)))
                    Button(L("取消", "Cancel", "キャンセル")) { grammar.cancel() }
                        .font(.system(size: 15, weight: .semibold))
                default:
                    if GrammarModel.isBundled {
                        // 内测包自带：只能停用，不能删、不用下载。
                        DashBigNumber(value: GrammarModel.installedSize.map { "\($0 / 1_000_000)" } ?? "380",
                                        unit: grammar.enabled ? L("MB · 已内置", "MB · Built in", "MB · 内蔵") : L("MB · 已内置 · 已停用", "MB · Built in · Off", "MB · 内蔵 · オフ"))
                        Toggle(L("使用整句模型", "Use sentence model", "文章モデルを使う"),
                               isOn: Binding(get: { grammar.enabled }, set: { grammar.setEnabled($0) }))
                            .tint(AppColor.purple)
                            .disabled(deployer.state == .deploying)
                        Text(L("内测版已自带整句模型，不用下载，也不能删除；不想用可以停用。",
                               "The beta comes with the sentence model built in. It can't be deleted, but you can turn it off.",
                               "ベータ版には文章モデルが内蔵されています。削除はできませんが、オフにできます。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    } else if grammar.installed {
                        DashBigNumber(value: GrammarModel.installedSize.map { "\($0 / 1_000_000)" } ?? "–",
                                        unit: grammar.enabled ? L("MB · 已下载", "MB · Downloaded", "MB · ダウンロード済み") : L("MB · 已下载 · 已关闭", "MB · Downloaded · Off", "MB · ダウンロード済み · オフ"))
                        // 关掉时模型留着，随时再打开，方便对比。切换后重新部署词库。
                        Toggle(L("使用整句模型", "Use sentence model", "文章モデルを使う"),
                               isOn: Binding(get: { grammar.enabled }, set: { grammar.setEnabled($0) }))
                            .tint(AppColor.purple)
                            .disabled(deployer.state == .deploying)
                        Text(L("长句一次打对的更多，键盘内存会多用一些。", "Whole sentences come out right more often; the keyboard uses a little more memory.", "長い文が一度で正しく出やすくなります。キーボードのメモリ使用は少し増えます。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(L("删除模型", "Delete model", "モデルを削除"), role: .destructive) { confirmDeleteGrammar = true }
                            .font(.system(size: 13, weight: .semibold))
                            .disabled(deployer.state == .deploying)
                    } else {
                        DashBigNumber(value: "380", unit: L("MB · 未下载", "MB · Not downloaded", "MB · 未ダウンロード"))
                        Text(L("按词和词常在一起出现的统计挑出最通顺的整句，整句打完首选更准。完全在本机运行，不联网。\(Storefront.isMainlandChina ? "默认从飞地的国内服务器下载" : "默认从万象的 GitHub 下载")，断了会自动重试、接着下。",
                               "Picks the most natural sentence from statistics of which words go together, so whole sentences come out right more often. Runs fully on this iPhone, offline. Downloaded from \(Storefront.isMainlandChina ? "Enclave's server in mainland China" : "Wanxiang's GitHub") by default; if the connection drops it retries and picks up where it left off.",
                               "語と語のつながりの統計から自然な文を選ぶので、文をまとめて入力したときの第一候補が正確になります。すべて端末内で動作し、通信しません。デフォルトでは\(Storefront.isMainlandChina ? "Enclave の中国国内サーバー" : "万象の GitHub")からダウンロードし、途切れたら自動で再試行して続きから再開します。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(grammar.canResume ? L("继续下载", "Resume download", "続きから") : L("下载", "Download", "ダウンロード")) { grammar.download() }
                            .font(.system(size: 15, weight: .semibold))
                            .disabled(deployer.state == .deploying)
                        grammarURLField
                    }
                }
                if case .failed(let message) = grammar.state {
                    Text(message).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
        }
    }

    /// 下载地址：GitHub 在大陆常常很慢或打不开，可以换成镜像或自己的服务器。改了地址旧进度作废。
    @ViewBuilder
    private var grammarURLField: some View {
        if showsGrammarURL || isGrammarFailed {
            grammarURLEditor
        } else {
            Button(L("下载太慢？换个下载地址", "Slow? Use another download address", "遅いときは別のアドレスへ")) { showsGrammarURL = true }
                .font(.system(size: 13))
                .foregroundStyle(AppColor.purple)
                .buttonStyle(.plain)
        }
    }

    private var isGrammarFailed: Bool {
        if case .failed = grammar.state { return true }
        return false
    }

    private var grammarURLEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("下载地址", "Download address", "ダウンロード元")).font(.system(size: 13, weight: .semibold))
            TextField(GrammarModel.defaultDownloadURL(mainland: Storefront.isMainlandChina).absoluteString, text: $grammarURL)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
                .onSubmit { saveGrammarURL() }
                .onChange(of: grammarURL) { _ in saveGrammarURL() }
            Text(L("空着就用上面灰字的默认地址。下不动时可以换成镜像地址，文件要是同一个 .gram。",
                   "Leave empty to use the default address shown in gray. If it's too slow, use a mirror of the same .gram file.",
                   "空欄なら灰色の既定のアドレスを使います。遅いときは同じ .gram ファイルのミラーを指定できます。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func saveGrammarURL() {
        let old = GrammarModel.downloadURL(mainland: Storefront.isMainlandChina)
        GrammarModel.customDownloadURL = grammarURL
        if GrammarModel.downloadURL(mainland: Storefront.isMainlandChina) != old { grammar.discardProgress() }
    }

    // MARK: - 英文词库

    /// 英文单词表和联想数据随键盘内置，不用下载，这里只能开关。
    private var englishCard: some View {
        DashCard {
            DashCardHeader(icon: "textformat.abc", title: L("英文词库", "English words", "英語辞書"), color: DashColor.input, note: L("已内置", "Built in", "内蔵"))
            DashBigNumber(value: L("6 万", "60k", "6 万"), unit: L("个单词 · 1.6 MB", "words · 1.6 MB", "語 · 1.6 MB"))
            // 开关只在 键盘 › 英文 一处（存储同一个 prediction.english）。
            Text(L("在 键盘 › 英文 里开关", "Turn it on or off in Keyboard › English", "キーボード › 英語 でオン・オフ"))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(L("英文状态下打字时补全单词（tomo → tomorrow），打完一个词接着推荐下一个。单词表来自万象拼音（CC BY 4.0），词组搭配来自 Tatoeba 例句（CC BY 2.0 FR）。",
                   "Completes words as you type in English (tomo → tomorrow) and suggests the next word. Word list from Wanxiang Pinyin (CC BY 4.0); word pairs from Tatoeba sentences (CC BY 2.0 FR).",
                   "英語入力中に単語を補完し（tomo → tomorrow）、次の単語を予測します。単語リストは万象ピンイン（CC BY 4.0）、語のつながりは Tatoeba の例文（CC BY 2.0 FR）から。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

}

/// 测试工具 › 打字速度（原词库页底部那张卡，内容不变）。
struct TypingSpeedCard: View {
    @State private var typingStats = TypingStats.summary

    var body: some View {
        DashCard {
            DashCardHeader(icon: "keyboard", title: L("打字速度", "Typing speed", "入力の速さ"), color: DashColor.input,
                           note: typingStats.map { L("最近 \($0.count) 个按键", "Last \($0.count) keys", "直近 \($0.count) キー") })
            if let stats = typingStats {
                VStack(alignment: .leading, spacing: 12) {
                    let smooth = stats.medianTotal <= 30
                    HStack(alignment: .firstTextBaseline) {
                        DashBigNumber(value: String(format: "%.0f", stats.medianTotal), unit: L("毫秒 · 一般", "ms · typical", "ミリ秒 · 通常"))
                        Spacer()
                        Text(smooth ? L("感觉不到卡", "Feels instant", "遅れを感じない") : L("有点卡", "A bit slow", "少し遅い"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(smooth ? DashColor.ok : Color.orange)
                    }
                    LatencyScale(typical: stats.medianTotal, slow: stats.slowTotal, slowest: stats.slowestTotal)
                    HStack(alignment: .top) {
                        TypingSmallStat(value: Self.milliseconds(stats.medianEngine), label: L("其中拼音引擎", "Pinyin engine", "うちエンジン"))
                        if let memory = stats.memoryWithModel ?? stats.memory {
                            TypingSmallStat(value: String(format: "%.0f/%.0f", memory.median, memory.peak),
                                            label: L("内存 MB 一般/最高", "Memory MB typ/peak", "メモリ MB 通常/最大"))
                        }
                        TypingSmallStat(value: "\(stats.memoryWarnings)", label: L("内存警告", "Memory warnings", "メモリ警告"))
                    }
                    if let launch = stats.launch {
                        HStack(alignment: .top) {
                            TypingSmallStat(value: Self.milliseconds(launch.appear),
                                            label: L("冷启动到弹出", "Cold start to shown", "コールド起動→表示"))
                            TypingSmallStat(value: Self.milliseconds(launch.ready),
                                            label: L("冷启动到能打拼音", "Cold start to pinyin ready", "コールド起動→入力可"))
                            TypingSmallStat(value: "\(launch.count)", label: L("冷启动次数", "Cold starts", "コールド起動回数"))
                        }
                    }
                    HStack(spacing: 4) {
                        Text(L("从手指离开按键到候选出来。30 毫秒以内基本感觉不到。", "From lifting your finger to candidates shown. Under 30 ms feels instant.", "指を離してから候補が出るまで。30 ミリ秒以内ならほぼ感じません。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(L("清空记录", "Clear", "記録を消去")) {
                            TypingStats.clear()
                            typingStats = nil
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    DashBigNumber(value: "0", unit: L("个按键", "keys", "キー"))
                    Text(L("用飞地输入法打几个拼音，这里就有数据了。键盘要开「允许完全访问」才记得下。", "Type some pinyin with the Enclave keyboard and your stats show up here. The keyboard needs Allow Full Access to record them.", "Enclave キーボードでピンインを入力すると、ここに記録が表示されます。「フルアクセスを許可」が必要です。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }
}

/// 从绿到红的刻度条，标出一般、较慢 10%、最慢三个位置。刻度到 100ms，更慢的贴着最右边。
private struct LatencyScale: View {
    var typical: Double
    var slow: Double
    var slowest: Double
    private let maxValue = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [DashColor.ok, .yellow, Color.orange, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle().fill(Color.primary).frame(width: 2, height: 16)
                            .offset(x: position([typical, slow, slowest][index], width) - 1)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            // 三个值常挤在一起，标签不贴着刻度，排成一行写在下面。
            HStack(spacing: 12) {
                legend(L("一般", "Typical", "通常"), typical)
                legend(L("较慢 10%", "Slow 10%", "遅い10%"), slow)
                legend(L("最慢", "Slowest", "最大"), slowest)
            }
        }
    }

    private func position(_ value: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(value / maxValue, 0), 1)) * width
    }

    private func legend(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", value)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
    }
}

// MARK: - 隐私、关于

/// 语言（L2）：跟随 iPhone / 简体中文 / English / 日本語，选完马上生效；下面一组说明会改哪些。
struct LanguageView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button { router.language = language } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.nativeName).foregroundStyle(.primary)
                                if language == .system {
                                    Text(L("现在是\(Loc.system.nativeName)", "Currently \(Loc.system.nativeName)",
                                           "現在は\(Loc.system.nativeName)"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if router.language == language {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color(hex: 0x5B4BE8))
                            }
                        }
                    }
                }
            }
            Section(L("会改哪些", "What changes", "変わるもの")) {
                LabeledContent(L("App 界面、键盘里的 AI 文字", "App and keyboard AI text", "アプリとキーボードの AI 表示"),
                               value: L("跟这里一致", "Follow this setting", "この設定に合わせる"))
                LabeledContent(L("拼音按键", "Pinyin keys", "ピンインのキー"), value: L("一直是中文", "Always Chinese", "常に中国語"))
                LabeledContent(L("润色结果", "Polish results", "整えた結果"), value: L("不受影响", "Not affected", "影響なし"))
            }
        }
        .navigationTitle(L("语言", "Language", "言語"))
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// 保存接口时的确认（P05）：「同意」记下这个地址，键盘里第一次润色就不再问；「暂不」什么都不记。
struct ConsentSheet: View {
    let provider: String
    let endpoint: String
    let agree: () -> Void
    let later: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x5B4BE8))
                    .padding(.top, 28)
                Text(L("允许把文字发送到这个接口？", "Allow sending text to this API?", "この API に文章を送信しますか？"))
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                VStack(spacing: 0) {
                    row(L("服务商", "Provider", "サービス"), provider)
                    Divider().padding(.leading, 14)
                    row(L("地址", "Address", "アドレス"), endpoint, mono: true)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                VStack(alignment: .leading, spacing: 14) {
                    point("text.alignleft", L("发送什么", "What's sent", "送るもの"),
                          L("只在你点「润色」或「再润」时，发送输入框里的文字（选中时只发选中的部分）和你写的要求。",
                            "Only when you tap Polish or Rewrite: the text in the field (just the selection, if any) and your prompt.",
                            "「整える」か「別の案」をタップしたときだけ、入力欄の文章（選択時はその部分だけ）と指示を送ります。"))
                    point("arrow.up.forward", L("发到哪里", "Where it goes", "送り先"),
                          L("直接发到上面这个地址，由服务商按它的隐私政策处理。", "Straight to the address above, handled under the provider's privacy policy.",
                            "上のアドレスに直接送られ、サービスのプライバシーポリシーに従って処理されます。"))
                    point("lock.shield", L("飞地输入法不经手", "Enclave never sees it", "Enclave は関与しません"),
                          L("无第三方中转，守护数据隐私：你的文字直接发给你选的服务商，飞地输入法不收集、不保存。", "No third-party relay. Your text goes straight to the provider you chose; Enclave never collects or keeps it.",
                            "第三者の中継なし。文章は選んだサービスへ直接送られ、Enclave は収集・保存しません。"))
                }
                Button(action: agree) {
                    Text(L("同意", "Allow", "同意する"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x5B4BE8)))
                }
                .buttonStyle(.plain)
                Button(L("暂不", "Not now", "今はしない"), action: later)
                    .font(.system(size: 16))
                Text(L("可以随时在「设置 › 隐私」撤回", "You can withdraw anytime in Settings › Privacy", "「設定 › プライバシー」でいつでも撤回できます"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(mono ? .system(.subheadline, design: .monospaced) : .subheadline).lineLimit(1).truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x4A3BD6))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(hex: 0xECEAFD)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
