import Foundation

/// 向服务商要可用的模型列表（接口页「选择」ML1–ML5）：OpenAI 兼容的 GET {base}/models，Ollama 用 /api/tags。
/// 只在用户点「选择」或点「测试」时请求，用的就是接口页填的地址和 Key。
enum ModelList {
    enum Failure: Error, Equatable {
        case unauthorized, noBalance, network, unsupported, badURL, other(Int)

        var message: String {
            switch self {
            case .unauthorized: return L("API Key 无效或已过期。请检查下方的 API Key 后重试。", "The API key is invalid or expired. Check the API key below and try again.", "API キーが無効か期限切れです。下の API キーを確認してから再試行してください。")
            case .noBalance: return L("账户余额不足。", "Your account balance is too low.", "アカウントの残高が不足しています。")
            case .network: return L("无法连接服务商，请检查网络。", "Can't reach the provider. Check your connection.", "サービスに接続できません。ネットワークを確認してください。")
            case .unsupported: return L("这个服务商不支持获取模型列表。", "This provider doesn't offer a model list.", "このサービスはモデル一覧の取得に対応していません。")
            case .badURL: return L("API 地址不正确。", "The API URL isn't valid.", "API の URL が正しくありません。")
            case .other(let code): return L("获取失败（HTTP \(code)）。", "Couldn't load the list (HTTP \(code)).", "取得できませんでした（HTTP \(code)）。")
            }
        }
    }

    static func isOllama(_ baseURL: String) -> Bool { baseURL.contains(":11434") }

    /// 列表地址：去掉末尾的 / 和 /chat/completions 再接 /models；Ollama 去掉 /v1 接 /api/tags。
    static func url(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { base.removeLast("/chat/completions".count) }
        if isOllama(base) {
            if base.hasSuffix("/v1") { base.removeLast(3) }
            base += "/api/tags"
        } else {
            base += "/models"
        }
        guard let url = URL(string: base), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    /// OpenAI 兼容：{"data":[{"id":…}]}；Ollama：{"models":[{"name":…}]}。保持服务商给的顺序，去重。
    static func parse(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let items = (root["data"] as? [[String: Any]]) ?? (root["models"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return items.compactMap { ($0["id"] ?? $0["name"] ?? $0["model"]) as? String }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 名字里带 reasoner / thinking 的是深度思考模型（改写页标「较慢」）。
    static func isThinking(_ model: String) -> Bool {
        let lower = model.lowercased()
        return lower.contains("reasoner") || lower.contains("thinking")
    }

    // MARK: 筛选（MF，功能对照表「模型下拉的筛选」）

    /// 不是对话模型的话是哪一类（向量、重排、语音合成…），润色、问答都用不了，不进主列表。对话模型是 nil。
    static func nonChatKind(_ model: String) -> String? {
        let lower = model.lowercased()
        let kinds: [(keys: [String], title: String)] = [
            (["embedding", "embed-"], L("向量", "Embedding", "埋め込み")),
            (["rerank"], L("重排", "Rerank", "リランク")),
            (["tts", "cosyvoice", "sambert"], L("语音合成", "Speech", "音声合成")),
            (["asr", "paraformer", "sensevoice"], L("语音识别", "Transcription", "音声認識")),
            (["realtime"], L("实时语音", "Realtime", "リアルタイム")),
            (["audio"], L("语音", "Audio", "音声")),
            (["image", "wanx", "wan2", "flux", "dall-e", "cogview"], L("画图", "Image", "画像生成")),
            (["video", "cogvideo"], L("视频", "Video", "動画")),
            (["ocr"], L("识字", "OCR", "OCR")),
        ]
        return kinds.first { $0.keys.contains(where: lower.contains) }?.title
    }

    /// 这个模型能不能联网（问答页的下拉只列能联网的）。只管千问（两个平台）和混元：
    /// 千问 = qwen-max、qwen-plus、qwen-flash 及其版本、qwen3.5 及以上；混元 = hy3 系列、deepseek-v4 系列。
    /// 别的服务商不过滤（Kimi 自己调搜索接口，和模型无关），返回 true。
    static func supportsWebSearch(_ model: String, provider: SearchProvider?) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespaces)
        switch provider {
        case .qwen:
            if ["qwen-max", "qwen-plus", "qwen-flash"].contains(where: { lower == $0 || lower.hasPrefix($0 + "-") }) { return true }
            guard lower.hasPrefix("qwen") else { return false }
            let digits = lower.dropFirst(4).prefix { $0.isNumber || $0 == "." }
            guard let version = Double(digits) else { return false }
            return version >= 3.5
        case .hunyuan:
            return lower.hasPrefix("hy3") || lower.hasPrefix("deepseek-v4")
        default:
            return true
        }
    }

    /// 问答页要不要按联网过滤：千问、混元。
    static func filtersForWebSearch(_ provider: SearchProvider?) -> Bool {
        provider == .qwen || provider == .hunyuan
    }

    /// 当前模型排第一，其余按服务商的顺序。
    static func ordered(_ models: [String], current: String) -> [String] {
        let current = current.trimmingCharacters(in: .whitespaces)
        guard models.contains(current) else { return models }
        return [current] + models.filter { $0 != current }
    }

    static func fetch(baseURL: String, apiKey: String?) async throws -> [String] {
        guard let url = url(baseURL: baseURL) else { throw Failure.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if let key = apiKey, !key.isEmpty, !isOllama(baseURL) {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await BuiltinAPI.session(for: apiKey).data(for: request)
        } catch {
            throw Failure.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 401, 403: throw Failure.unauthorized
        case 402: throw Failure.noBalance
        case 404:
            markUnsupported(baseURL)
            throw Failure.unsupported
        default: throw Failure.other(code)
        }
        return parse(data)
    }

    // MARK: 不支持的服务商

    /// 返回过 404 的地址（按主机名）记下来，之后不再显示「选择」。
    private static func unsupportedKey(_ baseURL: String) -> String? {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host.map { "models.unsupported.\($0)" }
    }

    static func isUnsupported(_ baseURL: String) -> Bool {
        unsupportedKey(baseURL).map { SharedStorage.defaults.bool(forKey: $0) } ?? false
    }

    private static func markUnsupported(_ baseURL: String) {
        if let key = unsupportedKey(baseURL) { SharedStorage.defaults.set(true, forKey: key) }
    }
}
