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

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("还没有配置 API，请先打开飞地输入法 App 填写。", "No API set up yet. Open the Enclave app to add one.", "API が未設定です。Enclave アプリで設定してください。")
        case .badURL(let url): return L("API 地址不正确：\(url)", "Invalid API URL: \(url)", "API の URL が正しくありません：\(url)")
        case .http(let code, let body): return L("请求失败（HTTP \(code)）：\(body)", "Request failed (HTTP \(code)): \(body)", "リクエストに失敗しました（HTTP \(code)）：\(body)")
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

    /// 逐段返回模型输出的文字。
    func stream(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard settings.isConfigured else { throw LLMError.notConfigured }
                    var request = URLRequest(url: try endpoint())
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
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

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
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
                        for try await byte in bytes { data.append(byte) }
                        let full = try JSONDecoder().decode(FullResponse.self, from: data)
                        continuation.yield(full.choices.first?.message.content ?? "")
                    } else {
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8),
                                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                                  let text = chunk.choices.first?.delta?.content, !text.isEmpty
                            else { continue }
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
