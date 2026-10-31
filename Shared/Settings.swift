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
        case "直击要害": return L("直击要害", "To the point", "要点だけ")
        case "详细": return L("详细", "Detailed", "詳しく")
        case "列要点": return L("列要点", "Key points", "要点を列挙")
        case "通俗": return L("通俗", "Plain words", "やさしく")
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

/// 中文打字时拼音显示在哪（F12）：上方一行（候选栏上面，照 iOS 原生，默认）；侧边（九宫格左列上三格换成拼音列，
/// 全键盘候选栏最左边一颗拼音键）。侧边模式不留拼音行，键盘矮 36。
enum PinyinDisplay: String, Codable, CaseIterable, Identifiable {
    case row, side

    var id: String { rawValue }

    var title: String { self == .row ? L("上方一行", "Row above", "上の行") : L("侧边", "Side", "横") }
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
    /// 问答风格（AI 栏蓝色那颗）：和改写的风格分开，一列名字 + 提示词，选中一条。旧版本没有，读的时候用默认四条。
    var answerStyles: [StylePreset] = StylePreset.answerDefaults
    var selectedAnswerStyleID: UUID?
    /// 联网倾向 0–4（问答提示词页那根条）：只管模型想不想联网，能不能联网仍看 webSearchMode。nil 当 2（适中）。
    var searchTendency: Int?

    // 键盘
    var inputLanguage: InputLanguage = .chinese
    var keyboardLayout: KeyboardLayout = .qwerty
    var pinyinDisplay: PinyinDisplay = .row
    /// 键盘底色用系统毛玻璃（#19 测试版）：顶边、底边都和系统那截玻璃接上，不留硬线。关掉回到不透明底色。
    var keyboardGlass: Bool = true
    /// 剪贴板实测（B1 第一步，临时）：键盘顶上出一条测试条，分别读 changeCount / hasStrings / 内容，看会不会弹「允许粘贴」。
    var clipboardProbe: Bool = false
    /// 繁体输出（B5）：候选、联想和上屏转成繁体；词库和学到的词照旧按简体存，AI 的结果不转。默认关。
    var traditionalOutput: Bool = false
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
    /// 识意问答联网（问答接口是千问、Kimi、智谱时）：模型说要查最新信息时怎么办。开：直接联网；每次询问：回答框里先问一次；
    /// 禁止：提示去开启。没选过时为 nil：App 启动后按店面定下来（中国大陆默认禁止，其他地区默认开）；键盘读到 nil 当禁止。
    /// 0.87 存的是布尔 webSearch，读的时候换过来。
    var webSearchMode: WebSearchMode?
    /// 问答用另一个接口：润色和识意改写走上面的接口（要快），识意问答走这一个（可以想久一点、联网）。
    /// 关着或没填好时问答也走润色的接口。API Key 单独存在钥匙串（SettingsStore.answerApiKey）。
    var separateAnswer: Bool = false
    var answerBaseURL: String = ""
    var answerModel: String = ""
    /// 已经部署进词库的模糊拼音。改了要重新部署才生效。
    var fuzzyPinyin: Set<FuzzyPinyin> = []
    var appearance: Appearance = .system

    enum CodingKeys: String, CodingKey {
        case baseURL, model, temperature, maxTokens, styles, selectedStyleID, answerStyles, selectedAnswerStyleID, searchTendency
        case inputLanguage, keyboardLayout, pinyinDisplay, keyboardGlass, clipboardProbe, traditionalOutput, keyHaptics, keySound, autoCapitalize, polishAnimation, fuzzyPinyin, appearance
        case resultKeyPrimary, resultKeySwipe, resultKeyWheelUp, longText, webSearchMode, separateAnswer, answerBaseURL, answerModel
    }

    private enum LegacyKeys: String, CodingKey { case webSearch }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var selectedStyle: StylePreset? {
        styles.first { $0.id == selectedStyleID } ?? styles.first
    }

    var selectedAnswerStyle: StylePreset? {
        answerStyles.first { $0.id == selectedAnswerStyleID } ?? answerStyles.first
    }

