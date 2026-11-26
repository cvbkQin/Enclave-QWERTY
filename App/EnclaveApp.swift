import StoreKit
import SwiftUI

@main
struct EnclaveApp: App {
    /// 只为 iCloud 同步的后台任务注册和静默推送（App/Sync/ICloudSyncScheduler.swift）。
    @UIApplicationDelegateAdaptor(EnclaveAppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared
    @StateObject private var store = AppStore()

    init() {
        // 内测版：收崩溃、卡死记录，只存本机。
        CrashLog.shared.start(source: "app")
        // 上次备份 / 恢复做到一半被杀时留下的词库副本，启动时清掉（后台做）。
        LearnedWords.cleanUpLeftovers()
        #if DEBUG
        // 模拟器截图用：-keyboardDebug "expanded,nine,compose:nihao" 让键盘直接显示某个状态。
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-keyboardDebug"), args.indices.contains(index + 1) {
            SharedStorage.defaults.set(args[index + 1], forKey: KeyboardDebug.key)
        } else {
            SharedStorage.defaults.removeObject(forKey: KeyboardDebug.key)
        }
        // 测试常用词：-commonWords "张三丰,me@example.com=yx" 写入几个词（= 后面是编码，不写就按拼音）。
        if let index = args.firstIndex(of: "-commonWords"), args.indices.contains(index + 1) {
            CommonWordStore.save(args[index + 1].split(separator: ",").map { item in
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                return CommonWord(text: parts[0], pinyin: CommonWordStore.pinyin(of: parts[0]),
                                  shortcut: parts.count > 1 ? parts[1] : "")
            })
        }
        // -promptsDebug missing / empty / optimized：提示词页截图（删掉两条预设、空提示词的编辑页、AI 优化结果）。
        if let index = args.firstIndex(of: "-promptsDebug"), args.indices.contains(index + 1) {
            PromptsDebug.scene = args[index + 1]
            AppRouter.shared.openAI(prompts: true)
        }
        // -storefront CHN：按中国大陆店面显示（接口页服务商）。
        if let index = args.firstIndex(of: "-storefront"), args.indices.contains(index + 1) {
            Storefront.debugOverride(args[index + 1])
        }
        // -keyboardWords "张三丰,me@example.com" 写进键盘常用语。
        if let index = args.firstIndex(of: "-keyboardWords"), args.indices.contains(index + 1) {
            CommonWordStore.keyboardTexts = args[index + 1].split(separator: ",").map(String.init)
        }
        // -keyboardPhrases "公司地址|北京市海淀区中关村大街 1 号|gsdz;好的" 写进键盘常用语（标题|内容|简码，分号隔开）。
        if let index = args.firstIndex(of: "-keyboardPhrases"), args.indices.contains(index + 1) {
            CommonWordStore.keyboardPhrases = args[index + 1].split(separator: ";").map { item in
                let parts = item.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                if parts.count == 1 { return KeyboardPhrase(text: parts[0]) }
                return KeyboardPhrase(title: parts[0], text: parts[1], shortcut: parts.count > 2 ? parts[2] : "")
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(store)
                // 输入时收起键盘：往下拖列表跟着收起，点输入框以外的地方也收起（KeyboardDismiss）。
                .scrollDismissesKeyboard(.interactively)
                // 单行输入框回车键写「完成」，点了收起；多行的各自改回换行（.submitLabel(.return)）。
                .submitLabel(.done)
                .onAppear { KeyboardDismiss.shared.install() }
                .task { RimeDeployer.shared.deployIfNeeded() }
                .task { WelcomeSetup.migrate(configured: store.settings.isConfigured) }
                .task { await UnlockStore.shared.refresh() }
                .task {
                    await Storefront.refreshCountry()
                    // 识意问答联网没选过：按店面定下来，中国大陆默认禁止，其他地区默认开。
                    if store.settings.webSearchMode == nil { store.settings.webSearchMode = Storefront.isMainlandChina ? .off : .on }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 键盘里改的设置（iPad 9 键换边、长按中/英换布局）存在共用设置里：回到前台重读一次（第 86 条）。
                    store.reloadSettings()
                    Task { await UnlockStore.shared.refresh() }
                    // iCloud 同步（关着时什么都不做）：打开 App、回到前台时同步一次，一分钟内回来多次只算一次。
                    Task { await ICloudSync.syncNow(minimumInterval: 60) }
                    // 后台下好的词库、整句模型回到前台再部署；热门词库满 7 天自动查一次更新（第 99 条）。
                    RimeDeployer.shared.deployIfNeeded()
                    DictAutoUpdate.shared.checkIfDue()
                    GrammarDownloader.shared.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    ICloudSyncScheduler.schedule()
                    DictUpdateScheduler.schedule()
                }
                .onOpenURL { url in
                    // 点开 .enclave 备份文件：到设置 › 备份与恢复，弹恢复面板。
                    if url.isFileURL, url.pathExtension.lowercased() == BackupService.fileExtension {
                        router.openedBackup = url
                        router.openSettings(.backup)
                        return
                    }
                    // enclave://playground 直接打开打字板并弹出键盘，方便在模拟器里截图测试。
                    guard url.scheme == "enclave" else { return }
                    switch url.host {
                    case "playground": router.openPlayground()
                    // 键盘「去开启」：先回到 App，再直接跳到系统设置里的 Enclave。
                    case "fullaccess":
                        // 冷启动时界面还没起来，稍等一下再跳，不然系统会忽略这次打开。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if let settings = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settings)
                            }
                        }
                    // 键盘出错卡的「去设置」：AI › 接口，进润色接口详情。
                    case "api":
                        router.openAI(detail: true, sharedAnswer: !store.settings.separateAnswer)
                    // 键盘里要联网但已禁止时的「去开启」：AI › 接口，滚到「联网搜索」。
                    case "api-answer":
                        router.openAI()
                        router.showsAnswerWebSearch = true
                    case "privacy-policy":
                        router.settingsPath = [.privacy, .privacyPolicy]
                        router.tab = .settings
                    // 键盘提示卡「去解锁」。
                    case "unlock": router.openSettings(.unlock)
                    // AI › 提示词（问答风格那一栏用 prompts-answer）。
                    case "prompts", "prompts-answer":
                        router.openAI(prompts: true, answerStyles: url.host == "prompts-answer")
                    case "common-words":
                        router.openKeyboard(.commonWords)
                    case "history":
                        router.historyPath = NavigationPath()
                        router.tab = .history
                    // 测试 iCloud 同步用（界面等 02 的稿子，做好后删掉）：enclave://icloud-sync/on、/off、/now、/keys-on、/keys-off。
                    // 只在 Debug 和开发者版装机里认，TestFlight 和正式版不认：打开同步要经过用户在界面上确认。
                    case "icloud-sync" where ICloudSyncDebug.isAllowed:
                        ICloudSyncDebug.handle(url.path)
                    default: break
                    }
                }
        }
    }
}

