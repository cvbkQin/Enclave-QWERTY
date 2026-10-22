import SwiftUI

/// 设置页顶部的麦克风会话状态。从键盘跳过来时用户第一眼看到的就是这里。
struct VoiceSessionSection: View {
    @EnvironmentObject private var voice: VoiceService

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(voice.state == .idle ? Color.secondary : Color.orange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if let error = voice.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if !voice.lastText.isEmpty {
                Text("上一次识别：\(voice.lastText)").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }

            switch voice.state {
            case .idle:
                Button("开启语音会话") { Task { await voice.startSession() } }
            case .recording:
                Button("说完了") { voice.stopRecording() }
                Button("结束语音会话", role: .destructive) { voice.endSession() }
            default:
                Button("结束语音会话", role: .destructive) { voice.endSession() }
            }
        } header: {
            Text("语音")
        }
    }

    private var icon: String {
        switch voice.state {
        case .idle: return "mic.slash"
        case .ready: return "mic"
        case .recording: return "waveform"
        case .transcribing: return "ellipsis"
        }
    }

    private var title: String {
        switch voice.state {
        case .idle: return "语音会话未开启"
        case .ready: return "麦克风已就绪"
        case .recording: return "正在听…"
        case .transcribing: return "识别中…"
        }
    }

    private var subtitle: String {
        switch voice.state {
        case .idle: return "在键盘上点「说话」会自动开启。"
        case .recording, .ready, .transcribing:
            return "点左上角「◀ 返回」回到刚才的 App，在键盘上点「说话」「说要求」即可，不用再跳回来。"
        }
    }
}

struct VoiceSettingsSection: View {
    @Binding var settings: EnclaveSettings
    @State private var asrKey = SettingsStore.asrApiKey ?? ""

    var body: some View {
        Section {
            Picker("识别方式", selection: $settings.asrProvider) {
                Text("苹果本机识别").tag(ASRProvider.apple)
                Text("自定义接口").tag(ASRProvider.custom)
            }
            if settings.asrProvider == .apple {
                Toggle("允许使用苹果服务器", isOn: $settings.allowAppleServerASR)
            } else {
                fieldRow("接口地址", text: $settings.asrBaseURL, placeholder: "http://100.x.x.x:8000/v1")
                fieldRow("模型", text: $settings.asrModel, placeholder: "whisper-1")
                HStack {
                    Text("API Key")
                    SecureField("自建服务可以留空", text: $asrKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            Picker("会话保持", selection: $settings.voiceSessionMinutes) {
                Text("5 分钟").tag(5)
                Text("15 分钟").tag(15)
                Text("1 小时").tag(60)
                Text("不自动结束").tag(0)
            }
            Toggle("说完自动润色", isOn: $settings.autoPolishAfterVoice)
        } header: {
            Text("语音输入")
        } footer: {
            Text("苹果本机识别默认只在手机上离线处理，不上传。自定义接口支持 OpenAI 兼容的 /audio/transcriptions，例如自建 Whisper 或 SenseVoice。会话开启期间状态栏会显示麦克风图标，但只有点「说话」后的声音才会被识别；闲置超过设定时间自动结束。")
        }
        .onChange(of: asrKey) { SettingsStore.asrApiKey = $0 }
    }

    private func fieldRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
