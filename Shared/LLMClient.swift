import Foundation

struct ChatMessage: Codable, Equatable {
    var role: String
    var content: String

    static func system(_ text: String) -> ChatMessage { ChatMessage(role: "system", content: text) }
    static func user(_ text: String) -> ChatMessage { ChatMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> ChatMessage { ChatMessage(role: "assistant", content: text) }
}

enum LLMError: LocalizedError {
    case notConfigured
    case badURL(String)
    case http(Int, String)
    /// 分段超时：firstData 为 true 是连上后一直没收到数据，否则是中途断流。
    case timeout(firstData: Bool)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("还没有配置 API，请先打开飞地输入法 App 填写。", "No API set up yet. Open the Enclave app to add one.", "API が未設定です。Enclave アプリで設定してください。")
        case .badURL(let url): return L("API 地址不正确：\(url)", "Invalid API URL: \(url)", "API の URL が正しくありません：\(url)")
        case .http(let code, let body): return L("请求失败（HTTP \(code)）：\(body)", "Request failed (HTTP \(code)): \(body)", "リクエストに失敗しました（HTTP \(code)）：\(body)")
        case .timeout(let firstData):
            return firstData
                ? L("模型一直没有响应", "The model didn't respond", "モデルから応答がありません")
                : L("模型中途没有新内容了", "The model stopped sending", "モデルからの送信が途中で止まりました")
        }
    }
}

/// 失败原因分成六类（P1）：超时、网络不通、Key 无效、余额不足、请求太频繁、服务端出错，每类一句话；服务端原文放 detail。
enum LLMFailure: Equatable {
    case timeout, network, unauthorized, noBalance, rateLimited, server(Int), other

    static func of(_ error: Error) -> LLMFailure {
        switch error {
        case LLMError.timeout: return .timeout
        case LLMError.http(let code, let body):
            let lower = body.lowercased()
            switch code {
            case 401, 403: return .unauthorized
            case 402: return .noBalance
            // Kimi 余额不足也回 429（exceeded_current_quota_error），按正文认。
            case 429: return lower.contains("quota") || lower.contains("balance") ? .noBalance : .rateLimited
            case 500...599: return .server(code)
            default: return .other
            }
        case let error as URLError:
            return error.code == .timedOut ? .timeout : .network
        default: return .other
        }
    }

    /// 自动重试一次的（ER0）：超时、429、5xx，还没出字时 1.5 秒后重发一次。网络不通、Key 无效、余额不足重试也没用。
    var autoRetry: Bool {
        switch self {
        case .timeout, .rateLimited, .server: return true
        case .network, .unauthorized, .noBalance, .other: return false
        }
    }

    /// 要去 App 接口页改的：Key 无效、余额不足（出错卡上多一颗「去设置」）。
    var needsSettings: Bool { self == .unauthorized || self == .noBalance }

    /// 出错卡第一行的标题（ER0）。
    func title(provider: String) -> String {
        switch self {
        case .timeout: return L("模型太久没响应", "The model took too long", "モデルの応答がありません")
        case .network: return L("连不上服务商", "Can't reach the provider", "サービスに接続できません")
        case .unauthorized: return L("API Key 无效", "Invalid API key", "API キーが無効です")
        case .noBalance: return L("账户余额不足", "Not enough credit", "残高が足りません")
        case .rateLimited: return L("请求太频繁", "Too many requests", "リクエストが多すぎます")
        case .server: return L("服务商出错了", "The provider had an error", "サービス側のエラー")
        case .other: return L("出错了", "Something went wrong", "エラーが発生しました")
        }
    }

