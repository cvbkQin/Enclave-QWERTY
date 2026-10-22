import SwiftUI

@main
struct EnclaveApp: App {
    @StateObject private var voice = VoiceService.shared

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(voice)
                .onOpenURL { url in
                    // 键盘点「说话」时用 enclave://voice 打开 App：这里只开启会话，
                    // 用户返回键盘后由键盘自动开始录音。
                    guard url.scheme == "enclave", url.host == "voice" else { return }
                    Task { await voice.startSession() }
                }
        }
    }
}