/// 底部五个标签：首页、接口和提示词、历史、键盘、设置。
/// iPad 宽屏（横向 regular：全屏、半屏）六个标签，接口和提示词分开（PA1 ③）；窄到 iPhone 那么宽时回到五个。
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var wide: Bool { UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular }

    var body: some View {
        tabs
            // 打开「自动保存复制的内容」的确认卡（CA4，每次从关拨到开都弹）：屏幕中间，盖住整个 App 包括标签栏。
            .overlay { AutoSaveConsentHost() }
            .onAppear { router.setWideLayout(wide) }
            .onChange(of: wide) { router.setWideLayout($0) }
            // 首次打开先看隐私说明（CP1），不能下滑关掉。iPad 宽屏时是居中的表单窗口（PA4 ⑦）。
            .padCover(isPresented: $router.showsPrivacyWelcome, wide: wide, onDismiss: {
                router.showSetupGuideIfNeeded(configured: store.settings.isConfigured)
            }) {
                PrivacyWelcomeView()
                    .environmentObject(router)
                    .environment(\.locale, Loc.locale)
            }
            // 连上 AI 接口的引导（OB1–OB7）。
            .padCover(item: $router.setupGuide, wide: wide) { start in
                SetupGuideView(start: start)
                    .environmentObject(router)
                    .environmentObject(store)
                    .environment(\.locale, Loc.locale)
            }
            .onAppear {
                // 之前已经同意过隐私政策、但还没走过引导的（老用户没配接口）。
                if !router.showsPrivacyWelcome { router.showSetupGuideIfNeeded(configured: store.settings.isConfigured) }
            }
            // 语言变了整棵视图按新语言重画；页面路径存在 router 里，不会回到首页。
            .id(router.language)
            .environment(\.locale, Loc.locale)
            .onAppear { applyAppearance(store.settings.appearance) }
            .onChange(of: store.settings.appearance) { applyAppearance($0) }
    }

    /// 日间 / 夜间设在窗口上，弹出的页面和系统控件跟着一起变；选回「跟随系统」也能马上还原。
    private func applyAppearance(_ appearance: Appearance) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = appearance.style }
        }
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label(L("首页", "Home", "ホーム"), systemImage: "house") }
                .tag(AppRouter.Tab.home)
            // 顺序（R0，11-22）：首页 / 接口和提示词 / 历史 / 键盘 / 设置，常用的放左边，键盘设置装好后很少再动。
            if router.wideLayout {
                // iPad 宽屏：接口、提示词各一个标签（11-22 cvbk「ipad空间足够，接口和提示词可以做成2个页面」）。
                AITab(segment: .api)
                    .tabItem { Label(L("接口", "API", "API"), systemImage: "text.bubble") }
                    .tag(AppRouter.Tab.ai)
                PromptsSplitView()
                    .tabItem { Label(L("提示词", "Prompts", "プロンプト"), systemImage: "text.quote") }
                    .tag(AppRouter.Tab.prompts)
            } else {
                AITab()
                    .tabItem { Label(AppRouter.aiTabTitle, systemImage: "text.bubble") }
                    .tag(AppRouter.Tab.ai)
            }
            HistoryTab()
                .tabItem { Label(L("历史", "History", "履歴"), systemImage: "clock") }
                .tag(AppRouter.Tab.history)
            KeyboardTab()
                .tabItem { Label(L("键盘", "Keyboard", "キーボード"), systemImage: "keyboard") }
                .tag(AppRouter.Tab.keyboard)
            SettingsView()
                .tabItem { Label(L("设置", "Settings", "設定"), systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .padTabStyle()
    }
}

