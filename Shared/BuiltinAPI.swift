import CryptoKit
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
    /// Key 不在 Info.plist 里：编译时混淆拆段（scripts/gen-builtin-secrets.py），这里才拼回来。
    static let apiKey = reveal(BuiltinSecrets.keyParts, BuiltinSecrets.keyMasks)
    static let answerBaseURL = value("EnclaveBuiltinAnswerBaseURL")
    static let answerModel = value("EnclaveBuiltinAnswerModel")
    static let answerApiKey = reveal(BuiltinSecrets.answerKeyParts, BuiltinSecrets.answerKeyMasks)

    private static func reveal(_ parts: [[UInt8]], _ masks: [[UInt8]]) -> String {
        let bytes = zip(parts, masks).flatMap { zip($0, $1).map { $0 ^ $1 } }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 发请求用的 URLSession：用内置 Key 的走证书绑定的那个，别的（自己填的接口）照常。
    static func session(for key: String?) -> URLSession {
        isBuiltin(key) && !BuiltinSecrets.pins.isEmpty ? PinnedSession.shared : .shared
    }

    static var available: Bool { !baseURL.isEmpty && !model.isEmpty && !apiKey.isEmpty }
    static var answerAvailable: Bool { !answerBaseURL.isEmpty && !answerModel.isEmpty && !answerApiKey.isEmpty }

    /// 这个 Key 是不是内置的（是的话算限额）。
    static func isBuiltin(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        return key == apiKey || key == answerApiKey
    }

    /// 把内置接口填进去。第一次装上（还没有任何设置）时调；Key 只在钥匙串里没有时才写。
    /// force：内测版接口页锁着改不了，装在开发版上面留下的旧设置（或者空的）要整个换成内置的，Key 也换。
    static func seed(_ settings: inout EnclaveSettings, force: Bool = false) {
        guard available else { return }
        settings.baseURL = baseURL
        settings.model = model
        if force || (SettingsStore.apiKey ?? "").isEmpty { SettingsStore.apiKey = apiKey }
        if answerAvailable {
            settings.separateAnswer = true
            settings.answerBaseURL = answerBaseURL
            settings.answerModel = answerModel
            if force || (SettingsStore.answerApiKey ?? "").isEmpty { SettingsStore.answerApiKey = answerApiKey }
        }
        SettingsStore.save(settings)
    }

    /// 内测版里存着的接口和内置的对不上（装在开发版上面）。
    static func needsReseed(_ settings: EnclaveSettings) -> Bool {
        guard isInternalBuild, available else { return false }
        if settings.baseURL != baseURL || settings.model != model { return true }
        return answerAvailable && (!settings.separateAnswer || settings.answerBaseURL != answerBaseURL || settings.answerModel != answerModel)
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

/// 内置接口的证书绑定：系统先照常验证证书，再要求证书链里至少有一张（中间证书或根证书）在编译时记下的指纹里，
/// 对不上就拒绝连接，抓包工具装的证书过不了。
private final class PinnedSession: NSObject, URLSessionDelegate {
    static let shared: URLSession = URLSession(configuration: .default, delegate: PinnedSession(), delegateQueue: nil)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.performDefaultHandling, nil)
        }
        guard SecTrustEvaluateWithError(trust, nil), let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }
        let matched = chain.dropFirst().contains { cert in
            let digest = SHA256.hash(data: SecCertificateCopyData(cert) as Data)
            return BuiltinSecrets.pins.contains(digest.map { String(format: "%02x", $0) }.joined())
        }
        completionHandler(matched ? .useCredential : .cancelAuthenticationChallenge, matched ? URLCredential(trust: trust) : nil)
    }
}
