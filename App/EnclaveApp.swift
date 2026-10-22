import SwiftUI

@main
struct EnclaveApp: App {
    @StateObject private var voice = VoiceService.shared

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(voice)
                .onOpenURL { url in
                    // 键盘点「说话」时用 enclave://voice?mode=content 打开 App：开启会话并直接开始录音。
                    guard url.scheme == "enclave", url.host == "voice" else { return }
                    let modeValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "mode" }?.value
                    let mode = modeValue.flatMap(VoiceMode.init(rawValue:)) ?? .content
                    Task {
                        await voice.startSession()
                        voice.startRecording(mode: mode)
                    }
                }
        }
    }
}