/// 页面跳转：标签、设置里的子页面，以及从链接或启动参数直接打开某个页面。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// prompts 只在 iPad 宽屏时有（接口、提示词分两个标签）；窄屏时提示词在 ai 标签的「提示词」分段里。
    enum Tab: Hashable { case home, keyboard, ai, prompts, history, settings }

    /// iPad 宽屏（横向 regular）：六个标签，提示词、历史、设置左右两栏（PA1–PA4）。RootView 按尺寸类设。
    @Published private(set) var wideLayout = false

    /// 宽窄切换时标签对上：宽屏「提示词」标签 ↔ 窄屏「接口和提示词」的提示词分段；
    /// 设置、历史两栏右边打开的那一页，变窄后就是一列里推进去的那一页（路径是同一份）。
    func setWideLayout(_ wide: Bool) {
        guard wide != wideLayout else { return }
        wideLayout = wide
        if wide, tab == .ai, aiSegment == .prompts {
            tab = .prompts
        } else if !wide, tab == .prompts {
            aiSegment = .prompts
            tab = .ai
        }
        if !wide, let id = historySelection {
            // 窄屏时详情在一列里往里推一页。
            var path = NavigationPath()
            path.append(HistoryPage.detail(id))
            historyPath = path
        }
        historySelection = nil
    }

    /// 历史两栏（PA2 ④）右边正在看的那条；窄屏时不用（详情推进 historyPath）。
    @Published var historySelection: String?

    /// 打开一条历史记录：宽屏换右边，窄屏往里推一页。
    func openHistory(_ id: String) {
        if wideLayout {
            historySelection = id
            historyPath = NavigationPath()
        } else {
            historyPath.append(HistoryPage.detail(id))
        }
    }

    /// 原来的「AI」标签（R0，11-22 改名）：接口和提示词两件事放在一个标签里。
    static var aiTabTitle: String { L("接口和提示词", "API & Prompts", "API とプロンプト") }

    /// 设置里的二级页。setup：首次设置（欢迎页四步）；scratchPad：打字板（enclave://playground，设置里没有入口）。
    enum SettingsPage: String, Hashable {
        case setup, scratchPad, privacy, about, unlock, language, privacyPolicy, licenses, diagnostics, feedback, testTools, backup, tour
    }

    /// 在「文件」等处点开的 .enclave 备份文件：备份页读到后弹恢复面板。
    @Published var openedBackup: URL?

    /// 键盘标签里的二级页：模糊拼音、词库、常用词、键盘常用语、按键判定。
    enum KeyboardPage: String, Hashable { case fuzzy, doublePinyin, doublePinyinPractice, pinyin, commonWords, keyboardWords, touch }

    /// 词库页下面的两行：热门词库、导入的词库（三级页）。
    typealias ExtDictGroupPage = ExtDict.Group

    /// 热门词库、导入的词库页里点一个扩展词库进详情。
    struct ExtDictPage: Hashable { let id: String }

    /// 历史标签里的二级页：一条记录的详情、历史记录设置。
    enum HistoryPage: Hashable { case detail(String), settings }

    /// AI 标签里的二级页：润色 / 问答接口详情、结果卡左边的按钮、最近 20 次。
    enum AIPage: Hashable { case api(answer: Bool), resultKey, recent(answer: Bool) }

    /// AI 标签顶上的「接口 | 提示词」（第 51 条）。不存：每次冷启动停在「接口」，后台切回来保持当时那个。
    enum AISegment: Hashable { case api, prompts }
    @Published var aiSegment: AISegment = .api

    /// 「提示词」下面的「润色风格 | 问答风格」（第 54 条）。不存：冷启动停在「润色风格」，后台切回来保持当时那个。
    enum PromptKind: Hashable { case polish, answer }
    @Published var promptKind: PromptKind = .polish

    @Published var tab: Tab = .home { didSet { markScreen() } }
    /// 界面语言，改了马上存进 App Group，整个界面按新语言重画（导航位置保留）。
    @Published var language = Loc.setting {
        didSet { Loc.setting = language }
    }
    @Published var settingsPath: [SettingsPage] = [] { didSet { markScreen() } }
    /// AI 标签切到「问答」并滚到「联网搜索」（键盘「去开启」）。AI 页处理完清掉。
    @Published var showsAnswerWebSearch = false
    @Published var keyboardPath = NavigationPath() { didSet { markScreen() } }
    @Published var aiPath = NavigationPath() { didSet { markScreen() } }
    @Published var historyPath = NavigationPath() { didSet { markScreen() } }
    /// 隐私政策同意情况（CP1–CP5）：首次打开整页说明，设置 › 隐私里「阅读并同意」也打开它。
    @Published var privacyAgreed = PrivacyConsent.isAgreed
    @Published var showsPrivacyWelcome = PrivacyConsent.needsPrompt
    /// 首次启动引导（OB1–OB7）：隐私同意之后弹一次；首页「跟着教程设置」从选服务商开始再打开。
    @Published var setupGuide: SetupGuidePage?
    /// 教程选的服务商（TU0）。
    @Published var guideProvider: Provider = .deepseek
    /// 从接口页「配置教程」打开时是哪一页（Key 填回那一页）；引导里打开为 nil。
    @Published var guideTarget: GuideTarget?
    /// 教程看哪一边（中国大陆 / 非中国大陆，T102 NC3）：nil 按 App Store 地区；教程顶上能切换。
    @Published var guideSide: APISide?

    /// 引导「自己填写」/ Ollama 要接口页弹出新建配置页；接口页处理完清掉。
    struct NewConfigRequest: Equatable {
        var template: ConfigTemplate?
    }
    @Published var newConfig: NewConfigRequest?

    /// 接口页「配置教程」（TA1、TA2）、常用 API 地址里的「教程」：只走这一家的 4 步，右上是 ×。side：跟配置地址那一边。
    func openTutorial(_ provider: Provider, answer: Bool, side: APISide? = nil) {
        guideProvider = provider
        guideSide = side
        guideTarget = answer ? .answer : .rewrite
        setupGuide = .step(1)
    }

    /// 跳到润色接口页并直接弹出新建配置页（template 预先填好那一家）。
    func openNewConfig(_ template: ConfigTemplate? = nil) {
        openModel(detail: true)
        newConfig = NewConfigRequest(template: template)
    }

    /// 隐私说明关掉后：同意了、引导没看过、接口也没配，就接着弹引导。
    /// 先放功能演示（没看过的），演示走完再进欢迎页。
    func showSetupGuideIfNeeded(configured: Bool) {
        guard privacyAgreed else { return }
        if !FeatureTour.seen {
            setupGuide = .tour
        } else if !SetupGuide.seen, !configured {
            setupGuide = .welcome
        }
    }

    /// 内测版诊断记录用的「当时界面」：哪个标签、设置里哪一页。
    func markScreen(_ detail: String? = nil) {
        guard CrashLog.isEnabled else { return }
        let names: [Tab: String] = [.home: "首页", .keyboard: "键盘", .ai: "接口和提示词", .prompts: "提示词", .history: "历史", .settings: "设置"]
        var parts = [names[tab] ?? ""]
        if tab == .settings, let page = settingsPath.last { parts.append(page.rawValue) }
        if let detail { parts.append(detail) }
        CrashLog.mark(parts.joined(separator: " · "), source: "app")
    }

    func agreePrivacy() {
        PrivacyConsent.agree()
        privacyAgreed = true
        showsPrivacyWelcome = false
    }

    func useBasicOnly() {
        PrivacyConsent.useBasicOnly()
        privacyAgreed = false
        showsPrivacyWelcome = false
    }

    func revokePrivacy() {
        PrivacyConsent.revoke()
        privacyAgreed = false
    }

    init() {
        // 截图用：-playground 打开打字板并弹键盘；-homePage commonWords / keyboardWords / keyboard 打开键盘标签的二级页；
        // -appPage model 打开设置里的某一页；-appTab styles 切标签。
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        // 模拟器测试：-privacy agree / basic / reset 直接设好隐私政策同意情况。
        if let i = args.firstIndex(of: "-privacy"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "agree": PrivacyConsent.agree()
            case "basic": PrivacyConsent.useBasicOnly()
            case "reset": PrivacyConsent.resetForTesting()
            default: break
            }
            privacyAgreed = PrivacyConsent.isAgreed
            showsPrivacyWelcome = PrivacyConsent.needsPrompt
        }
        // -setupGuide reset / seen / open：引导看没看过，open 直接打开。
        if let i = args.firstIndex(of: "-setupGuide"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "reset": SetupGuide.seen = false
            case "seen": SetupGuide.seen = true
            case "open": setupGuide = .welcome
            case "deepseek": setupGuide = .step(4)
            case "kimi", "qwen", "glm":
                guideProvider = ["kimi": .kimi, "qwen": .qwen, "glm": .glm][args[i + 1]] ?? .deepseek
                setupGuide = .step(1)
            case "done": setupGuide = .done
            default: break
            }
        }
        // -tour reset / seen / open：功能演示看没看过，open 直接打开（再玩一次的样子）。
        if let i = args.firstIndex(of: "-tour"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "reset": FeatureTour.seen = false
            case "seen": FeatureTour.seen = true
            case "open": setupGuide = .tourReplay(nil)
            default: break
            }
        }
        // -diag sample / clear：诊断与反馈页塞几条假记录看样子，或者清空。
        if let i = args.firstIndex(of: "-diag"), args.indices.contains(i + 1) {
            args[i + 1] == "sample" ? CrashLog.addSamples() : CrashLog.clear()
        }
        // -rimeEval：纠错测试，词库部署好后把测试输入喂给引擎，结果写进 Documents（见 RimeEval）。
        if args.contains("-rimeEval") { RimeEval.runWhenDeployed() }
        #endif
        if args.contains("-playground") { openPlayground() }
        // 旧的 -homePage 参数：键盘那几页现在在键盘标签。
        if let i = args.firstIndex(of: "-homePage"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "keyboard": openKeyboard()
            case let name: if let page = KeyboardPage(rawValue: name) { openKeyboard(page) }
            }
        }
        if let i = args.firstIndex(of: "-appTab"), args.indices.contains(i + 1) {
            tab = ["keyboard": .keyboard, "ai": .ai, "styles": .ai, "prompts": .ai, "model": .ai, "history": .history, "settings": .settings][args[i + 1]] ?? .home
            // 提示词：窄屏是「接口和提示词」的提示词分段，iPad 宽屏换成「提示词」标签（setWideLayout）。
            if ["styles", "prompts"].contains(args[i + 1]) { aiSegment = .prompts }
        }
        // -appPage keyboard / pinyin / api / api-answer / testTools / privacy/privacyPolicy：直接打开某一页。
        if let i = args.firstIndex(of: "-appPage"), args.indices.contains(i + 1) {
            let name = args[i + 1]
            switch name {
            case "keyboard": openKeyboard()
            case "api", "api-main": openAI(answer: false, detail: true)
            case "api-answer": openAI(answer: true, detail: true)
            case "resultKey":
                openAI()
                aiPath.append(AIPage.resultKey)
            // 截图：AI › 提示词（润色风格 / 问答风格）、最近 20 次。manage 是以前的管理页，现在就地编辑，进同一页。
            case "ai-prompts", "manage": openAI(prompts: true)
            case "ai-prompts-answer", "manage-answer": openAI(prompts: true, answerStyles: true)
            case "recent", "recent-answer":
                openAI()
                aiPath.append(AIPage.recent(answer: name == "recent-answer"))
            default:
                if let page = KeyboardPage(rawValue: name) {
                    openKeyboard(page)
                } else if name == "ext-hot" || name == "ext-imported" {
                    // -appPage ext-hot / ext-imported：词库页下面的热门词库、导入的词库。
                    openKeyboard(.pinyin)
                    keyboardPath.append(name == "ext-hot" ? ExtDictGroupPage.hot : .imported)
                } else if name.hasPrefix("ext:") {
                    // -appPage ext:diming：某个扩展词库的详情（经过它所在的热门词库或导入的词库页）。
                    let id = String(name.dropFirst(4))
                    openKeyboard(.pinyin)
                    keyboardPath.append(ExtDict.installed.first { $0.id == id }?.kind.group ?? ExtDictGroupPage.hot)
                    keyboardPath.append(ExtDictPage(id: id))
                } else {
                    let pages = name.split(separator: "/").compactMap { SettingsPage(rawValue: String($0)) }
                    if !pages.isEmpty {
                        tab = .settings
                        settingsPath = pages
                    }
                }
            }
        }
    }

    /// enclave://playground、-playground：打开打字板，进去自动弹键盘（截图、打字基准用）。
    func openPlayground() {
        settingsPath = [.scratchPad]
        tab = .settings
    }

    /// 首页小卡：切到键盘标签，page 为 nil 时停在顶部。
    func openKeyboard(_ page: KeyboardPage? = nil) {
        keyboardPath = NavigationPath()
        if let page { keyboardPath.append(page) }
        tab = .keyboard
    }

    /// 跳到 AI 标签：默认「接口」，prompts 时「提示词」；detail 再推入润色（answer 时问答）接口详情。
    /// sharedAnswer：问答和润色用同一个接口，问答没有自己的详情，进润色的。
    func openAI(answer: Bool = false, detail: Bool = false, sharedAnswer: Bool = false, prompts: Bool = false, answerStyles: Bool = false) {
        aiSegment = prompts ? .prompts : .api
        if prompts { promptKind = answerStyles ? .answer : .polish }
        aiPath = NavigationPath()
        if detail { aiPath.append(AIPage.api(answer: answer && !sharedAnswer)) }
        tab = prompts && wideLayout ? .prompts : .ai
    }

    /// 从首页接口卡、欢迎页、解锁页跳到 AI 标签（填 Key 的进润色接口详情）。
    func openModel(answer: Bool = false, detail: Bool = false) {
        openAI(answer: answer, detail: detail)
    }

    /// 从首页卡片跳到设置里的某一页。
    func openSettings(_ page: SettingsPage) {
        settingsPath = [page]
        tab = .settings
    }
}

