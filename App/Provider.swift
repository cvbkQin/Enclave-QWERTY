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
        // 新加的几家（豆包、文心…）和 LM Studio 写服务商名。
        let template = ConfigTemplate.detect(baseURL)
        if template != .custom { return template.defaultName }
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
    /// 引导「填写服务商」下面的「推荐」（NC3）：前四家有分步教程，Ollama 直接进新建配置页。
    static let guideShown: [Provider] = [.deepseek, .kimi, .qwen, .glm, .ollama]

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

    /// Kimi 中国大陆站（platform.moonshot.cn）和非中国大陆站（platform.moonshot.ai）的 Key 不通用：大陆店面填 .cn，其他地区填 .ai。
    static let kimiChina = "https://api.moonshot.cn/v1"
    static let kimiGlobal = "https://api.moonshot.ai/v1"
    /// Kimi 预设：润色用高速版（能力一样、快 2～3 倍），单独设问答接口时问答用 K3。
    static let kimiAnswerModel = "kimi-k3.1-pro"
    /// 千问（阿里云百炼）同样分中国大陆站和非中国大陆站（新加坡）。
    static let qwenChina = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    static let qwenGlobal = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    /// 智谱：中国大陆开放平台（open.bigmodel.cn）和非中国大陆的 Z.ai。
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

/// 同一家服务商的中国大陆站和非中国大陆站是两个平台，Key 不通用（T102）。
/// 只有一个地址、两边都能用的（DeepSeek、本机服务）是「通用」。
enum APISide: String, Hashable {
    case global, china, universal

    /// 标签上的字（和整句模型下载线路一样，非中国大陆在前）。
    var label: String {
        switch self {
        case .global: return L("非中国大陆", "Outside Mainland China", "中国本土以外")
        case .china: return L("中国大陆", "Mainland China", "中国本土")
        case .universal: return L("通用", "All regions", "共通")
        }
    }

    /// 没别的线索时按 App Store 地区。
    static var storefront: APISide { Storefront.isMainlandChina ? .china : .global }
}

/// 「常用 API 地址」里的一个地址按钮。
struct APIEndpoint: Hashable {
    let side: APISide
    let url: String