    /// 出错卡第二行的灰字说明（ER0）。
    func note(provider: String) -> String {
        switch self {
        case .timeout: return L("可能是网络慢或服务商忙", "The network may be slow or the provider busy", "ネットワークが遅いか、サービスが混雑しています")
        case .network: return L("检查一下网络，或稍后再试", "Check your network or try again later", "ネットワークを確認するか、後で再試行してください")
        case .unauthorized: return L("到 App 接口页检查 Key", "Check the key on the API page in the app", "アプリの API ページでキーを確認してください")
        case .noBalance: return L("到 \(provider) 充值后再试", "Top up with \(provider) and try again", "\(provider) でチャージしてから再試行してください")
        case .rateLimited: return L("等几秒再试", "Wait a few seconds and try again", "数秒待ってから再試行してください")
        case .server: return L("\(provider) 那边暂时有问题，稍后再试", "\(provider) is having trouble. Try again later", "\(provider) で一時的な問題が起きています。後で再試行してください")
        case .other: return L("点重试再试一次", "Tap Retry to try again", "再試行してください")
        }
    }

    /// 「· 详情」里的原文：第一行「{服务商} · HTTP {码}」，下面是服务端返回（截到 500 字）。
    static func detail(_ error: Error, provider: String) -> String {
        switch error {
        case LLMError.http(let code, let body): return "\(provider) · HTTP \(code)\n\(body)"
        case LLMError.timeout(let firstData):
            return "\(provider) · " + (firstData ? "timeout (no data)" : "timeout (stalled)")
        case let error as URLError: return "\(provider) · URLError \(error.code.rawValue)\n\(error.localizedDescription)"
        default: return "\(provider)\n\(error.localizedDescription)"
        }
    }
}

/// OpenAI 兼容的 /chat/completions 客户端，支持流式输出。
struct LLMClient {
    var settings: EnclaveSettings
    var apiKey: String?
    /// 打开服务商自带的联网（千问 enable_search、智谱 web_search 工具）。
    /// 只在模型说了要联网、并且允许之后的那次问答请求上打开；Kimi 和别的服务商不发这些字段。
    var webSearch = false