    /// 联网倾向，0–4，没设过是 2。
    var tendency: Int { min(max(searchTendency ?? 2, 0), 4) }
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
        answerStyles = (try? c.decodeIfPresent([StylePreset].self, forKey: .answerStyles)) ?? answerStyles
        selectedAnswerStyleID = try? c.decodeIfPresent(UUID.self, forKey: .selectedAnswerStyleID)
        searchTendency = try? c.decodeIfPresent(Int.self, forKey: .searchTendency)
        inputLanguage = (try? c.decodeIfPresent(InputLanguage.self, forKey: .inputLanguage)) ?? inputLanguage
        keyboardLayout = (try? c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout)) ?? keyboardLayout
        pinyinDisplay = (try? c.decodeIfPresent(PinyinDisplay.self, forKey: .pinyinDisplay)) ?? pinyinDisplay
        keyboardGlass = (try? c.decodeIfPresent(Bool.self, forKey: .keyboardGlass)) ?? keyboardGlass
        clipboardProbe = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardProbe)) ?? clipboardProbe
        traditionalOutput = (try? c.decodeIfPresent(Bool.self, forKey: .traditionalOutput)) ?? traditionalOutput
        keyHaptics = try c.decodeIfPresent(Bool.self, forKey: .keyHaptics) ?? keyHaptics
        keySound = try c.decodeIfPresent(Bool.self, forKey: .keySound) ?? keySound
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? autoCapitalize
        polishAnimation = try c.decodeIfPresent(Bool.self, forKey: .polishAnimation) ?? polishAnimation
        resultKeyPrimary = (try? c.decodeIfPresent(ResultKeyAction.self, forKey: .resultKeyPrimary)) ?? resultKeyPrimary
        // P1-4a：滑动方式和方向不再能设，一律上滑；之前选了弹出或下滑的，升级后不提示直接换成上滑。
        resultKeySwipe = .wheel
        resultKeyWheelUp = true
        longText = try c.decodeIfPresent(Bool.self, forKey: .longText) ?? longText
        webSearchMode = try? c.decodeIfPresent(WebSearchMode.self, forKey: .webSearchMode)
        if webSearchMode == nil, let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .webSearch) {
            webSearchMode = legacy ? .on : .off
        }
        separateAnswer = try c.decodeIfPresent(Bool.self, forKey: .separateAnswer) ?? separateAnswer
        answerBaseURL = try c.decodeIfPresent(String.self, forKey: .answerBaseURL) ?? answerBaseURL
        answerModel = try c.decodeIfPresent(String.self, forKey: .answerModel) ?? answerModel
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

    /// 问答风格的默认四条（规格「问答风格与联网提示词」第 1 节）。提示词空着时按「简短直接，几句话说清楚」回答。
    /// id 固定：旧设置里没有这一组时，App 和键盘各自读出来的默认四条是同一批，次数统计对得上。
    static let answerDefaults: [StylePreset] = [
        StylePreset(id: UUID(uuidString: "A5C0E001-0000-4000-8000-000000000001")!, name: "直击要害", prompt: "先给结论，直击要害，言简意赅。一般不超过三句，不铺垫、不重复问题、不加客套和免责声明。"),
        StylePreset(id: UUID(uuidString: "A5C0E001-0000-4000-8000-000000000002")!, name: "详细", prompt: "先给结论，再用几句话解释原因和要点，必要时举一个例子。"),
        StylePreset(id: UUID(uuidString: "A5C0E001-0000-4000-8000-000000000003")!, name: "列要点", prompt: "用「1.」「2.」分点回答，每点一句，最多五点。"),
        StylePreset(id: UUID(uuidString: "A5C0E001-0000-4000-8000-000000000004")!, name: "通俗", prompt: "像跟朋友解释一样，用大白话，少用术语，术语要顺带解释。"),
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
        else {
            // 第一次装：内测版填上自带的接口，其他版本照旧是空的。
            var settings = EnclaveSettings()
            BuiltinAPI.seed(&settings)
            return settings
        }
        settings.migrateRetiredModels()
        // 内测版接口页锁着：装在开发版上面时旧设置改不了，换成内置接口。
        if BuiltinAPI.needsReseed(settings) { BuiltinAPI.seed(&settings, force: true) }
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

    /// 问答接口的 API Key（单独设了问答接口时用）。
    static var answerApiKey: String? {
        get { Keychain.get("apiKey.answer") }
        set { Keychain.set(newValue, for: "apiKey.answer") }
    }

    /// 问答该用哪个 Key：单独设了问答接口用它的，否则和润色同一个。
    static func answerKey(for settings: EnclaveSettings) -> String? {
        settings.usesAnswerEndpoint ? answerApiKey : apiKey
    }

    // MARK: - 通过剪贴板同步（App Group 不可用时的兜底）

    private static let exportPrefix = "enclave-config:"

    private struct ExportPayload: Codable {
        var settings: EnclaveSettings
        var apiKey: String?
        var answerApiKey: String?
    }

    static func exportString() -> String? {
        let payload = ExportPayload(settings: load(), apiKey: apiKey, answerApiKey: answerApiKey)
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
        if let key = payload.answerApiKey { answerApiKey = key }
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

extension EnclaveSettings {
    /// Kimi 的 kimi-k 系列温度是固定的（填别的值会报错）：请求里不发温度，接口页的温度一行注明不生效。
    var usesFixedTemperature: Bool {
        baseURL.contains("moonshot.") && model.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("kimi-k")
    }
}

extension EnclaveSettings {
    /// 键盘出错卡里写的服务商名字：认得出的写服务商，自定义的写主机名。
    var providerName: String {
        let base = baseURL.lowercased()
        if base.contains("api.deepseek.com") { return "DeepSeek" }
        if base.contains("moonshot.") { return "Kimi" }
        if base.contains("dashscope") { return L("通义千问", "Qwen", "Qwen") }
        if base.contains("bigmodel.cn") || base.contains("api.z.ai") { return L("智谱", "Zhipu", "Zhipu") }
        if base.contains("tokenhub.tencentmaas.com") { return L("腾讯混元", "Tencent Hunyuan", "Tencent Hunyuan") }
        if base.contains("api.openai.com") { return "OpenAI" }
        if base.contains(":11434") { return "Ollama" }
        return URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host ?? baseURL
    }

    /// 连的是 Kimi（api.moonshot.cn / .ai）。
    var isKimi: Bool { baseURL.contains("moonshot.") }
    /// 这个接口能联网的话是哪一家：Kimi、千问（阿里云百炼）、智谱。别的服务商没有可用的联网接口，返回 nil。
    var searchProvider: SearchProvider? {
        if isKimi { return .kimi }
        if baseURL.contains("dashscope.aliyuncs.com") || baseURL.contains("dashscope-intl.aliyuncs.com") { return .qwen }
        if baseURL.contains("bigmodel.cn") || baseURL.contains("api.z.ai") { return .glm }
        if baseURL.contains("tokenhub.tencentmaas.com") { return .hunyuan }
        return nil
    }
    /// 联网确认卡上写的模型名：服务商预设的模型写模型名，自己改过的写「自定义模型」。
    var searchModelLabel: String {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let presets: Set<String> = ["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed", "qwen-plus", "glm-5.3", "hy3"]
        return presets.contains(name) ? name : L("自定义模型", "custom model", "カスタムモデル")
    }
    /// 识意问答联网用哪一家：问答走的接口能联网就有（三档里选了禁止也有，要联网时提示去开启）。
    var answerSearch: SearchProvider? { forAnswers.searchProvider }

    /// 问答真的走另一个接口：开着、地址和模型都填了。
    var usesAnswerEndpoint: Bool {
        separateAnswer && !answerBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !answerModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 问答用的设置：换成问答接口的地址和模型，温度、最大输出等照旧（Kimi K3 会先思考，最大输出至少 4096）。
    var forAnswers: EnclaveSettings {
        guard usesAnswerEndpoint else { return self }
        var copy = self
        copy.baseURL = answerBaseURL
        copy.model = answerModel
        // Kimi K3、智谱 GLM 会先思考，思考也算在最大输出里。
        if copy.usesFixedTemperature || copy.searchProvider == .glm { copy.maxTokens = max(copy.maxTokens, 4096) }
        return copy
    }
}

/// 识意问答联网的三档。
enum WebSearchMode: String, Codable, CaseIterable, Identifiable {
    case on, ask, off
    var id: Self { self }

    var title: String {
        switch self {
        case .on: return L("开", "On", "オン")
        case .ask: return L("每次询问", "Ask each time", "毎回確認")
        case .off: return L("禁止", "Off", "オフ")
        }
    }
}

/// 识意问答联网用哪一家的方式。
/// 三家都是模型先判断：第一行写「联网」才算要联网（三档在这一步起作用）。允许之后：
/// Kimi：键盘拿问题原文调 Kimi 的搜索接口（/tools/search），再带上资料问一次。
/// 千问（enable_search + forced_search）、智谱（web_search 工具）：服务商自带联网，只带问题原文再问一次，搜索词由服务商根据问题生成。
enum SearchProvider: String {
    case kimi, qwen, glm, hunyuan

    var name: String {
        switch self {
        case .kimi: return "Kimi"
        case .qwen: return L("通义千问", "Qwen", "Qwen")
        case .glm: return L("智谱", "Zhipu GLM", "Zhipu GLM")
        case .hunyuan: return L("腾讯混元", "Tencent Hunyuan", "Tencent Hunyuan")
        }
    }

    /// 大陆店面打开联网时确认框里写的公司全称（AP4）。
    var company: String {
        switch self {
        case .kimi: return "北京月之暗面科技有限公司"
        case .qwen: return "阿里云"
        case .glm: return "北京智谱华章科技股份有限公司"
        case .hunyuan: return "深圳市腾讯计算机系统有限公司"
        }
    }

    /// 服务商自带联网（一次请求里搜完答完），不用键盘另外去搜。
    var builtin: Bool { self != .kimi }
}
