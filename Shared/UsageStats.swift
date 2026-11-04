import Foundation

/// App 仪表盘要的使用记录：按天的计数一律走 DailyStats（polish.*、word.*），
/// 不按天的两样（最近 20 次请求、试过的场景）存在这里。都只在手机上，不上传。
enum UsageStats {
    private static let recentKey = "stats.polishRecent"
    private static let answerRecentKey = "stats.answerRecent"
    private static let labKey = "stats.labTried"
    /// AI 页接口卡和「最近 20 次」页（第 51 条）：润色、问答各留最近 20 次。
    static let recentLimit = 20

    // MARK: 执行提示词（键盘里）

    /// 一次请求结束：成功记 polish.done、耗时和这条提示词，失败记 polish.failed；都进最近 20 次。点停止不算。
    /// mainAPI：发到润色接口的。走单独问答接口的请求记进问答卡的「最近 20 次」。
    /// styleName、model、error、webSearchMs 给「最近 20 次」页每一行用；不记打的字和回答。
    static func recordPolish(ms: Int, ok: Bool, styleID: UUID?, mainAPI: Bool = true, styleName: String? = nil,
                             model: String? = nil, error: String? = nil, webSearchMs: Int? = nil) {
        if ok {
            DailyStats.add("polish.done")
            DailyStats.add("polish.ms", ms)
            if let styleID { DailyStats.add("polish.style.\(styleID.uuidString)") }
        } else {
            DailyStats.add("polish.failed")
        }
        let request = Request(ms: ms, ok: ok, at: Date(), error: ok ? nil : (error ?? Request.Failure.other),
                              styleName: styleName, model: model, webSearchMs: webSearchMs)
        if mainAPI { record(request, answer: false) } else { record(request, answer: true) }
        // 请求不多，每次都写，App 马上能看到。
        DailyStats.flush()
    }

    /// 只进最近 20 次（接口卡「测试连接」也算一次请求），不计入执行次数。
    static func recordRequest(ms: Int, ok: Bool, model: String? = nil, error: String? = nil, test: Bool = false) {
        record(Request(ms: ms, ok: ok, at: Date(), error: ok ? nil : (error ?? Request.Failure.other), model: model,
                       test: test ? true : nil), answer: false)
    }

    /// 问答卡的最近 20 次（单独设了问答接口时；问答卡「测试连接」也算）。
    static func recordAnswerRequest(ms: Int, ok: Bool, model: String? = nil, error: String? = nil, test: Bool = false) {
        record(Request(ms: ms, ok: ok, at: Date(), error: ok ? nil : (error ?? Request.Failure.other), model: model,
                       test: test ? true : nil), answer: true)
    }

    static func record(_ request: Request, answer: Bool) {
        if answer {
            answerRecent = Array((answerRecent + [request]).suffix(recentLimit))
        } else {
            polishRecent = Array((polishRecent + [request]).suffix(recentLimit))
        }
    }

    /// 「最近 20 次」页底部「清空记录」：只清这一种。
    static func clearRecent(answer: Bool) {
        SharedStorage.defaults.removeObject(forKey: answer ? answerRecentKey : recentKey)
    }

    static var answerRecent: [Request] {
        get {
            guard let data = SharedStorage.defaults.data(forKey: answerRecentKey) else { return [] }
            return (try? JSONDecoder().decode([Request].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedStorage.defaults.set(data, forKey: answerRecentKey) }
        }
    }

    struct Request: Codable, Equatable {
        var ms: Int
        var ok: Bool
        var at: Date
        /// 下面几项 0.95_8 起记，旧数据缺的就不显示。
        /// 失败原因：Failure 里的取值。
        var error: String?
        /// 用的提示词 / 问答风格名字。
        var styleName: String?
        var model: String?
        /// 问答联网搜索用了多久（毫秒）。
        var webSearchMs: Int?
        /// 接口卡「测试连接」发的。
        var test: Bool?

        /// 超过 3 秒算慢（柱子橙色）。
        var slow: Bool { ok && ms > 3000 }

        enum Failure {
            static let timeout = "timeout"
            static let network = "network"
            static let unauthorized = "unauthorized"
            static let noBalance = "noBalance"
            static let rateLimited = "rateLimited"
            static let server = "server"
            static let empty = "empty"
            static let search = "search"
            static let other = "other"

            static func of(_ error: Error) -> String {
                switch LLMFailure.of(error) {
                case .timeout: return timeout
                case .network: return network
                case .unauthorized: return unauthorized
                case .noBalance: return noBalance
                case .rateLimited: return rateLimited
                case .server: return server
                case .other: return other
                }
            }
        }

        /// 「最近 20 次」页失败那一行的原因。
        var failureText: String {
            switch error {
            case Failure.timeout: return L("超时：太久没有回应", "Timed out: no response", "タイムアウト：応答なし")
            case Failure.network: return L("没有网络", "No network", "ネットワークなし")
            case Failure.unauthorized: return L("Key 无效（401）", "Invalid key (401)", "キーが無効（401）")
            case Failure.noBalance: return L("余额不足", "Not enough credit", "残高不足")
            case Failure.rateLimited: return L("请求太频繁（429）", "Too many requests (429)", "リクエスト過多（429）")
            case Failure.server: return L("服务商出错（5xx）", "Provider error (5xx)", "サービス側のエラー（5xx）")
            case Failure.empty: return L("模型没有返回内容", "The model returned nothing", "モデルから応答なし")
            case Failure.search: return L("联网搜索失败", "Web search failed", "ウェブ検索に失敗")
            default: return L("出错了", "Something went wrong", "エラー")
            }
        }
    }

    /// 最近 20 次请求，最早的在前。
    static var polishRecent: [Request] {
        get {
            guard let data = SharedStorage.defaults.data(forKey: recentKey) else { return [] }
            return (try? JSONDecoder().decode([Request].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { SharedStorage.defaults.set(data, forKey: recentKey) }
        }
    }

    // MARK: 常用词上屏（键盘里）

    /// 设置 › 隐私「清除使用统计」：按天计数和最近 20 次请求。
    static func clearStats() {
        DailyStats.clear()
        SharedStorage.defaults.removeObject(forKey: recentKey)
        SharedStorage.defaults.removeObject(forKey: answerRecentKey)
    }

    static func wordCommitted(_ text: String) {
        DailyStats.add("word.commit")
        DailyStats.add(wordKey(text))
    }

    static func wordKey(_ text: String) -> String { "word.text.\(text)" }

    // MARK: 使用指引（App 里）

    /// 试过的场景 id。
    static var labTried: Set<String> {
        Set(SharedStorage.defaults.stringArray(forKey: labKey) ?? [])
    }

    static func markLabTried(_ id: String) {
        var tried = labTried
        guard tried.insert(id).inserted else { return }
        SharedStorage.defaults.set(Array(tried).sorted(), forKey: labKey)
    }

    // MARK: 读（App 里）

    /// 最近 7 天的合计。
    static func week(_ counter: String) -> Int {
        DailyStats.series(counter, days: 7).reduce(0) { $0 + $1.value }
    }

    static func today(_ counter: String) -> Int {
        DailyStats.series(counter, days: 1).first?.value ?? 0
    }
}
