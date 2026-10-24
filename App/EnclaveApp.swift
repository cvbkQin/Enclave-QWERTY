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
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(store)
                .task { RimeDeployer.shared.deployIfNeeded() }
                .onOpenURL { url in
                    // enclave://playground 直接打开「试一试」并弹出键盘，方便在模拟器里截图测试。
                    if url.scheme == "enclave", url.host == "playground" {
                        router.openPlayground()
                    }
                }
        }
    }
}

/// 底部三个标签：首页、风格、设置。
struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(AppRouter.Tab.home)
            StylesTab()
                .tabItem { Label("风格", systemImage: "sparkles") }
                .tag(AppRouter.Tab.styles)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
    }
}

/// 页面跳转：标签、设置里的子页面，以及从链接或启动参数直接打开某个页面。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable { case home, styles, settings }

    enum SettingsPage: String, Hashable {
        case model, keyboard, fuzzy, pinyin, guide, playground, privacy, about
    }

    @Published var tab: Tab = .home
    @Published var settingsPath: [SettingsPage] = []
    @Published var showPlayground = false
    /// 每次打开「试一试」都换一个值，让页面重新聚焦第一个输入框。
    @Published private(set) var playgroundFocusToken = UUID()

    init() {
        // 截图用：-playground 打开试一试；-appPage model 打开设置里的某一页；-appTab styles 切标签。
        let args = ProcessInfo.processInfo.arguments
        showPlayground = args.contains("-playground")
        if let i = args.firstIndex(of: "-appTab"), args.indices.contains(i + 1) {
            tab = ["styles": .styles, "settings": .settings][args[i + 1]] ?? .home
        }
        if let i = args.firstIndex(of: "-appPage"), args.indices.contains(i + 1) {
            let pages = args[i + 1].split(separator: "/").compactMap { SettingsPage(rawValue: String($0)) }
            if !pages.isEmpty {
                tab = .settings
                settingsPath = pages
            }
        }
    }

    func openPlayground() {
        playgroundFocusToken = UUID()
        tab = .home
        showPlayground = true
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
            test = reply.isEmpty ? .failure("连上了，但模型没有返回内容。")
                : .success(String(reply.prefix(40)), Date().timeIntervalSince(start))
        } catch {
            test = .failure(error.localizedDescription)
        }
    }
}
