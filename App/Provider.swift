import Foundation
import StoreKit

// 服务商预设（从 SettingsView.swift 挪出来，单元测试也编它）。

/// 首页「接口」小卡上的服务商名字：认得出的写服务商，自定义的写地址里的主机名。
enum ProviderName {
    /// 带上模型时：这一组地址和模型存过预设，就写预设的名字。
    static func of(_ baseURL: String, model: String) -> String {
        SavedAPIStore.name(baseURL: baseURL, model: model) ?? of(baseURL)
    }

    static func of(_ baseURL: String) -> String {
        let provider = Provider.detect(baseURL)
        guard provider == .custom else { return provider.title }
        return URL(string: baseURL)?.host ?? provider.title
    }
}

/// 常用服务商，选了自动填地址和模型。
/// 润色页列 DeepSeek、Kimi、通义千问、智谱 GLM，下面一张整行「自定义」（Ollama、vLLM、LM Studio，11-01 起 Ollama 不再单列）；
/// 自己改了地址或模型就四个都不选中，算自定义。OpenAI、Ollama 只留着认旧设置的地址。
enum Provider: CaseIterable, Identifiable {
    case deepseek, openai, kimi, qwen, glm, hunyuan, ollama, custom

    /// 服务商卡片按这个顺序排，2×2。
    static let shown: [Provider] = [.deepseek, .kimi, .qwen, .glm]
    /// 问答页的服务商：四家都能联网（千问、Kimi、智谱、腾讯混元）。都是国内已备案的服务商。
    /// DeepSeek 不能联网，0.93 起问答页不再列（cvbk）；已经填了 DeepSeek 的照样能用，只是四个都不选中。
    static let answerShown: [Provider] = [.qwen, .kimi, .glm, .hunyuan]
    /// 引导里选服务商（TU0）：前四家有分步教程，Ollama、其他直接去接口页。
    static let guideShown: [Provider] = [.deepseek, .kimi, .qwen, .glm, .ollama, .custom]

