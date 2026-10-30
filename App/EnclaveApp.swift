import StoreKit
import SwiftUI

@main
struct EnclaveApp: App {
    @StateObject private var router = AppRouter.shared
    @StateObject private var store = AppStore()

    init() {
        // 内测版：收崩溃、卡死记录，只存本机。
        CrashLog.shared.start(source: "app")
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
            AppRouter.shared.openAI(answer: false)
        }
        // -storefront CHN：按中国大陆店面显示（接口页服务商）。
        if let index = args.firstIndex(of: "-storefront"), args.indices.contains(index + 1) {
            Storefront.debugOverride(args[index + 1])
        }
        // -keyboardWords "张三丰,me@example.com" 写进键盘常用语。
        if let index = args.firstIndex(of: "-keyboardWords"), args.indices.contains(index + 1) {
            CommonWordStore.keyboardTexts = args[index + 1].split(separator: ",").map(String.init)
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
                    Task { await UnlockStore.shared.refresh() }
                }
                .onOpenURL { url in
                    // enclave://playground 直接打开「试一试」并弹出键盘，方便在模拟器里截图测试。
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
                    // 键盘出错卡的「去设置」：AI 标签，进当前那页的接口详情（问答和润色用同一个时进润色的）。
                    case "api":
                        router.openAI(detail: true, sharedAnswer: !store.settings.separateAnswer)
                    // 键盘里要联网但已禁止时的「去开启」：AI › 问答，滚到「联网搜索」。
                    case "api-answer":
                        router.openAI(answer: true)
                        router.showsAnswerWebSearch = true
                    case "privacy-policy":
                        router.settingsPath = [.privacy, .privacyPolicy]
                        router.tab = .settings
                    // 键盘提示卡「去解锁」。
                    case "unlock": router.openSettings(.unlock)
                    // 键盘风格一排最右的「+」：AI 标签对应那一页（润色 / 问答）的提示词。
                    case "prompts", "prompts-answer":
                        router.openAI(answer: url.host == "prompts-answer")
                    case "common-words":
                        router.openKeyboard(.commonWords)
                    default: break
                    }
                }
        }
    }
}

