import Foundation

struct StylePreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var prompt: String
}

struct EnclaveSettings: Codable, Equatable {
    /// OpenAI 兼容接口的 base URL，例如 https://api.deepseek.com/v1 或 http://100.x.x.x:11434/v1
    var baseURL: String = ""
    var model: String = ""
    var temperature: Double = 0.3
    var maxTokens: Int = 1024
    var styles: [StylePreset] = StylePreset.defaults
    var selectedStyleID: UUID?

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var selectedStyle: StylePreset? {
        styles.first { $0.id == selectedStyleID } ?? styles.first
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