    /// 现在填的地址和模型对得上哪个预设：地址和模型都和预设一样才算；Ollama 只认 11434 端口（IP 本来就要改）。
    /// 对不上时返回 nil（四个都不选中）。answer：按问答页的预设比（Kimi 问答用 K3）。
    static func matching(baseURL: String, model: String, answer: Bool = false) -> Provider? {
        func trimmed(_ text: String) -> String {
            var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.hasSuffix("/") { text.removeLast() }
            return text
        }
        let found = (answer ? answerShown : shown).first { provider in
            if provider == .ollama { return baseURL.contains(":11434") }
            guard let preset = answer ? provider.answerPreset : provider.preset else { return false }
            // Kimi、千问、智谱的国内、国际两个地址都算（两边的 Key 不通用）。
            let urls = provider == .kimi ? [Provider.kimiChina, Provider.kimiGlobal]
                : provider == .qwen ? [Provider.qwenChina, Provider.qwenGlobal]
                : provider == .glm ? [Provider.glmChina, Provider.glmGlobal] : [preset.baseURL]
            return urls.contains(trimmed(baseURL)) && trimmed(model) == preset.model
        }
        return found
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .kimi: return "Kimi"
        case .qwen: return L("通义千问", "Qwen", "Qwen")
        case .glm: return L("智谱 GLM", "Zhipu GLM", "Zhipu GLM")
        case .hunyuan: return L("腾讯混元", "Tencent Hunyuan", "Tencent Hunyuan")
        case .ollama: return "Ollama"
        case .custom: return L("自定义", "Custom", "カスタム")
        }
    }

    /// 卡片上名字下面的灰字（AP1、AP2）。
    var subtitle: String {
        switch self {
        case .deepseek: return "api.deepseek.com"
        case .openai: return "api.openai.com"
        case .kimi: return L("月之暗面开放平台", "Moonshot AI platform", "Moonshot AI プラットフォーム")
        case .qwen: return L("阿里云百炼", "Alibaba Cloud Model Studio", "Alibaba Cloud Model Studio")
        case .glm: return L("智谱开放平台", "Z.ai platform", "Z.ai プラットフォーム")
        case .hunyuan: return L("腾讯云 TokenHub", "Tencent Cloud TokenHub", "Tencent Cloud TokenHub")
        case .ollama: return L("自己电脑上", "Your own computer", "自分のパソコン")
        case .custom: return "vLLM、LM Studio"
        }
    }

    /// Kimi 国内站（platform.moonshot.cn）和国际站（platform.moonshot.ai）的 Key 不通用：大陆店面填 .cn，其他地区填 .ai。
    static let kimiChina = "https://api.moonshot.cn/v1"
    static let kimiGlobal = "https://api.moonshot.ai/v1"
    /// Kimi 预设：润色用高速版（能力一样、快 2～3 倍），单独设问答接口时问答用 K3。
    static let kimiAnswerModel = "kimi-k3.1-pro"
    /// 千问（阿里云百炼）同样分国内站和国际站（新加坡）。
    static let qwenChina = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    static let qwenGlobal = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    /// 智谱：国内开放平台（open.bigmodel.cn）和国际站 Z.ai。
    static let glmChina = "https://open.bigmodel.cn/api/paas/v4"
    static let glmGlobal = "https://api.z.ai/api/paas/v4"
    /// 腾讯混元：腾讯云 TokenHub 的 OpenAI 兼容接口，只有一个站。
    static let hunyuanURL = "https://tokenhub.tencentmaas.com/v1"

    var preset: (baseURL: String, model: String)? {
        switch self {
        case .deepseek: return ("https://api.deepseek.com/v1", "deepseek-flash")
        case .openai: return ("https://api.openai.com/v1", "gpt-4o-mini")
        case .kimi: return (Storefront.isMainlandChina ? Self.kimiChina : Self.kimiGlobal, "kimi-k3.1-pro-highspeed")
        case .qwen: return (Storefront.isMainlandChina ? Self.qwenChina : Self.qwenGlobal, "qwen-plus")
        case .glm: return (Storefront.isMainlandChina ? Self.glmChina : Self.glmGlobal, "glm-5.3")
        case .hunyuan: return (Self.hunyuanURL, "hy3")
        case .ollama: return ("http://192.168.1.100:11434/v1", "qwen2.5:7b")
        case .custom: return nil
        }
    }

    /// 问答页的预设：Kimi 用 K3（润色的预设是更快的高速版），别的和润色一样。千问 qwen-plus 支持联网。
    var answerPreset: (baseURL: String, model: String)? {
        guard let preset else { return nil }
        return self == .kimi ? (preset.baseURL, Self.kimiAnswerModel) : preset
    }

    /// 问答能联网（千问、Kimi、智谱、腾讯混元）。
    var canSearch: Bool { self == .kimi || self == .qwen || self == .glm || self == .hunyuan }

    /// 选这个服务商时最大输出填多少（Kimi K3、智谱会先思考，思考也算在里面）。
    var maxTokens: Int { self == .kimi || self == .glm ? 4096 : EnclaveSettings().maxTokens }

    static func detect(_ baseURL: String) -> Provider {
        if baseURL.contains("api.deepseek.com") { return .deepseek }
        if baseURL.contains("api.openai.com") { return .openai }
        if baseURL.contains("api.moonshot.cn") || baseURL.contains("api.moonshot.ai") { return .kimi }
        if EnclaveSettings.isQwen(baseURL) { return .qwen }
        if baseURL.contains("bigmodel.cn") || baseURL.contains("api.z.ai") { return .glm }
        if baseURL.contains("tokenhub.tencentmaas.com") { return .hunyuan }
        if baseURL.contains(":11434") { return .ollama }
        return .custom
    }
}

/// 「添加配置」里的服务商模板（CF2）：只用来新建时预填地址和推荐模型，之后改什么只改这一条配置。
/// 千问分两个平台：阿里云百炼和千问 AI 平台，两边的 Key 不通用，在哪儿申请的 Key 就选哪个。
enum ConfigTemplate: String, CaseIterable, Identifiable {
    case deepseek, kimi, qwenBailian, qwenAI, glm, hunyuan, custom

    var id: String { rawValue }

    /// 「选一家服务商」分组里的几家（自定义另起一组）。
    static let providers: [ConfigTemplate] = [.deepseek, .kimi, .qwenBailian, .qwenAI, .glm, .hunyuan]

    static let qwenAIURL = "https://maas.qianwenaiapi.com/compatible-mode/v1"

