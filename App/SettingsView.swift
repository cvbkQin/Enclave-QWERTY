import SwiftUI
import UIKit

struct SettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var apiKey = SettingsStore.apiKey ?? ""
    @State private var testState: TestState = .idle
    @State private var copied = false

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PlaygroundView()
                    } label: {
                        Label("试一试键盘", systemImage: "keyboard")
                    }
                }
                VoiceSessionSection()
                PinyinSection()
                apiSection
                testSection
                styleSection
                VoiceSettingsSection(settings: $settings)
                syncSection
                SetupGuideSection()
            }
            .navigationTitle("Enclave")
            .onChange(of: settings) { SettingsStore.save($0) }
            .onChange(of: apiKey) { SettingsStore.apiKey = $0 }
        }
    }

    private var apiSection: some View {
        Section {
            LabeledField(title: "API 地址", text: $settings.baseURL, placeholder: "https://api.deepseek.com/v1", keyboard: .URL)
            LabeledField(title: "模型", text: $settings.model, placeholder: "deepseek-chat")
            HStack {
                Text("API Key")
                SecureField("自建服务可以留空", text: $apiKey)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Stepper(value: $settings.temperature, in: 0...1.5, step: 0.1) {
                HStack {
                    Text("温度")
                    Spacer()
                    Text(settings.temperature, format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $settings.maxTokens, in: 256...8192, step: 256) {
                HStack {
                    Text("最大输出")
                    Spacer()
                    Text("\(settings.maxTokens) tokens").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("模型接口（OpenAI 兼容）")
        } footer: {
            Text("支持任何 OpenAI 兼容接口：第三方 API、自建 Ollama / vLLM / LM Studio。地址填到 /v1 为止。API Key 只存在本机钥匙串里。")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await runTest() }
            } label: {
                HStack {
                    Text("测试连接")
                    Spacer()
                    if testState == .running { ProgressView() }
                }
            }
            .disabled(!settings.isConfigured || testState == .running)

            switch testState {
            case .success(let reply):
                Text("连接成功：\(reply)").font(.footnote).foregroundStyle(.green)
            case .failure(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    private var styleSection: some View {
        Section {
            Picker("默认风格", selection: Binding(
                get: { settings.selectedStyle?.id ?? UUID() },
                set: { settings.selectedStyleID = $0 }
            )) {
                ForEach(settings.styles) { Text($0.name).tag($0.id) }
            }
            NavigationLink("编辑风格预设") {
                StylesView(styles: $settings.styles)
            }
        } header: {
            Text("风格")
        } footer: {
            Text("风格会加到每次请求的系统提示里，键盘顶部也可以随时切换。")
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Text("App 与键盘共享配置")
                Spacer()
                Text(SharedStorage.isShared ? "已开启" : "不可用")
                    .foregroundStyle(SharedStorage.isShared ? .green : .orange)
            }
            if !SharedStorage.isShared {
                Button(copied ? "已复制，去键盘里点「从剪贴板导入配置」" : "复制配置") {
                    if let string = SettingsStore.exportString() {
                        UIPasteboard.general.string = string
                        copied = true
                    }
                }
            }
        } footer: {
            if !SharedStorage.isShared {
                Text("当前签名没有拿到 App Group，键盘读不到这里的设置。复制配置后在键盘里导入，导入后剪贴板会自动清空。")
            }
        }
    }

    private func runTest() async {
        testState = .running
        let client = LLMClient(settings: settings, apiKey: apiKey)
        var raw = ""
        do {
            for try await piece in client.stream([.user("只回复两个字：你好")]) {
                raw += piece
            }
            let reply = ModelOutput.clean(raw)
            testState = reply.isEmpty ? .failure("连上了，但模型没有返回内容。") : .success(String(reply.prefix(40)))
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

private struct LabeledField: View {
    var title: String
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(title)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct SetupGuideSection: View {
    var body: some View {
        Section("开启键盘") {
            Text("1. 打开 设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选择 Enclave。")
            Text("2. 点进 Enclave，打开「允许完全访问」。键盘需要它才能联网调用你的模型。")
            Text("3. 在任意输入框长按或点地球键切到 Enclave。")
            Text("用法：在输入框写原话，点「执行」润色；写「原话 // 要求」按要求改；只写「// 要求」让它帮你写。满意后点「替换」或「插入」，发送仍由你自己按。")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}
