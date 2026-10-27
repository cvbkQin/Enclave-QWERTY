import UIKit

struct StylePreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var prompt: String

    /// 界面上显示的名字：自带的 5 个风格按界面语言翻译，用户自己起的名字原样显示。提示词不翻。
    /// 默认那条叫「润色」（0.81 之前叫「自动」、显示成「润色」，名字和键盘上对不上，升级时改名）。
    var displayName: String {
        switch name {
        case "润色": return L("润色", "Polish", "整える")
        case "正式": return L("正式", "Formal", "丁寧")
        case "口语": return L("口语", "Casual", "カジュアル")
        case "简短": return L("简短", "Concise", "簡潔に")
        case "结构": return L("结构", "Bullets", "箇条書き")
        default:
            // 名字清空了也要能认出来：键盘面板里不能出现空的标签。
            return name.trimmingCharacters(in: .whitespaces).isEmpty ? L("未命名", "Untitled", "名前なし") : name
        }
    }
}

/// 键盘主要用哪种语言：中文（默认）、英文为主（每次弹出先是英文，中英键照常切）、只用英文（没有中英键）。
enum InputLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese
    case englishFirst
    case englishOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return L("中文", "Chinese", "中文")
        case .englishFirst: return L("英文为主", "English first", "英語中心")
        case .englishOnly: return L("只用英文", "English only", "英語のみ")
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
        case .qwerty: return L("全键盘（26 键）", "QWERTY", "QWERTY")
        case .nineKey: return L("九宫格", "10-key", "10キー")
        }
    }

    var shortTitle: String { self == .qwerty ? L("全键盘", "QWERTY", "QWERTY") : L("九宫格", "10-key", "10キー") }
}

/// 日间 / 夜间：跟随 iPhone，或者固定浅色、深色。只管 App；键盘跟着正在打字的 App 走，和系统键盘一样。
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("跟随系统", "Automatic", "自動")
        case .light: return L("浅色", "Light", "ライト")
        case .dark: return L("深色", "Dark", "ダーク")
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 结果卡左边那颗键点一下做什么，另一个按住滑过去。
enum ResultKeyAction: String, Codable, CaseIterable, Identifiable {
    case replace, insert

    var id: String { rawValue }
    var other: ResultKeyAction { self == .replace ? .insert : .replace }

    var title: String {
        switch self {
        case .replace: return L("替换", "Replace", "置き換え")
        case .insert: return L("插入", "Insert", "挿入")
        }
    }

    var systemImage: String { self == .replace ? "arrow.left.arrow.right" : "text.insert" }
}

/// 结果卡左边那颗键怎么换到另一个：滚轮（像拨号盘跟着手指转）或往下划弹出。
enum ResultKeySwipe: String, Codable, CaseIterable, Identifiable {
    case wheel, pop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wheel: return L("滚轮", "Wheel", "ホイール")
        case .pop: return L("弹出", "Pop-up", "ポップアップ")
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
    var inputLanguage: InputLanguage = .chinese
    var keyboardLayout: KeyboardLayout = .qwerty
    /// 按键震动（需要打开完全访问）。
    var keyHaptics: Bool = true
    /// 按键声音（手机静音时不响）。
    var keySound: Bool = true
    /// 英文输入时句首自动大写，和系统键盘一样。
    var autoCapitalize: Bool = true
    /// 润色时结果卡片的流光和星星动画；系统打开「减弱动态效果」时不播。
    var polishAnimation: Bool = true
    /// 结果卡左边的键：点一下是哪个（默认替换）、怎么滑到另一个、滚轮往哪边滑（true 上滑，另一个露在下面）。
    var resultKeyPrimary: ResultKeyAction = .replace
    var resultKeySwipe: ResultKeySwipe = .wheel
    var resultKeyWheelUp: Bool = true
    /// 处理长文本：关着（默认）时 AI 只读光标前 100 字左右的整句，打开后 200 字左右。
    var longText: Bool = false
    /// 已经部署进词库的模糊拼音。改了要重新部署才生效。
    var fuzzyPinyin: Set<FuzzyPinyin> = []
    var appearance: Appearance = .system

    enum CodingKeys: String, CodingKey {
        case baseURL, model, temperature, maxTokens, styles, selectedStyleID
        case inputLanguage, keyboardLayout, keyHaptics, keySound, autoCapitalize, polishAnimation, fuzzyPinyin, appearance
        case resultKeyPrimary, resultKeySwipe, resultKeyWheelUp, longText
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
        // 默认那条以前叫「自动」，键盘上却显示「润色」：改名成「润色」，App 里和键盘上一致。
        // 提示词改过、名字前后带空格的也改（0.81 只改了提示词为空的，有人键盘上还是「自动」）；已经有「润色」就不动。
        if !styles.contains(where: { $0.name == "润色" }),
           let index = styles.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == "自动" }) {
            styles[index].name = "润色"
        }
        inputLanguage = (try? c.decodeIfPresent(InputLanguage.self, forKey: .inputLanguage)) ?? inputLanguage
        keyboardLayout = (try? c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout)) ?? keyboardLayout
        keyHaptics = try c.decodeIfPresent(Bool.self, forKey: .keyHaptics) ?? keyHaptics
        keySound = try c.decodeIfPresent(Bool.self, forKey: .keySound) ?? keySound
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? autoCapitalize
        polishAnimation = try c.decodeIfPresent(Bool.self, forKey: .polishAnimation) ?? polishAnimation
        resultKeyPrimary = (try? c.decodeIfPresent(ResultKeyAction.self, forKey: .resultKeyPrimary)) ?? resultKeyPrimary
        resultKeySwipe = (try? c.decodeIfPresent(ResultKeySwipe.self, forKey: .resultKeySwipe)) ?? resultKeySwipe
        resultKeyWheelUp = try c.decodeIfPresent(Bool.self, forKey: .resultKeyWheelUp) ?? resultKeyWheelUp
        longText = try c.decodeIfPresent(Bool.self, forKey: .longText) ?? longText
        fuzzyPinyin = (try? c.decodeIfPresent(Set<FuzzyPinyin>.self, forKey: .fuzzyPinyin)) ?? fuzzyPinyin
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? appearance
    }
}

extension StylePreset {
    /// 键盘上的风格标签。「润色」没有额外要求，由润色 prompt 按内容决定排版。
    /// 场景化的写法（邮件、周报等）由用户自己在 App 里添加。
    static let defaults: [StylePreset] = [
        StylePreset(name: "润色", prompt: ""),
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
    /// 键盘「要求」框里的字。使用指引「一键应用」从 App 里写进来，键盘下次出现时读到。
    static let instructionKey = "instruction.v1"

    static func load() -> EnclaveSettings {
        guard let data = SharedStorage.defaults.data(forKey: settingsKey),
              var settings = try? JSONDecoder().decode(EnclaveSettings.self, from: data)
        else { return EnclaveSettings() }
        settings.migrateRetiredModels()
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

extension EnclaveSettings {
    /// DeepSeek 的旧模型名 deepseek-chat / deepseek-reasoner 在 2026-07-24 停用，现在官方只有
    /// deepseek-flash 和 deepseek-v4-pro。还存着旧名的，读设置时换成 deepseek-flash（地址不变）。
    static let retiredDeepSeekModels: Set<String> = ["deepseek-chat", "deepseek-reasoner", "deepseek-v4-flash"]

    mutating func migrateRetiredModels() {
        guard baseURL.contains("api.deepseek.com"),
              Self.retiredDeepSeekModels.contains(model.trimmingCharacters(in: .whitespaces).lowercased()) else { return }
        model = "deepseek-flash"
    }
}