/// App 里各页共用的设置和 API key，改了马上存。
@MainActor
final class AppStore: ObservableObject {
    @Published var settings = SettingsStore.load() {
        didSet {
            guard settings != oldValue else { return }
            if !loading {
                SettingsStore.save(settings)
                if Self.syncedPartsDiffer(settings, oldValue) { scheduleSync() }
            }
            if settings.answerBaseURL != oldValue.answerBaseURL || settings.answerModel != oldValue.answerModel {
                answerTest = .idle
                answerMissingModel = nil
            }
            if settings.baseURL != oldValue.baseURL || settings.model != oldValue.model {
                test = .idle
                missingModel = nil
            }
        }
    }
    /// 润色页、问答页各自第几次点接口方案（等同步的那条同步完时，这一页期间又点过别的就不用它）。
    /// 分开记：改一条两页都在用的方案时连着换两页，不会把前一页的丢掉（04 四审可选 5）。
    private var applyRequests: [Bool: Int] = [:]
    /// 从存着的地方重新读（reload）时为 true：只更新界面，不写回（04 复审 A1：开着 Key 同步时 Key 可能在等同步，
    /// 读到的是空，写回去会把 iCloud 钥匙串里的删掉，所有设备一起没了）。
    private var loading = false
    @Published var apiKey = SettingsStore.apiKey ?? "" {
        didSet {
            guard apiKey != oldValue else { return }
            if !loading {
                SettingsStore.apiKey = apiKey
                scheduleSync()
            }
            test = .idle
            missingModel = nil
        }
    }
    /// 问答接口单独的 API Key。
    @Published var answerApiKey = SettingsStore.answerApiKey ?? "" {
        didSet {
            guard answerApiKey != oldValue else { return }
            if !loading {
                SettingsStore.answerApiKey = answerApiKey
                scheduleSync()
            }
            answerTest = .idle
            answerMissingModel = nil
        }
    }