/// 底部四个标签：首页、键盘、AI、设置。
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: AppStore

    var body: some View {
        tabs
            // 首次打开先看隐私说明（CP1），不能下滑关掉。
            .fullScreenCover(isPresented: $router.showsPrivacyWelcome, onDismiss: {
                router.showSetupGuideIfNeeded(configured: store.settings.isConfigured)
            }) {
                PrivacyWelcomeView()
                    .environmentObject(router)
                    .environment(\.locale, Loc.locale)
            }
            // 连上 AI 接口的引导（OB1–OB7）。
            .fullScreenCover(item: $router.setupGuide) { start in
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
            KeyboardTab()
                .tabItem { Label(L("键盘", "Keyboard", "キーボード"), systemImage: "keyboard") }
                .tag(AppRouter.Tab.keyboard)
            AITab()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(AppRouter.Tab.ai)
            SettingsView()
                .tabItem { Label(L("设置", "Settings", "設定"), systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
    }
}

/// 页面跳转：标签、设置里的子页面，以及从链接或启动参数直接打开某个页面。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable { case home, keyboard, ai, settings }

    /// 设置里的二级页。setup：首次设置（欢迎页四步）；firstScene：使用指引的第一个场景（enclave://playground）。
    enum SettingsPage: String, Hashable {
        case setup, playground, firstScene, privacy, about, unlock, language, privacyPolicy, licenses, diagnostics, feedback, testTools
    }

    /// 键盘标签里的二级页：模糊拼音、词库、常用词、键盘常用语、按键判定。
    enum KeyboardPage: String, Hashable { case fuzzy, pinyin, commonWords, keyboardWords, touch }

    /// 词库页里点一个扩展词库进详情。
    struct ExtDictPage: Hashable { let id: String }

    /// AI 标签里的二级页：润色 / 问答接口详情、结果卡左边的按钮。
    enum AIPage: Hashable { case api(answer: Bool), resultKey }

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
    /// 隐私政策同意情况（CP1–CP5）：首次打开整页说明，设置 › 隐私里「阅读并同意」也打开它。
    @Published var privacyAgreed = PrivacyConsent.isAgreed
    @Published var showsPrivacyWelcome = PrivacyConsent.needsPrompt
    /// 首次启动引导（OB1–OB7）：隐私同意之后弹一次；首页「跟着教程设置」从选服务商开始再打开。
    @Published var setupGuide: SetupGuidePage?
    /// 教程选的服务商（TU0）。
    @Published var guideProvider: Provider = .deepseek
    /// 从接口页「配置教程」打开时是哪一页（Key 填回那一页）；引导里打开为 nil。
    @Published var guideTarget: GuideTarget?

    /// 接口页格子右下角「配置教程」（TA1、TA2）：只走这一家的 4 步，右上是 ×。
    func openTutorial(_ provider: Provider, answer: Bool) {
        guideProvider = provider
        guideTarget = answer ? .answer : .rewrite
        setupGuide = .step(1)
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
        let names: [Tab: String] = [.home: "首页", .keyboard: "键盘", .ai: "AI", .settings: "设置"]
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
        // 截图用：-playground 打开第一个场景；-homePage commonWords / keyboardWords / lab / keyboard 打开首页的二级页；
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
            case "open": setupGuide = .tourReplay
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
        // 旧的 -homePage 参数：键盘那几页现在在键盘标签，使用指引在设置。
        if let i = args.firstIndex(of: "-homePage"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "keyboard": openKeyboard()
            case "lab": openSettings(.playground)
            case let name: if let page = KeyboardPage(rawValue: name) { openKeyboard(page) }
            }
        }
        if let i = args.firstIndex(of: "-appTab"), args.indices.contains(i + 1) {
            tab = ["keyboard": .keyboard, "ai": .ai, "styles": .ai, "model": .ai, "settings": .settings][args[i + 1]] ?? .home
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
            default:
                if let page = KeyboardPage(rawValue: name) {
                    openKeyboard(page)
                } else if name.hasPrefix("ext:") {
                    // -appPage ext:diming：词库页里某个扩展词库的详情。
                    openKeyboard(.pinyin)
                    keyboardPath.append(ExtDictPage(id: String(name.dropFirst(4))))
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

    /// enclave://playground：打开使用指引的第一个场景，进去自动弹键盘。
    func openPlayground() {
        settingsPath = [.playground, .firstScene]
        tab = .settings
    }

    /// 首页小卡：切到键盘标签，page 为 nil 时停在顶部。
    func openKeyboard(_ page: KeyboardPage? = nil) {
        keyboardPath = NavigationPath()
        if let page { keyboardPath.append(page) }
        tab = .keyboard
    }

    /// AI 标签记住上次停的那页（润色 / 问答）。
    static var aiShowsAnswer: Bool {
        get { UserDefaults.standard.string(forKey: "apiPage") == "answer" }
        set { UserDefaults.standard.set(newValue ? "answer" : "main", forKey: "apiPage") }
    }

    /// 跳到 AI 标签。answer 为 nil 时停在上次那页；detail 再推入那页的接口详情。
    /// sharedAnswer：问答和润色用同一个接口，问答页没有详情，进润色的。
    func openAI(answer: Bool? = nil, detail: Bool = false, sharedAnswer: Bool = false) {
        if let answer { Self.aiShowsAnswer = answer }
        aiPath = NavigationPath()
        if detail { aiPath.append(AIPage.api(answer: Self.aiShowsAnswer && !sharedAnswer)) }
        tab = .ai
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
            SettingsStore.save(settings)
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
    @Published var apiKey = SettingsStore.apiKey ?? "" {
        didSet {
            guard apiKey != oldValue else { return }
            SettingsStore.apiKey = apiKey
            test = .idle
            missingModel = nil
        }
    }
    /// 问答接口单独的 API Key。
    @Published var answerApiKey = SettingsStore.answerApiKey ?? "" {
        didSet {
            guard answerApiKey != oldValue else { return }
            SettingsStore.answerApiKey = answerApiKey
            answerTest = .idle
            answerMissingModel = nil
        }
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
        let key = saved.apiKey ?? ""
        if answer {
            settings.separateAnswer = true
            settings.answerBaseURL = saved.baseURL
            settings.answerModel = saved.model
            answerApiKey = key
        } else {
            settings.baseURL = saved.baseURL
            settings.model = saved.model
            apiKey = key
        }
        guard PrivacyConsent.isAgreed else { return }
        Task { answer ? await runAnswerTest() : await runTest() }
    }

    func renameSavedAPI(_ id: UUID, to name: String) {
        SavedAPIStore.rename(id, to: name)
        savedAPIs = SavedAPIStore.all
    }

    func deleteSavedAPI(_ id: UUID) {
        SavedAPIStore.delete(id)
        savedAPIs = SavedAPIStore.all
    }

    /// 从剪贴板导入后重新读一遍。
    func reload() {
        settings = SettingsStore.load()
        apiKey = SettingsStore.apiKey ?? ""
        answerApiKey = SettingsStore.answerApiKey ?? ""
        test = .idle
    }

    /// 上次测试这个地址和模型的结果，首页「接口」卡片显示连接状态用。
    var lastTestOK: Bool? {
        SharedStorage.defaults.object(forKey: testKey) as? Bool
    }

    private var testKey: String { "test.ok.\(settings.baseURL)|\(settings.model)" }

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
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")], retries: 0) { raw += piece }
            answerTest = ModelOutput.clean(raw).isEmpty
                ? .failure(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                : .success("", Date().timeIntervalSince(start))
        } catch {
            answerTest = .failure(error.localizedDescription)
        }
        var ok = false
        if case .success = answerTest { ok = true }
        if ok { await checkModelListed(answer: true) }
        // 问答页的小曲线里有它。
        UsageStats.recordAnswerRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok)
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

    func runTest() async {
        // 没同意隐私政策前不发任何网络请求（测试会把 API Key 发到外部地址），入口处会先提示。
        guard PrivacyConsent.isAgreed else { return }
        test = .running
        testFailure = nil
        let start = Date()
        let client = LLMClient(settings: settings, apiKey: apiKey)
        var raw = ""
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")], retries: 0) {
                raw += piece
            }
            let reply = ModelOutput.clean(raw)
            test = reply.isEmpty ? .failure(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                : .success(String(reply.prefix(40)), Date().timeIntervalSince(start))
        } catch {
            test = .failure(error.localizedDescription)
            switch error {
            case LLMError.http(let code, _) where code == 401 || code == 403: testFailure = .unauthorized
            case LLMError.http(402, _): testFailure = .noBalance
            case LLMError.timeout: testFailure = .network
            case is URLError: testFailure = .network
            default: testFailure = .other
            }
        }
        var ok = false
        if case .success = test { ok = true }
        SharedStorage.defaults.set(ok, forKey: testKey)
        if ok { await checkModelListed(answer: false) }
        // 测试也算一次请求，接口页的小曲线里有它。
        UsageStats.recordRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok)
    }
}
