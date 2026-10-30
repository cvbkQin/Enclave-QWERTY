import Foundation
import StoreKit

// 服务商预设（从 SettingsView.swift 挪出来，单元测试也编它）。

/// 首页「接口」小卡上的服务商名字：认得出的写服务商，自定义的写地址里的主机名。
enum ProviderName {
    static func of(_ baseURL: String) -> String {
        let provider = Provider.detect(baseURL)
        guard provider == .custom else { return provider.title }
        return URL(string: baseURL)?.host ?? provider.title
    }
}

/// 常用服务商，选了自动填地址和模型。
/// 所有地区都列 DeepSeek、Kimi、通义千问，加上跑在自己电脑上的 Ollama（0.86 起，原来只有中国大陆店面这样）；
/// 没有「自定义」卡片，自己改了地址或模型就四个都不选中，算自定义。OpenAI 和自定义只留着认旧设置的地址。
enum Provider: CaseIterable, Identifiable {
    case deepseek, openai, kimi, qwen, glm, hunyuan, ollama, custom

    /// 服务商卡片按这个顺序排，2×2。
    static let shown: [Provider] = [.deepseek, .kimi, .qwen, .ollama]
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
        if baseURL.contains("dashscope.aliyuncs.com") || baseURL.contains("dashscope-intl.aliyuncs.com") { return .qwen }
        if baseURL.contains("bigmodel.cn") || baseURL.contains("api.z.ai") { return .glm }
        if baseURL.contains("tokenhub.tencentmaas.com") { return .hunyuan }
        if baseURL.contains(":11434") { return .ollama }
        return .custom
    }
}