    private var syncTask: Task<Void, Never>?

    /// 改了会同步的东西（风格、接口、Key、接口方案）：开着 iCloud 同步时等 3 秒同步一次，别的设备不用等这台下次打开 App
    /// （04 复审 A2）。连着改（打字、拖滑块）只算最后一次。同步本身另起一个任务，后面再改不会把正在跑的同步取消掉。
    private func scheduleSync() {
        guard ICloudSync.isEnabled else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            Task { await ICloudSync.syncNow() }
        }
    }

    /// 同步的那部分设置（风格；开着 Key 同步时还有接口）变了没有。
    private static func syncedPartsDiffer(_ a: EnclaveSettings, _ b: EnclaveSettings) -> Bool {
        SyncMerge.StyleProfile(settings: a) != SyncMerge.StyleProfile(settings: b)
            || SyncMerge.EndpointProfile(settings: a, keys: [:]) != SyncMerge.EndpointProfile(settings: b, keys: [:])
    }
    @Published private(set) var test: TestState = .idle
    /// 测试成功后顺便取一次模型列表，当前模型不在里面时记下它的名字（ML5「可能已下线」）。取列表失败不算。
    @Published private(set) var missingModel: String?
    @Published private(set) var answerMissingModel: String?
    /// 测试失败的原因，引导里按它给一句话（OB6）：Key 不对、余额不足、网络不通。
    @Published private(set) var testFailure: TestFailure?

    enum TestFailure: Equatable { case unauthorized, noBalance, network, other }

    enum TestState: Equatable {
        case idle, running, success(String, TimeInterval), failure(String)
    }

    /// 已存方案（接口页「保存」）。
    @Published private(set) var savedAPIs = SavedAPIStore.all

    private var syncObserver: NSObjectProtocol?

    init() {
        // iCloud 同步写进了别的设备改的接口和风格：重新读，不然这里手里的旧设置下次保存时会把它们冲掉。
        syncObserver = NotificationCenter.default.addObserver(forName: .enclaveSyncDidApply, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.reload()
            self.savedAPIs = SavedAPIStore.all
        }
    }

    deinit {
        if let syncObserver { NotificationCenter.default.removeObserver(syncObserver) }
    }

    /// 把这一页现在填的地址、模型、Key 存成预设。answer：问答页。三样都和已有某条一样时不新增（.duplicate）。
    @discardableResult
    func saveAPI(name: String?, answer: Bool) -> SavedAPIStore.SaveResult {
        let result = answer
            ? SavedAPIStore.save(name: name, baseURL: settings.answerBaseURL, model: settings.answerModel, apiKey: answerApiKey)
            : SavedAPIStore.save(name: name, baseURL: settings.baseURL, model: settings.model, apiKey: apiKey)
        savedAPIs = SavedAPIStore.all
        return result
    }

    /// 这一页现在用的是哪条预设：地址、模型、Key 三样都一样才算。
    func currentSavedAPI(answer: Bool) -> SavedAPI? {
        savedAPIs.first { answer
            ? $0.matches(baseURL: settings.answerBaseURL, model: settings.answerModel, apiKey: answerApiKey)
            : $0.matches(baseURL: settings.baseURL, model: settings.model, apiKey: apiKey) }
    }

    /// 点预设：只换这一页的地址、模型和 Key（问答页顺便关掉「和改写用同一个接口」），然后状态卡重新测一次。
    func applySavedAPI(_ saved: SavedAPI, answer: Bool) {
        let request = (applyRequests[answer] ?? 0) + 1
        applyRequests[answer] = request
        // 开着 Key 同步、这条的 Key 在等同步（别的设备刚改过它）：读到的是空，照用会把这一页的 Key 清掉、删到所有设备上
        // （04 复审 A1）。先同步一次，新的 Key 和配置到了再用；还没到就不动。同步期间又点了别的就不用这条（04 三审可选 7）。
        if saved.keyPending {
            Task {
                await ICloudSync.syncNow()
                guard request == applyRequests[answer],
                      let fresh = SavedAPIStore.all.first(where: { $0.id == saved.id }), !fresh.keyPending else { return }
                applySavedAPI(fresh, answer: answer)
            }
            return
        }
        let key = saved.apiKey ?? ""
        if answer {
            settings.separateAnswer = true
            settings.answerBaseURL = saved.baseURL
            settings.answerModel = saved.model
            settings.answerTemperature = saved.temperature
            settings.answerMaxTokens = saved.maxTokens
            answerApiKey = key
        } else {
            settings.baseURL = saved.baseURL
            settings.model = saved.model
            // 生成参数跟着配置走（旧预设没有就不动）。
            if let temperature = saved.temperature { settings.temperature = temperature }
            if let maxTokens = saved.maxTokens { settings.maxTokens = maxTokens }
            apiKey = key
        }
        guard PrivacyConsent.isAgreed else { return }
        Task { answer ? await runAnswerTest() : await runTest() }
    }

    // MARK: 接口配置（CF）

    /// 第一次打开新的接口配置页：原来润色、问答正在用的接口各存成一条配置。
    func migrateConfigsIfNeeded() {
        var current: [(baseURL: String, model: String, apiKey: String?, temperature: Double?, maxTokens: Int?)] = []
        if settings.isConfigured { current.append((settings.baseURL, settings.model, apiKey, settings.temperature, settings.maxTokens)) }
        if settings.usesAnswerEndpoint {
            current.append((settings.answerBaseURL, settings.answerModel, answerApiKey,
                            settings.answerTemperature ?? settings.temperature, settings.answerMaxTokens ?? settings.maxTokens))
        }
        SavedAPIStore.migrateIfNeeded(current: current) { ProviderName.of($0) }
        savedAPIs = SavedAPIStore.all
    }

    /// 新建配置；这一页还没有正在用的配置时直接用上它。
    @discardableResult
    func addConfig(_ item: SavedAPI, apiKey key: String, answer: Bool) -> SavedAPI {
        let hadCurrent = currentSavedAPI(answer: answer) != nil
            || (answer ? settings.usesAnswerEndpoint : settings.isConfigured)
        let saved = SavedAPIStore.add(item, apiKey: key)
        savedAPIs = SavedAPIStore.all
        scheduleSync()
        if !hadCurrent { applySavedAPI(saved, answer: answer) }
        return saved
    }

    /// 改配置；润色或问答正在用这一条的话，改完接着用改后的。
    func updateConfig(_ item: SavedAPI, apiKey key: String) {
        let polishUses = currentSavedAPI(answer: false)?.id == item.id
        let answerUses = settings.separateAnswer && currentSavedAPI(answer: true)?.id == item.id
        SavedAPIStore.update(item, apiKey: key)
        savedAPIs = SavedAPIStore.all
        scheduleSync()
        guard let saved = savedAPIs.first(where: { $0.id == item.id }) else { return }
        if polishUses { applySavedAPI(saved, answer: false) }
        if answerUses { applySavedAPI(saved, answer: true) }
    }

    func renameSavedAPI(_ id: UUID, to name: String) {
        SavedAPIStore.rename(id, to: name)
        savedAPIs = SavedAPIStore.all
        scheduleSync()
    }

    func deleteSavedAPI(_ id: UUID) {
        SavedAPIStore.delete(id)
        savedAPIs = SavedAPIStore.all
        scheduleSync()
    }

    /// 从剪贴板导入、同步写进了别的设备的改动之后重新读一遍：只更新界面，不写回、不再触发同步。
    func reload() {
        loading = true
        defer { loading = false }
        settings = SettingsStore.load()
        apiKey = SettingsStore.apiKey ?? ""
        answerApiKey = SettingsStore.answerApiKey ?? ""
        test = .idle
    }

    /// 键盘自己存进共用设置的改动（iPad 9 键换边 swapNineSide、长按中/英换布局）：App 回到前台、键盘设置页出现时重读（第 86 条）。
    /// 只读设置、只更新界面、不写回；不动 Key 和接口测试的状态（和 reload 不同，回前台时不该清掉）。
    func reloadSettings() {
        let latest = SettingsStore.load()
        guard latest != settings else { return }
        loading = true
        defer { loading = false }
        settings = latest
    }

    /// 恢复备份后重新读 Key（同 reload，不写回）。
    func reloadKeys() {
        loading = true
        defer { loading = false }
        apiKey = SettingsStore.apiKey ?? ""
        answerApiKey = SettingsStore.answerApiKey ?? ""
    }

    /// 上次测试这个地址和模型的结果，首页「接口」卡片显示连接状态用。
    var lastTestOK: Bool? {
        SharedStorage.defaults.object(forKey: testKey) as? Bool
    }

    private var testKey: String { EnclaveSettings.testKey(baseURL: settings.baseURL, model: settings.model) }

    #if DEBUG
    /// 截图用：不联网，直接当作测试成功。
    func fakeTestSuccess() {
        testFailure = nil
        test = .success("你好", 0.8)
        // 同真的测试一样记下结果：欢迎页第 3 步、首页接口卡看的是它。
        SharedStorage.defaults.set(true, forKey: testKey)
    }
    #endif

    /// 问答接口的测试（接口页「测试问答接口」）。只显示在按钮旁边，不算进顶部状态卡和首页。
    @Published private(set) var answerTest: TestState = .idle

    func runAnswerTest() async {
        guard PrivacyConsent.isAgreed, settings.usesAnswerEndpoint else { return }
        answerTest = .running
        let start = Date()
        let client = LLMClient(settings: settings.forAnswers, apiKey: answerApiKey)
        var raw = ""
        var failure: String?
        let result: TestState
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")], retries: 0) { raw += piece }
            if ModelOutput.clean(raw).isEmpty { failure = UsageStats.Request.Failure.empty }
            result = ModelOutput.clean(raw).isEmpty
                ? .failure(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                : .success("", Date().timeIntervalSince(start))
        } catch {
            failure = UsageStats.Request.Failure.of(error)
            result = .failure(Self.testFailureText(error, failure))
        }
        var ok = false
        if case .success = result { ok = true }
        // 键盘按它决定显不显示问答键（QE）。
        let answerConfig = settings.forAnswers
        SharedStorage.defaults.set(ok, forKey: EnclaveSettings.testKey(baseURL: answerConfig.baseURL, model: answerConfig.model))
        // 问答卡的最近 20 次里有它；先记再改状态，接口卡收到变化时就能读到这一次。
        UsageStats.recordAnswerRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok, model: settings.forAnswers.model,
                                       error: failure, test: true)
        answerTest = result
        if ok { await checkModelListed(answer: true) }
    }

    private func checkModelListed(answer: Bool) async {
        let config = answer ? settings.forAnswers : settings
        let model = config.model.trimmingCharacters(in: .whitespaces)
        guard !BuiltinAPI.isInternalBuild, !model.isEmpty, !ModelList.isUnsupported(config.baseURL),
              let models = try? await ModelList.fetch(baseURL: config.baseURL, apiKey: answer ? answerApiKey : apiKey),
              !models.isEmpty else { return }
        // 等列表回来时设置可能已经改了。
        guard (answer ? settings.forAnswers : settings).model.trimmingCharacters(in: .whitespaces) == model else { return }
        let missing = models.contains(model) ? nil : model
        if answer { answerMissingModel = missing } else { missingModel = missing }
    }

    /// 测试失败时接口卡上的红字：认得的原因用短句（同「最近 20 次」，比如「Key 无效（401）」），
    /// 不把服务商返回的原始 JSON（里面可能带 Key 的后几位）显示出来；认不得的才用原始信息。
    static func testFailureText(_ error: Error, _ failure: String?) -> String {
        guard let failure, failure != UsageStats.Request.Failure.other else { return error.localizedDescription }
        return UsageStats.Request(ms: 0, ok: false, at: Date(), error: failure).failureText
    }

    func runTest() async {
        // 没同意隐私政策前不发任何网络请求（测试会把 API Key 发到外部地址），入口处会先提示。
        guard PrivacyConsent.isAgreed else { return }
        test = .running
        testFailure = nil
        let start = Date()
        let client = LLMClient(settings: settings, apiKey: apiKey)
        var raw = ""
        var failure: String?
        let result: TestState
        var reason: TestFailure?
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")], retries: 0) {
                raw += piece
            }
            if ModelOutput.clean(raw).isEmpty { failure = UsageStats.Request.Failure.empty }
            let reply = ModelOutput.clean(raw)
            result = reply.isEmpty ? .failure(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                : .success(String(reply.prefix(40)), Date().timeIntervalSince(start))
        } catch {
            failure = UsageStats.Request.Failure.of(error)
            result = .failure(Self.testFailureText(error, failure))
            switch error {
            case LLMError.http(let code, _) where code == 401 || code == 403: reason = .unauthorized
            case LLMError.http(402, _): reason = .noBalance
            case LLMError.timeout: reason = .network
            case is URLError: reason = .network
            default: reason = .other
            }
        }
        var ok = false
        if case .success = result { ok = true }
        SharedStorage.defaults.set(ok, forKey: testKey)
        // 上手引导第 3 步「连接 AI」（T95）：润色测通就算定了问答，默认和润色用同一个配置；另配过问答 Key 的不动。
        if ok && !WelcomeSetup.answerDecided {
            WelcomeSetup.answerDecided = true
            if answerApiKey.isEmpty { settings.separateAnswer = false }
        }
        // 测试也算一次请求，润色卡的最近 20 次里有它；先记再改状态，接口卡收到变化时就能读到这一次。
        UsageStats.recordRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok, model: settings.model, error: failure, test: true)
        testFailure = reason
        test = result
        if ok { await checkModelListed(answer: false) }
    }
}
