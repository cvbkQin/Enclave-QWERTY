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

    /// 键盘第一次用某一家联网问答前，在确认卡上说明过发给谁、怎么收费，并且点了同意。按服务商分开记，换了一家再确认一次。
    /// 0.87 只有 Kimi，记在 "webSearch.consented"（布尔），算 Kimi 同意过。
    private static let legacyKey = "webSearch.consented"
    private static func key(_ provider: SearchProvider) -> String { "webSearch.consented.\(provider.rawValue)" }
    static func isConsented(_ provider: SearchProvider) -> Bool {
        SharedStorage.defaults.bool(forKey: key(provider)) || (provider == .kimi && SharedStorage.defaults.bool(forKey: legacyKey))
    }
    static func grantConsent(_ provider: SearchProvider) { SharedStorage.defaults.set(true, forKey: key(provider)) }

    /// 确认卡上那一行：发什么、发给谁、谁收费。
    static func consentNote(_ provider: SearchProvider) -> String {
        switch provider {
        case .kimi:
            return L("联网问答会调用 Kimi 搜索：问题会发给 Kimi 的搜索接口，每次约 0.01 元从你的 Kimi 账户扣。", "Web search in Ask uses Kimi search: your question goes to Kimi's search API, about ¥0.01 per search from your Kimi account.", "質問のウェブ検索は Kimi 検索を使います。質問が Kimi の検索 API に送られ、1 回約 0.01 元が Kimi アカウントから引かれます。")
        case .qwen:
            return L("联网会调用通义千问的搜索：只把你的问题发给千问，由阿里云根据问题生成搜索词去搜，按次计费，从你的阿里云百炼账户扣。", "Web search uses Qwen search: only your question is sent to Qwen, and Alibaba Cloud searches with terms based on it, billed per search to your Model Studio account.", "ウェブ検索には Qwen の検索を使います。質問だけを Qwen に送り、Alibaba Cloud が質問から検索語を作って検索します。回数ごとに Model Studio アカウントに課金されます。")
        case .glm:
            return L("联网会调用智谱的搜索：只把你的问题发给智谱，由智谱根据问题生成搜索词去搜，每次约 0.01 元，从你的智谱账户扣。", "Web search uses Zhipu search: only your question is sent to Zhipu, which searches with terms based on it, about ¥0.01 per search from your Zhipu account.", "ウェブ検索には Zhipu の検索を使います。質問だけを Zhipu に送り、Zhipu が質問から検索語を作って検索します。1 回約 0.01 元が Zhipu アカウントから引かれます。")
        }
    }

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
        let (data, response) = try await BuiltinAPI.session(for: apiKey).data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data).search_results ?? []
    }

    /// 交给模型的资料：最多 3 条，每条标题、来源、日期、摘要，摘要截到 200 字，免得上下文太长、回答跟着啰嗦。
    static func digest(_ results: [Result]) -> String {
        results.prefix(3).enumerated().map { index, item in
            var lines = ["[\(index + 1)] \(item.title ?? "")"]
            let source = [item.site_name, item.date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !source.isEmpty { lines.append(source) }
            if let snippet = item.snippet, !snippet.isEmpty { lines.append(String(snippet.prefix(200))) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
