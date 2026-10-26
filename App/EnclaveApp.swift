import SwiftUI

@main
struct EnclaveApp: App {
    @StateObject private var router = AppRouter.shared
    @StateObject private var store = AppStore()

    init() {
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
                .task { RimeDeployer.shared.deployIfNeeded() }
                .task { await UnlockStore.shared.refresh() }
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
                    case "privacy-policy":
                        router.settingsPath = [.privacy, .privacyPolicy]
                        router.tab = .settings
                    // 键盘提示卡「去解锁」。
                    case "unlock": router.openSettings(.unlock)
                    case "common-words":
                        router.tab = .home
                        router.homePath = NavigationPath([AppRouter.HomePage.commonWords])
                    default: break
                    }
                }
        }
    }
}

/// 底部四个标签：首页、提示词、接口、设置。
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: AppStore

    var body: some View {
        tabs
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
            StylesTab()
                .tabItem { Label(L("提示词", "Prompts", "プロンプト"), systemImage: "sparkles") }
                .tag(AppRouter.Tab.styles)
            NavigationStack { ModelSettingsView() }
                .tabItem { Label(L("接口", "API", "API"), systemImage: "cpu") }
                .tag(AppRouter.Tab.model)
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

    enum Tab: Hashable { case home, styles, model, settings }

    enum SettingsPage: String, Hashable {
        case keyboard, fuzzy, pinyin, guide, playground, privacy, about, unlock, language, privacyPolicy, licenses
    }

    /// 首页里的二级页：键盘、常用词（全部 / 键盘标签）、场景实验室和其中一个场景。
    enum HomePage: Hashable { case keyboard, pinyin, commonWords, keyboardWords, lab, scene(Int) }

    @Published var tab: Tab = .home
    /// 界面语言，改了马上存进 App Group，整个界面按新语言重画（导航位置保留）。
    @Published var language = Loc.setting {
        didSet { Loc.setting = language }
    }
    @Published var settingsPath: [SettingsPage] = []
    @Published var homePath = NavigationPath()

    init() {
        // 截图用：-playground 打开第一个场景；-homePage commonWords / keyboardWords / lab / keyboard 打开首页的二级页；
        // -appPage model 打开设置里的某一页；-appTab styles 切标签。
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-playground") { homePath = NavigationPath([HomePage.lab, HomePage.scene(0)]) }
        if let i = args.firstIndex(of: "-homePage"), args.indices.contains(i + 1) {
            let page: HomePage? = ["keyboard": .keyboard, "commonWords": .commonWords, "keyboardWords": .keyboardWords, "lab": .lab][args[i + 1]]
            if let page { homePath = NavigationPath([page]) }
        }
        if let i = args.firstIndex(of: "-appTab"), args.indices.contains(i + 1) {
            tab = ["styles": .styles, "model": .model, "settings": .settings][args[i + 1]] ?? .home
        }
        if let i = args.firstIndex(of: "-appPage"), args.indices.contains(i + 1) {
            let pages = args[i + 1].split(separator: "/").compactMap { SettingsPage(rawValue: String($0)) }
            if !pages.isEmpty {
                tab = .settings
                settingsPath = pages
            }
        }
    }

    /// enclave://playground：打开场景实验室的第一个场景，进去自动弹键盘。
    func openPlayground() {
        tab = .home
        homePath = NavigationPath([HomePage.lab, HomePage.scene(0)])
    }

    func openHome(_ page: HomePage) {
        homePath.append(page)
    }

    /// 从首页卡片跳到「接口」标签。
    func openModel() {
        tab = .model
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
            if settings.baseURL != oldValue.baseURL || settings.model != oldValue.model { test = .idle }
        }
    }
    @Published var apiKey = SettingsStore.apiKey ?? "" {
        didSet {
            guard apiKey != oldValue else { return }
            SettingsStore.apiKey = apiKey
            test = .idle
        }
    }
    @Published private(set) var test: TestState = .idle

    enum TestState: Equatable {
        case idle, running, success(String, TimeInterval), failure(String)
    }

    /// 从剪贴板导入后重新读一遍。
    func reload() {
        settings = SettingsStore.load()
        apiKey = SettingsStore.apiKey ?? ""
        test = .idle
    }

    /// 上次测试这个地址和模型的结果，首页「接口」卡片显示连接状态用。
    var lastTestOK: Bool? {
        SharedStorage.defaults.object(forKey: testKey) as? Bool
    }

    private var testKey: String { "test.ok.\(settings.baseURL)|\(settings.model)" }

    func runTest() async {
        test = .running
        let start = Date()
        let client = LLMClient(settings: settings, apiKey: apiKey)
        var raw = ""
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")]) {
                raw += piece
            }
            let reply = ModelOutput.clean(raw)
            test = reply.isEmpty ? .failure(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                : .success(String(reply.prefix(40)), Date().timeIntervalSince(start))
        } catch {
            test = .failure(error.localizedDescription)
        }
        var ok = false
        if case .success = test { ok = true }
        SharedStorage.defaults.set(ok, forKey: testKey)
        // 测试也算一次请求，接口页的小曲线里有它。
        UsageStats.recordRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok)
    }
}
