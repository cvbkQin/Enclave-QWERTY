import Foundation

/// 内测版（版本号后缀 .0）自带的接口：邀请来的人装上就能用，不用自己申请 Key。
/// 地址、模型、Key 只写在打包那台 Mac 的 Configs/Local.xcconfig 里（不进 Git），打内测包时加 INTERNAL_BUILD=YES 才编进 Info.plist；
/// 开发者版、公测版这几项是空的，这里什么都不做。
/// 用内置 Key 时每天有上限：润色（含改写、自动识意）100 次，问答 50 次。
enum BuiltinAPI {
    private static func value(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespaces)
        return raw.contains("$(") ? "" : raw
    }

    /// 内测包（打包时 INTERNAL_BUILD=YES）：接口页只能看。
    static let isInternalBuild = value("EnclaveInternalBuild") == "YES"
    /// 公测包（打包时 PUBLIC_BUILD=YES）：只用来在首页标「公测版」。
    static let isPublicBuild = value("EnclavePublicBuild") == "YES"

    static let baseURL = value("EnclaveBuiltinBaseURL")
    static let model = value("EnclaveBuiltinModel")
    static let apiKey = value("EnclaveBuiltinKey")
    static let answerBaseURL = value("EnclaveBuiltinAnswerBaseURL")
    static let answerModel = value("EnclaveBuiltinAnswerModel")
    static let answerApiKey = value("EnclaveBuiltinAnswerKey")

    static var available: Bool { !baseURL.isEmpty && !model.isEmpty && !apiKey.isEmpty }
    static var answerAvailable: Bool { !answerBaseURL.isEmpty && !answerModel.isEmpty && !answerApiKey.isEmpty }

    /// 这个 Key 是不是内置的（是的话算限额）。
    static func isBuiltin(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        return key == apiKey || key == answerApiKey
    }

    /// 第一次装上（还没有任何设置）时把内置接口填进去；已经有设置的不动，装在旧版上面会保留原来填的。
    static func seed(_ settings: inout EnclaveSettings) {
        guard available else { return }
        settings.baseURL = baseURL
        settings.model = model
        if (SettingsStore.apiKey ?? "").isEmpty { SettingsStore.apiKey = apiKey }
        if answerAvailable {
            settings.separateAnswer = true
            settings.answerBaseURL = answerBaseURL
            settings.answerModel = answerModel
            if (SettingsStore.answerApiKey ?? "").isEmpty { SettingsStore.answerApiKey = answerApiKey }
        }
        SettingsStore.save(settings)
    }

    // MARK: - 每天的上限

    enum Kind: String {
        case polish, answer
        var limit: Int { self == .polish ? 100 : 50 }
    }

    private static func countKey(_ kind: Kind) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "builtin.\(kind.rawValue).\(formatter.string(from: Date()))"
    }

    static func used(_ kind: Kind) -> Int { SharedStorage.defaults.integer(forKey: countKey(kind)) }

    /// 用内置 Key 时，这次还能不能调；能的话记一次。不是内置 Key 一律放行。
    static func take(_ kind: Kind, key: String?) -> Bool {
        guard isBuiltin(key) else { return true }
        let count = used(kind)
        guard count < kind.limit else { return false }
        SharedStorage.defaults.set(count + 1, forKey: countKey(kind))
        return true
    }

    /// 内测版接口页锁着，换不了 Key，只能等明天。
    static func limitMessage(_ kind: Kind) -> String {
        kind == .polish
            ? L("内测接口今天的润色次数（100 次）用完了，明天再来。", "The beta's built-in API has used today's 100 rewrites. Try again tomorrow.", "内蔵 API の今日の書き換え（100 回）を使い切りました。また明日お使いください。")
            : L("内测接口今天的问答次数（50 次）用完了，明天再来。", "The beta's built-in API has used today's 50 answers. Try again tomorrow.", "内蔵 API の今日の回答（50 回）を使い切りました。また明日お使いください。")
    }
}
