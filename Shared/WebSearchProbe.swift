import Foundation

/// 「测试联网」（接口配置页 CF3b）：配好问答接口后点一下，真的联网问一次，看这个地址 + 模型到底能不能联网。
/// 结果按「地址 + 模型」记在共享存储里，接口列表（CF5）和键盘按它标「可联网」/「不能联网」；没测过的照旧按服务商判断。
///
/// 判断方法按服务商分（能看到真实搜索结果的优先）：
/// - Kimi：键盘本来就自己调搜索接口（/tools/search），搜到结果就算可联网，和模型无关。
/// - 智谱：请求里带 web_search 工具，返回里有 web_search 结果就算可联网。
/// - 千问、腾讯混元：服务商自带联网，OpenAI 兼容方式下返回里不一定带搜索来源。先找返回里的搜索字段，
///   找不到再看回答里有没有今天的日期（不联网的模型不知道今天是几号）。
/// - 别的服务商：没有联网接口，不用测，直接算不能联网。
/// 每测一次服务商另收一次搜索费（约 0.01 元），只在用户点「测试」时发。
enum WebSearchProbe {
    enum Verdict: String, Codable, Equatable {
        case online, offline
    }

    /// 测的那句问题：要今天的日期和实时天气，不联网答不对。
    static let question = "今天是几月几号？上海现在天气怎么样？只用一句话回答，要写出今天的日期。"

    /// 跑一次测试。网络、Key、余额之类的错误照常抛出（界面显示「没测成 · 重试」），只有确定能 / 不能联网才返回结果，并记下来。
    @discardableResult
    static func run(settings: EnclaveSettings, apiKey: String?, now: Date = Date()) async throws -> Verdict {
        let verdict: Verdict
        switch settings.searchProvider {
        case nil:
            verdict = .offline
        case .kimi:
            let results = try await WebSearch(settings: settings, apiKey: apiKey).search("上海 今天 天气")
            verdict = results.isEmpty ? .offline : .online
        case .some(let provider):
            let client = LLMClient(settings: settings, apiKey: apiKey, webSearch: true)
            let messages: [ChatMessage] = [
                .system("你可以联网搜索。这次必须先联网搜索再回答。"),
                .user(question),
            ]
            do {
                let data = try await client.completeRaw(messages)
                verdict = Self.verdict(provider: provider, response: data, now: now)
            } catch LLMError.http(let code, let body) where code == 400 && Self.rejectsSearch(body) {
                // 服务商明说这个模型不支持联网参数。
                verdict = .offline
            }
        }
        store(verdict, baseURL: settings.baseURL, model: settings.model, at: now)
        return verdict
    }

    // MARK: 看返回

    /// 从响应体判断。纯函数，单元测试直接喂 JSON。
    static func verdict(provider: SearchProvider, response data: Data, now: Date) -> Verdict {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return .offline }
        if hasSearchResults(root) { return .online }
        let answer = content(of: root)
        return mentionsDate(answer, now) ? .online : .offline
    }

    /// 返回里有没有搜索结果：智谱的 web_search、千问 DashScope 的 search_info.search_results、
    /// 其他服务商常见的 search_results / citations。数组非空才算。
    static func hasSearchResults(_ node: Any) -> Bool {
        let keys: Set<String> = ["web_search", "search_results", "search_info", "citations", "references"]
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if keys.contains(key), nonEmpty(value) { return true }
                if key != "messages", hasSearchResults(value) { return true }
            }
        } else if let array = node as? [Any] {
            return array.contains { hasSearchResults($0) }
        }
        return false
    }

    private static func nonEmpty(_ value: Any) -> Bool {
        if let array = value as? [Any] { return !array.isEmpty }
        if let dict = value as? [String: Any] {
            // search_info 这种外面包一层的：里面有非空数组才算。
            return dict.values.contains { nonEmpty($0) }
        }
        return false
    }

    /// choices[0].message.content，去掉 <think>。
    static func content(of root: Any) -> String {
        guard let dict = root as? [String: Any], let choices = dict["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String
        else { return "" }
        return ModelOutput.clean(text)
    }

    /// 回答里写了今天的日期（11月3日、11 月 3 号、11-03、11/3、Nov 3）。按北京时间算今天。
    static func mentionsDate(_ text: String, _ now: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let month = calendar.component(.month, from: now), day = calendar.component(.day, from: now)
        let compact = text.replacingOccurrences(of: " ", with: "")
        let patterns = [
            "\(month)月\(day)日", "\(month)月\(day)号",
            String(format: "%02d月%02d日", month, day),
            String(format: "%d-%02d-%02d", calendar.component(.year, from: now), month, day),
            String(format: "%02d-%02d", month, day), "\(month)/\(day)",
        ]
        if patterns.contains(where: { compact.contains($0) }) { return true }
        let english = DateFormatter()
        english.locale = Locale(identifier: "en_US_POSIX")
        english.timeZone = calendar.timeZone
        english.dateFormat = "MMM d"
        let short = english.string(from: now)
        english.dateFormat = "MMMM d"
        let long = english.string(from: now)
        return text.localizedCaseInsensitiveContains(short) || text.localizedCaseInsensitiveContains(long)
    }

    /// 400 的报错里说的是联网参数不支持（模型不支持 enable_search / web_search 之类）。
    static func rejectsSearch(_ body: String) -> Bool {
        let lower = body.lowercased()
        return ["enable_search", "web_search", "search", "联网"].contains { lower.contains($0) }
    }

    // MARK: 记下来

    private static let storeKey = "webSearch.probe"

    private struct Record: Codable {
        var verdict: Verdict
        var testedAt: Date
    }

    private static func id(baseURL: String, model: String) -> String {
        SavedAPIStore.normalized(baseURL).lowercased() + "|" + model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var records: [String: Record] {
        guard let data = SharedStorage.defaults.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([String: Record].self, from: data) else { return [:] }
        return list
    }

    static func store(_ verdict: Verdict, baseURL: String, model: String, at date: Date = Date()) {
        var all = records
        all[id(baseURL: baseURL, model: model)] = Record(verdict: verdict, testedAt: date)
        if let data = try? JSONEncoder().encode(all) { SharedStorage.defaults.set(data, forKey: storeKey) }
    }

    /// 这个地址 + 模型测过的结果；没测过是 nil（界面显示「未测试」，照旧按服务商判断）。
    static func stored(baseURL: String, model: String) -> Verdict? {
        records[id(baseURL: baseURL, model: model)]?.verdict
    }

    /// 什么时候测的（「可联网 · 今天测过」之类的小字用）。
    static func testedAt(baseURL: String, model: String) -> Date? {
        records[id(baseURL: baseURL, model: model)]?.testedAt
    }
}
