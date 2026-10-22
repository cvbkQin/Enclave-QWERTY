import Foundation

struct StylePreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var prompt: String
}

enum ASRProvider: String, Codable, CaseIterable, Identifiable {
    /// 苹果语音识别，默认只用本机离线识别。
    case apple
    /// OpenAI 兼容的 /audio/transcriptions 接口，例如自建的 Whisper / SenseVoice。
    case custom

    var id: String { rawValue }
}

/// 语音会话怎么让 App 在后台待命。
enum VoiceSessionStyle: String, Codable, CaseIterable, Identifiable {
    /// 画中画小窗让 App 保持运行，只在说话时打开麦克风，平时状态栏没有橙点。
    case pip
    /// 麦克风一直开着（音频后台模式），会话期间一直有橙点。
    case alwaysOnMic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pip: return "悬浮窗模式"
        case .alwaysOnMic: return "常驻麦克风"
        }
    }
}

enum KeyboardLayout: String, Codable, CaseIterable, Identifiable {
    /// 全键盘，26 个字母键。
    case qwerty
    /// 九宫格拼音。
    case nineKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwerty: return "全键盘（26 键）"
        case .nineKey: return "九宫格"
        }
    }
}

struct EnclaveSettings: Codable, Equatable {
    /// OpenAI 兼容接口的 base URL，例如 https://api.deepseek.com/v1 或 http://100.x.x.x:11434/v1
    var baseURL: String = ""
    var model: String = ""
    var temperature: Double = 0.3
    var maxTokens: Int = 1024
    var styles: [StylePreset] = StylePreset.defaults
    var selectedStyleID: UUID?

    // 语音输入
    var asrProvider: ASRProvider = .apple
    /// 设备不支持中文离线识别时，是否允许改用苹果服务器识别。
    var allowAppleServerASR: Bool = false
    var asrBaseURL: String = ""
    var asrModel: String = "whisper-1"
    /// 麦克风会话闲置多久后自动结束，0 表示不自动结束。
    var voiceSessionMinutes: Int = 15
    var voiceSessionStyle: VoiceSessionStyle = .pip
    /// 说完后自动润色到预览区。
    var autoPolishAfterVoice: Bool = true

    // 键盘
    var keyboardLayout: KeyboardLayout = .qwerty
    /// 按键震动（需要打开完全访问）。
    var keyHaptics: Bool = true
    /// 按键声音（手机静音时不响）。
    var keySound: Bool = true

    enum CodingKeys: String, CodingKey {
        case baseURL, model, temperature, maxTokens, styles, selectedStyleID
        case asrProvider, allowAppleServerASR, asrBaseURL, asrModel, voiceSessionMinutes, voiceSessionStyle, autoPolishAfterVoice
        case keyboardLayout, keyHaptics, keySound
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var selectedStyle: StylePreset? {
        styles.first { $0.id == selectedStyleID } ?? styles.first
    }
}

extension EnclaveSettings {
    /// 逐项解码，缺失的字段用默认值，这样旧版本存的设置升级后不会丢。
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? baseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? temperature
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? maxTokens
        styles = try c.decodeIfPresent([StylePreset].self, forKey: .styles) ?? styles
        selectedStyleID = try c.decodeIfPresent(UUID.self, forKey: .selectedStyleID)
        asrProvider = (try? c.decodeIfPresent(ASRProvider.self, forKey: .asrProvider)) ?? asrProvider
        allowAppleServerASR = try c.decodeIfPresent(Bool.self, forKey: .allowAppleServerASR) ?? allowAppleServerASR
        asrBaseURL = try c.decodeIfPresent(String.self, forKey: .asrBaseURL) ?? asrBaseURL
        asrModel = try c.decodeIfPresent(String.self, forKey: .asrModel) ?? asrModel
        voiceSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .voiceSessionMinutes) ?? voiceSessionMinutes
        voiceSessionStyle = (try? c.decodeIfPresent(VoiceSessionStyle.self, forKey: .voiceSessionStyle)) ?? voiceSessionStyle
        autoPolishAfterVoice = try c.decodeIfPresent(Bool.self, forKey: .autoPolishAfterVoice) ?? autoPolishAfterVoice
        keyboardLayout = (try? c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout)) ?? keyboardLayout
        keyHaptics = try c.decodeIfPresent(Bool.self, forKey: .keyHaptics) ?? keyHaptics
        keySound = try c.decodeIfPresent(Bool.self, forKey: .keySound) ?? keySound
    }
}

extension StylePreset {
    static let defaults: [StylePreset] = [
        StylePreset(name: "聊天", prompt: "场景是微信等即时聊天。语气自然口语化，句子简短，不要用书面套话。"),
        StylePreset(name: "邮件", prompt: "场景是工作邮件。语气礼貌、清晰、专业，结构分明。"),
        StylePreset(name: "汇报", prompt: "场景是向上级汇报工作。先说结论，再说要点，简洁具体。"),
    ]
}

/// 设置和 API key 的读写。API key 只存钥匙串，不进 UserDefaults。
enum SettingsStore {
    private static let settingsKey = "settings.v1"
    private static let apiKeyAccount = "apiKey"
    private static let asrApiKeyAccount = "asrApiKey"

    static func load() -> EnclaveSettings {
        guard let data = SharedStorage.defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(EnclaveSettings.self, from: data)
        else { return EnclaveSettings() }
        return settings
    }

    static func save(_ settings: EnclaveSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            SharedStorage.defaults.set(data, forKey: settingsKey)
        }
    }

    static var apiKey: String? {
        get { Keychain.get(apiKeyAccount) }
        set { Keychain.set(newValue, for: apiKeyAccount) }
    }

    static var asrApiKey: String? {
        get { Keychain.get(asrApiKeyAccount) }
        set { Keychain.set(newValue, for: asrApiKeyAccount) }
    }

    // MARK: - 通过剪贴板同步（App Group 不可用时的兜底）

    private static let exportPrefix = "enclave-config:"

    private struct ExportPayload: Codable {
        var settings: EnclaveSettings
        var apiKey: String?
    }

    static func exportString() -> String? {
        let payload = ExportPayload(settings: load(), apiKey: apiKey)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return exportPrefix + data.base64EncodedString()
    }

    /// 导入成功返回 true。
    @discardableResult
    static func importString(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(exportPrefix),
              let data = Data(base64Encoded: String(trimmed.dropFirst(exportPrefix.count))),
              let payload = try? JSONDecoder().decode(ExportPayload.self, from: data)
        else { return false }
        save(payload.settings)
        apiKey = payload.apiKey
        return true
    }
}