    /// logo、教程、能力按哪一家算。
    var provider: Provider {
        switch self {
        case .deepseek: return .deepseek
        case .kimi: return .kimi
        case .qwenBailian, .qwenAI: return .qwen
        case .glm: return .glm
        case .hunyuan: return .hunyuan
        case .custom: return .custom
        }
    }

    var title: String {
        switch self {
        case .qwenBailian: return L("千问（阿里云百炼）", "Qwen (Alibaba Cloud Model Studio)", "Qwen（Alibaba Cloud Model Studio）")
        case .qwenAI: return L("千问 AI 平台", "Qwen AI Platform", "Qwen AI プラットフォーム")
        default: return provider.title
        }
    }

    /// 新建时名字的默认值：服务商名（千问两个平台都叫「千问」再看重名）。
    var defaultName: String {
        switch self {
        case .qwenBailian, .qwenAI: return L("千问", "Qwen", "Qwen")
        case .custom: return L("自定义", "Custom", "カスタム")
        default: return provider.title
        }
    }

    /// 平台名（配置页顶部服务商卡的灰字）。
    var platform: String {
        switch self {
        case .deepseek: return L("DeepSeek 开放平台", "DeepSeek platform", "DeepSeek プラットフォーム")
        case .kimi: return L("月之暗面", "Moonshot AI", "Moonshot AI")
        case .qwenBailian: return L("阿里云百炼", "Alibaba Cloud Model Studio", "Alibaba Cloud Model Studio")
        case .qwenAI: return L("千问 AI 平台", "Qwen AI Platform", "Qwen AI プラットフォーム")
        case .glm: return L("智谱开放平台", "Z.ai platform", "Z.ai プラットフォーム")
        case .hunyuan: return L("腾讯云 TokenHub", "Tencent Cloud TokenHub", "Tencent Cloud TokenHub")
        case .custom: return L("自己搭的服务", "Self-hosted", "セルフホスト")
        }
    }

    var baseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .kimi: return Storefront.isMainlandChina ? Provider.kimiChina : Provider.kimiGlobal
        case .qwenBailian: return Storefront.isMainlandChina ? Provider.qwenChina : Provider.qwenGlobal
        case .qwenAI: return Self.qwenAIURL
        case .glm: return Storefront.isMainlandChina ? Provider.glmChina : Provider.glmGlobal
        case .hunyuan: return Provider.hunyuanURL
        case .custom: return ""
        }
    }

    /// 推荐模型（CF2）。
    var model: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .kimi: return Provider.kimiAnswerModel
        case .qwenBailian, .qwenAI: return "qwen-flash"
        case .glm: return "glm-5-flash"
        case .hunyuan: return "hy3"
        case .custom: return ""
        }
    }

    /// 副标题：「地址或平台名 · 推荐模型」。
    var subtitle: String {
        switch self {
        case .deepseek: return "api.deepseek.com · " + model
        case .kimi: return L("月之暗面", "Moonshot AI", "Moonshot AI") + " · " + model
        case .qwenBailian: return "dashscope.aliyuncs.com · " + model
        case .qwenAI: return "maas.qianwenaiapi.com · " + model
        case .glm: return L("智谱开放平台", "Z.ai platform", "Z.ai") + " · " + model
        case .hunyuan: return L("腾讯云 TokenHub", "Tencent Cloud TokenHub", "Tencent Cloud TokenHub") + " · " + model
        case .custom: return L("Ollama、vLLM、LM Studio，或任何 OpenAI 兼容地址", "Ollama, vLLM, LM Studio, or any OpenAI-compatible URL", "Ollama、vLLM、LM Studio、または OpenAI 互換の URL")
        }
    }

    /// Kimi K3、智谱会先思考，思考也算在最多字数里。
    var maxTokens: Int { provider.maxTokens }

    /// 旧配置没记模板：按地址认（千问 AI 平台的地址单独认）。
    static func detect(_ baseURL: String) -> ConfigTemplate {
        if baseURL.lowercased().contains("qianwenaiapi.com") { return .qwenAI }
        switch Provider.detect(baseURL) {
        case .deepseek: return .deepseek
        case .kimi: return .kimi
        case .qwen: return .qwenBailian
        case .glm: return .glm
        case .hunyuan: return .hunyuan
        default: return .custom
        }
    }

    static func of(_ config: SavedAPI) -> ConfigTemplate {
        config.template.flatMap(ConfigTemplate.init(rawValue:)) ?? detect(config.baseURL)
    }
}