    var host: String {
        guard let url = URL(string: url), let host = url.host else { return self.url }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

extension Provider {
    /// Kimi、千问（百炼）、智谱有中国大陆、非中国大陆两个站（教程顶上能切换）。
    var hasSides: Bool { self == .kimi || self == .qwen || self == .glm }

    /// 这一边的地址；只有一个站的不管 side。
    func baseURL(side: APISide?) -> String? {
        let china = (side ?? .storefront) == .china
        switch self {
        case .kimi: return china ? Self.kimiChina : Self.kimiGlobal
        case .qwen: return china ? Self.qwenChina : Self.qwenGlobal
        case .glm: return china ? Self.glmChina : Self.glmGlobal
        default: return preset?.baseURL
        }
    }

    /// 地址是哪一边的：认不出（或只有一个站）是 nil。
    static func side(of baseURL: String) -> APISide? {
        let template = ConfigTemplate.detect(baseURL)
        guard template.provider.hasSides else { return nil }
        return template.side(of: baseURL)
    }
}

/// 常用服务商（T102「常用 API 地址」）：按地址认是哪家，列出每家中国大陆、非中国大陆的地址。
/// 只用来认地址、填地址；之后改什么只改这一条配置。千问分两个平台：阿里云百炼和千问 AI 平台，两边的 Key 不通用。
/// rawValue 存在 SavedAPI.template 里，不能改名。
enum ConfigTemplate: String, CaseIterable, Identifiable {
    case deepseek, kimi, qwenBailian, qwenAI, glm, hunyuan
    case doubao, wenxin, minimax, stepfun, siliconflow
    case ollama, lmstudio
    case custom

    var id: String { rawValue }

    /// 「常用 API 地址」里「服务商」一组。硅基流动是聚合平台，上面有没备案的海外模型：大陆店面不列（05 备案核对）。
    static var catalog: [ConfigTemplate] {
        let all: [ConfigTemplate] = [.deepseek, .kimi, .qwenBailian, .qwenAI, .glm, .hunyuan, .doubao, .wenxin, .minimax, .stepfun, .siliconflow]
        return Storefront.isMainlandChina ? all.filter { $0 != .siliconflow } : all
    }

    /// 「自己电脑上」一组。
    static let local: [ConfigTemplate] = [.ollama, .lmstudio]

    static let qwenAIURL = "https://maas.qianwenaiapi.com/compatible-mode/v1"
    /// 本机服务地址里的示例 IP：选了以后直接选中，一打就替换。
    static let sampleIP = "192.168.1.100"

    /// logo、教程、能力按哪一家算（新加的几家和 LM Studio 算自定义）。
    var provider: Provider {
        switch self {
        case .deepseek: return .deepseek
        case .kimi: return .kimi
        case .qwenBailian, .qwenAI: return .qwen
        case .glm: return .glm
        case .hunyuan: return .hunyuan
        case .ollama: return .ollama
        case .doubao, .wenxin, .minimax, .stepfun, .siliconflow, .lmstudio, .custom: return .custom
        }
    }

    var isLocal: Bool { self == .ollama || self == .lmstudio }
    /// 认得出的云服务商：Key 空着就不去拉模型（NC2 ⑪）。
    var needsKey: Bool { self != .custom && !isLocal }

    var title: String {
        switch self {
        case .qwenBailian: return L("千问（阿里云百炼）", "Qwen (Alibaba Cloud Model Studio)", "Qwen（Alibaba Cloud Model Studio）")
        case .qwenAI: return L("千问 AI 平台", "Qwen AI Platform", "Qwen AI プラットフォーム")
        case .doubao: return L("豆包（火山方舟）", "Doubao (Volcano Ark)", "Doubao（Volcano Ark）")
        case .wenxin: return L("文心（百度千帆）", "ERNIE (Baidu Qianfan)", "ERNIE（Baidu Qianfan）")
        case .minimax: return "MiniMax"
        case .stepfun: return L("阶跃星辰", "StepFun", "StepFun")
        case .siliconflow: return L("硅基流动", "SiliconFlow", "SiliconFlow")
        case .lmstudio: return "LM Studio"
        default: return provider.title
        }
    }

    /// 名称的默认值：服务商名（千问两个平台都叫「千问」再看重名）。
    var defaultName: String {
        switch self {
        case .qwenBailian, .qwenAI: return L("千问", "Qwen", "Qwen")
        case .doubao: return L("豆包", "Doubao", "Doubao")
        case .wenxin: return L("文心", "ERNIE", "ERNIE")
        default: return title
        }
    }

    /// 平台名（配置页顶部服务商卡的灰字）。豆包非中国大陆是 BytePlus。
    func platform(side: APISide?) -> String {
        switch self {
        case .deepseek: return L("DeepSeek 开放平台", "DeepSeek platform", "DeepSeek プラットフォーム")
        case .kimi: return L("月之暗面", "Moonshot AI", "Moonshot AI")
        case .qwenBailian: return L("阿里云百炼", "Alibaba Cloud Model Studio", "Alibaba Cloud Model Studio")
        case .qwenAI: return L("千问 AI 平台", "Qwen AI Platform", "Qwen AI プラットフォーム")
        case .glm: return side == .global ? "Z.ai" : L("智谱开放平台", "Zhipu platform", "Zhipu プラットフォーム")
        case .hunyuan: return L("腾讯云 TokenHub", "Tencent Cloud TokenHub", "Tencent Cloud TokenHub")
        case .doubao: return side == .global ? "BytePlus ModelArk" : L("火山方舟", "Volcano Ark", "Volcano Ark")
        case .wenxin: return L("百度智能云千帆", "Baidu AI Cloud Qianfan", "Baidu AI Cloud Qianfan")
        case .minimax: return L("MiniMax 开放平台", "MiniMax platform", "MiniMax プラットフォーム")
        case .stepfun: return L("阶跃星辰开放平台", "StepFun platform", "StepFun プラットフォーム")
        case .siliconflow: return "SiliconCloud"
        case .ollama, .lmstudio: return L("自己电脑上", "On your computer", "自分のパソコン")
        case .custom: return L("自定义", "Custom", "カスタム")
        }
    }

    /// 每家的地址：非中国大陆在前；两边同一个的只有一个「通用」；只有国内站的只有「中国大陆」。
    var endpoints: [APIEndpoint] {
        switch self {
        case .deepseek: return [APIEndpoint(side: .universal, url: "https://api.deepseek.com/v1")]
        case .kimi: return [APIEndpoint(side: .global, url: Provider.kimiGlobal), APIEndpoint(side: .china, url: Provider.kimiChina)]
        case .qwenBailian: return [APIEndpoint(side: .global, url: Provider.qwenGlobal), APIEndpoint(side: .china, url: Provider.qwenChina)]
        case .qwenAI: return [APIEndpoint(side: .china, url: Self.qwenAIURL)]
        case .glm: return [APIEndpoint(side: .global, url: Provider.glmGlobal), APIEndpoint(side: .china, url: Provider.glmChina)]
        case .hunyuan: return [APIEndpoint(side: .china, url: Provider.hunyuanURL)]
        case .doubao: return [APIEndpoint(side: .global, url: "https://ark.ap-southeast.bytepluses.com/api/v3"),
                              APIEndpoint(side: .china, url: "https://ark.cn-beijing.volces.com/api/v3")]
        case .wenxin: return [APIEndpoint(side: .china, url: "https://qianfan.baidubce.com/v2")]
        case .minimax: return [APIEndpoint(side: .global, url: "https://api.minimax.io/v1"), APIEndpoint(side: .china, url: "https://api.minimax.cn/v1")]
        case .stepfun: return [APIEndpoint(side: .global, url: "https://api.stepfun.ai/v1"), APIEndpoint(side: .china, url: "https://api.stepfun.com/v1")]
        case .siliconflow: return [APIEndpoint(side: .global, url: "https://api.siliconflow.com/v1"), APIEndpoint(side: .china, url: "https://api.siliconflow.cn/v1")]
        case .ollama: return [APIEndpoint(side: .universal, url: "http://\(Self.sampleIP):11434/v1")]
        case .lmstudio: return [APIEndpoint(side: .universal, url: "http://\(Self.sampleIP):1234/v1")]
        case .custom: return []
        }
    }

    /// 按 App Store 地区默认填哪个地址（引导、教程进来时）。
    var baseURL: String {
        let list = endpoints
        return (list.first { $0.side == APISide.storefront } ?? list.first { $0.side == .universal } ?? list.first)?.url ?? ""
    }

    /// 地址是这家的哪一边：只有一个地址的就是那一边；两个的按主机名比；对不上是 nil。
    func side(of baseURL: String) -> APISide? {
        let list = endpoints
        if list.count == 1 { return list[0].side }
        let text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: text)?.host?.lowercased() else { return nil }
        return list.first { URL(string: $0.url)?.host == host }?.side
    }

    /// 推荐模型（下拉里标「推荐」用 Provider.preset；这里留给旧代码和测试）。新加的几家没有推荐模型。
    var model: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .kimi: return Provider.kimiAnswerModel
        case .qwenBailian, .qwenAI: return "qwen-flash"
        case .glm: return "glm-5-flash"
        case .hunyuan: return "hy3"
        default: return ""
        }
    }

    /// Kimi K3、智谱会先思考，思考也算在最多字数里；其他按默认。
    var maxTokens: Int { provider.maxTokens }

    /// 按地址认是哪家（千问 AI 平台、新加的几家单独认）。
    static func detect(_ baseURL: String) -> ConfigTemplate {
        let url = baseURL.lowercased()
        if url.contains("qianwenaiapi.com") { return .qwenAI }
        if url.contains("volces.com") || url.contains("bytepluses.com") { return .doubao }
        if url.contains("qianfan.baidubce.com") { return .wenxin }
        if url.contains("minimax.io") || url.contains("minimax.cn") || url.contains("minimaxi.com") { return .minimax }
        if url.contains("stepfun.ai") || url.contains("stepfun.com") { return .stepfun }
        if url.contains("siliconflow.cn") || url.contains("siliconflow.com") { return .siliconflow }
        switch Provider.detect(baseURL) {
        case .deepseek: return .deepseek
        case .kimi: return .kimi
        case .qwen: return .qwenBailian
        case .glm: return .glm
        case .hunyuan: return .hunyuan
        case .ollama: return .ollama
        case .openai, .custom: break
        }
        if url.contains(":1234/") || url.hasSuffix(":1234") { return .lmstudio }
        return .custom
    }

    /// 一条配置是哪家：地址认得出就按地址（地址改过以后跟着变），认不出用新建时记下的。
    static func of(_ config: SavedAPI) -> ConfigTemplate {
        let detected = detect(config.baseURL)
        guard detected == .custom else { return detected }
        return config.template.flatMap(ConfigTemplate.init(rawValue:)) ?? .custom
    }
}