    func endpoint() throws -> URL {
        var base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: full), url.scheme != nil, url.host != nil else {
            throw LLMError.badURL(settings.baseURL)
        }
        return url
    }

    private struct RequestBody: Encodable {
        var model: String
        var messages: [ChatMessage]
        var stream: Bool
        /// 为空就不发（Kimi 的 kimi-k 系列温度有固定要求，填别的值会报错，交给服务端用默认值）。
        var temperature: Double?
        var max_tokens: Int
        /// Kimi K3 一直会先思考，默认想得最久（max）；键盘里要快，发 low。别的服务商不发。
        var reasoning_effort: String?
        /// 千问（阿里云百炼）联网。模型已经判断过要联网，forced_search 让它一定搜。
        var enable_search: Bool?
        var search_options: SearchOptions?
        /// 智谱联网：内置的 web_search 工具。
        var tools: [Tool]?
    }

    private struct SearchOptions: Encodable { var forced_search = true }

    private struct Tool: Encodable {
        struct WebSearch: Encodable {
            var enable = true
            /// 基础版搜索引擎，约 ¥0.01/次。
            var search_engine = "search_std"
            var search_result = true
            var count = 5
        }
        var type = "web_search"
        var web_search = WebSearch()
    }

    /// 按服务商调整参数：Kimi（api.moonshot.cn / .ai）的 kimi-k 系列不发温度，K3 再加 reasoning_effort: low。
    private var kimiModel: String? {
        settings.usesFixedTemperature ? settings.model.trimmingCharacters(in: .whitespaces).lowercased() : nil
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { var content: String? }
            var delta: Delta?
        }
        var choices: [Choice]
    }

    private struct FullResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }

    /// 等第一段数据的时限：本机或局域网（Ollama 冷加载慢）45 秒；Kimi K 系列先思考、开着联网要先搜，30 秒；其他云端 20 秒。
    var firstDataLimit: TimeInterval {
        let base = settings.baseURL.lowercased()
        if base.contains(":11434") || base.hasPrefix("http://") { return 45 }
        if settings.usesFixedTemperature || webSearch { return 30 }
        return 20
    }
    /// 收到数据以后，两段之间超过这么久没有新内容算断流。总时长不限，长回答不受影响。
    static let stallLimit: TimeInterval = 20

    /// 逐段返回模型输出的文字。retries：还没出字就失败、而且是 429 / 5xx / 超时 / 断网时，1.5 秒后自动重发几次（默认一次）。
    /// 已经出了字的不重发，错误照常抛出。
    func stream(_ messages: [ChatMessage], retries: Int = 1) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                while true {
                    let yielded = Flag()
                    do {
                        try await streamOnce(messages) { text in
                            yielded.set()
                            continuation.yield(text)
                        }
                        continuation.finish()
                        return
                    } catch {
                        if !Task.isCancelled, attempt < retries, !yielded.value, LLMFailure.of(error).autoRetry {
                            attempt += 1
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if !Task.isCancelled { continue }
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 发一次请求。旁边一个看门狗：连上后 firstDataLimit 内没收到任何数据、或之后 stallLimit 没有新数据，就抛 timeout。
    /// 推理模型先发思考内容（这里不显示），也算收到数据，免得被误判超时。
    private func streamOnce(_ messages: [ChatMessage], onText: @escaping @Sendable (String) -> Void) async throws {
        guard settings.isConfigured else { throw LLMError.notConfigured }
        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        // 超时由下面的看门狗管；这里只兜底。
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: settings.model.trimmingCharacters(in: .whitespaces),
            messages: messages,
            stream: true,
            temperature: kimiModel == nil ? settings.temperature : nil,
            max_tokens: settings.maxTokens,
            reasoning_effort: kimiModel?.hasPrefix("kimi-k3") == true ? "low" : nil,
            enable_search: webSearch && settings.searchProvider == .qwen ? true : nil,
            search_options: webSearch && settings.searchProvider == .qwen ? SearchOptions() : nil,
            tools: webSearch && settings.searchProvider == .glm ? [Tool()] : nil
        ))

        let activity = Activity()
        let firstLimit = firstDataLimit
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                activity.touch()
                let http = response as? HTTPURLResponse
                if let http, !(200..<300).contains(http.statusCode) {
                    var body = ""
                    for try await line in bytes.lines {
                        body += line
                        if body.count > 500 { break }
                    }
                    throw LLMError.http(http.statusCode, String(body.prefix(500)))
                }

                let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
                if contentType.contains("application/json") {
                    // 服务端忽略了 stream 参数，直接返回完整结果。
                    var data = Data()
                    for try await byte in bytes {
                        data.append(byte)
                        if data.count % 512 == 1 { activity.touch() }
                    }
                    let full = try JSONDecoder().decode(FullResponse.self, from: data)
                    onText(full.choices.first?.message.content ?? "")
                } else {
                    for try await line in bytes.lines {
                        activity.touch()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let text = chunk.choices.first?.delta?.content, !text.isEmpty
                        else { continue }
                        onText(text)
                    }
                }
            }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let state = activity.state
                    let waited = Date().timeIntervalSince(state.last)
                    if waited > (state.received ? Self.stallLimit : firstLimit) {
                        throw LLMError.timeout(firstData: !state.received)
                    }
                }
            }
            // 读完（或任一边出错）就收掉另一边。
            try await group.next()
            group.cancelAll()
        }
    }

    /// 看门狗看的：开始时间、最近一次收到数据的时间。两个子任务都会碰，用锁。
    private final class Activity: @unchecked Sendable {
        private let lock = NSLock()
        private var last = Date()
        private var received = false

        func touch() {
            lock.lock(); last = Date(); received = true; lock.unlock()
        }

        var state: (last: Date, received: Bool) {
            lock.lock(); defer { lock.unlock() }
            return (last, received)
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        func set() { lock.lock(); on = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
    }
}

enum ModelOutput {
    /// 去掉推理模型输出的 <think>…</think>。思考还没结束时返回空串。
    static func clean(_ raw: String) -> String {
        var text = raw
        while let start = text.range(of: "<think>") {
            guard let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) else {
                text = String(text[..<start.lowerBound])
                break
            }
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
