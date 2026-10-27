import Foundation

/// Kimi 的联网搜索（POST {地址}/tools/search，和对话用同一个地址、同一个 Key）。
/// 识意问答里模型说要查最新信息时调用一次，搜索由 Kimi 另外按次计费（大陆约 ¥0.01/次）。
/// 旧的 $web_search 内置工具已经下线，这里用独立接口：什么时候搜、搜什么由键盘决定。
struct WebSearch {
    struct Result: Decodable, Equatable {
        var title: String?
        var url: String?
        var site_name: String?
        var date: String?
        var snippet: String?
    }

    private struct Response: Decodable { var search_results: [Result]? }

    private struct Request: Encodable {
        var text_query: String
        var limit: Int
        var timeout_seconds: Int
    }

    var settings: EnclaveSettings
    var apiKey: String?

    func endpoint() throws -> URL {
        var base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { base.removeLast("/chat/completions".count) }
        guard let url = URL(string: base + "/tools/search"), url.host != nil else {
            throw LLMError.badURL(settings.baseURL)
        }
        return url
    }

    /// 搜 query，最多 5 条。
    func search(_ query: String) async throws -> [Result] {
        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Request(text_query: query, limit: 5, timeout_seconds: 15))
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data).search_results ?? []
    }

    /// 交给模型的资料：每条标题、来源、日期、摘要，摘要截到 300 字，免得上下文太长。
    static func digest(_ results: [Result]) -> String {
        results.prefix(5).enumerated().map { index, item in
            var lines = ["[\(index + 1)] \(item.title ?? "")"]
            let source = [item.site_name, item.date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !source.isEmpty { lines.append(source) }
            if let snippet = item.snippet, !snippet.isEmpty { lines.append(String(snippet.prefix(300))) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
