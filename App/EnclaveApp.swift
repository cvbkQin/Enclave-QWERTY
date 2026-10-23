import SwiftUI

@main
struct EnclaveApp: App {
    @StateObject private var router = AppRouter.shared

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
            SettingsView()
                .environmentObject(router)
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

/// 页面跳转：从链接或启动参数直接打开某个页面。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var showPlayground = ProcessInfo.processInfo.arguments.contains("-playground")
    /// 每次打开「试一试」都换一个值，让页面重新聚焦第一个输入框。
    @Published private(set) var playgroundFocusToken = UUID()

    func openPlayground() {
        playgroundFocusToken = UUID()
        showPlayground = true
    }
}
