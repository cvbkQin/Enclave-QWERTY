import Foundation

struct StylePreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var prompt: String
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

    // 键盘
    var keyboardLayout: KeyboardLayout = .qwerty
    /// 按键震动（需要打开完全访问）。
    var keyHaptics: Bool = true
    /// 按键声音（手机静音时不响）。
    var keySound: Bool = true
    /// 润色时结果卡片的流光和星星动画；系统打开「减弱动态效果」时不播。
    var polishAnimation: Bool = true

    enum CodingKeys: String, CodingKey {
        case baseURL, model, temperature, maxTokens, styles, selectedStyleID
        case keyboardLayout, keyHaptics, keySound, polishAnimation
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
        // 用户没改过的旧默认列表，升级成新的默认列表。
        let current = styles.map { [$0.name, $0.prompt] }
        if StylePreset.legacyDefaults.contains(where: { $0.map { [$0.name, $0.prompt] } == current }) {
            styles = StylePreset.defaults
            selectedStyleID = nil
        }
        keyboardLayout = (try? c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout)) ?? keyboardLayout
        keyHaptics = try c.decodeIfPresent(Bool.self, forKey: .keyHaptics) ?? keyHaptics
        keySound = try c.decodeIfPresent(Bool.self, forKey: .keySound) ?? keySound
        polishAnimation = try c.decodeIfPresent(Bool.self, forKey: .polishAnimation) ?? polishAnimation
    }
}

extension StylePreset {
    /// 键盘上的风格标签。「自动」没有额外要求，由润色 prompt 按内容决定排版。
    /// 场景化的写法（邮件、周报等）由用户自己在 App 里添加。
    static let defaults: [StylePreset] = [
        StylePreset(name: "自动", prompt: ""),
        StylePreset(name: "正式", prompt: "风格：正式。用书面、得体、礼貌的表达，适合工作沟通和对外发送；不用口语词、语气词和表情。"),
        StylePreset(name: "口语", prompt: "风格：口语。像本人平时说话一样自然随意，句子简短；不加标题、不分点编号，不用书面套话。"),
        StylePreset(name: "简短", prompt: "风格：简短。只保留核心意思，删掉客套、铺垫和重复，能一句说清就只写一句。"),
        StylePreset(name: "结构", prompt: "风格：结构。提炼原文里的关键信息，删掉无关细节和铺垫，整理成「1.」「2.」「3.」编号要点，每点一行、一句话说清；要点较多且能归类时先分组，每组一行小标题，组内编号。即使原文很短也按要点列出。"),
    ]

    /// 以前各版的默认风格，用户没改过时升级成新的默认列表。
    static let legacyDefaults: [[(name: String, prompt: String)]] = [
        [
            ("聊天", "场景是微信等即时聊天。语气自然口语化，句子简短，不要用书面套话。"),
            ("邮件", "场景是工作邮件。语气礼貌、清晰、专业，结构分明。"),
            ("汇报", "场景是向上级汇报工作。先说结论，再说要点，简洁具体。"),
        ],
        [
            ("自动", ""),
            ("消息", "场景是微信等即时聊天消息。语气自然，句子简短，像本人在说话；不加标题、不分点编号，不用书面套话。"),
            ("邮件", "场景是工作邮件。开头一句称呼问候，正文分段、礼貌清晰；结尾署名只在用户提到自己名字时才加，否则不加署名。"),
            ("周报", "场景是工作周报。第一行写标题，然后按「本周进展：」「问题：」「下周计划：」分组，组内用「1.」「2.」编号；原文没有提到的组省略，不要编造内容。"),
            ("纪要", "场景是会议纪要。第一行写会议主题作标题，然后分「结论：」和「待办：」两组编号列出；待办里原文提到负责人或时间的写在后面，没提到的不要编。"),
        ],
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
