import Foundation

/// AI 帮回（T16）：帮回是润色的一种（帮回并入润色，方案 D v6）。复制了对方的话，用当前的润色风格写一条回复，走润色接口（主接口）。
/// 不联网搜索；对方的名字键盘读不到，不发给模型。只发对方的话、润色风格的要求、识意框里的要求和输入框里自己打的字。
enum HelpReply {
    /// 只写一条，直接输出回复本身，边写边显示。
    /// style：当前润色风格（没有或提示词是空的，按「自然、像本人」写）。meaning：输入框里自己打的字（想表达的意思）。request：识意框里的要求。
    static func messages(message: String, style: StylePreset?, meaning: String = "", request: String = "") -> [ChatMessage] {
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = """
        你在帮用户回复别人发来的消息。用户复制了对方说的话，请以用户本人的口吻，写一条可以直接发出去的回复。
        要求：
        - 只输出回复本身，不解释、不加引号、不写「回复：」之类的前缀，不写编号；不用 Markdown 符号。
        - 用对方消息的语言回复（风格或要求里指定了语言时照它）；中文一律用简体。
        - 像真人在聊天软件里打字，长度和对方的话差不多，不要客套过头，不要编造对方没提到的具体事实（时间、地点、人名可以照对方说的）。
        - 给了「用户想表达的意思」时，回复要表达这个意思，可以调整说法，但不要改掉意思。
        """
        let rule = style?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var prompt = """
        <对方的话>
        \(message)
        </对方的话>

        """
        if rule.isEmpty {
            prompt += "风格：自然、像本人。"
        } else {
            prompt += "下面是用户选的润色风格，只取它对语气、用词、长度的要求，用在你写的回复上：\n\(rule)"
        }
        if !meaning.isEmpty {
            prompt += "\n\n<用户想表达的意思>\n\(meaning)\n</用户想表达的意思>"
        }
        if !request.isEmpty {
            prompt += "\n\n要求：\(request)"
        }
        return [.system(system), .user(prompt)]
    }

    /// 一种风格的输出：去掉模型偶尔加的「【1】」、引号、「风格「x」：」前缀。写到一半也能用（边写边显示）。
    static func single(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(【\s*\d*\s*】?|\d+[\.、．)）]\s)"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return clean(text)
    }

    /// 去掉首尾空白、成对的引号、「风格名：」之类的前缀。
    private static func clean(_ part: String) -> String {
        var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(风格)?「[^」]{1,8}」[：:]\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let pairs: [(Character, Character)] = [("“", "”"), ("\"", "\""), ("「", "」"), ("『", "』")]
        for (open, close) in pairs where text.count > 2 && text.first == open && text.last == close {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 剪贴板记录长按菜单里出不出「帮回这条」：单号、链接、纯数字、邮箱这类不出。
    static func suits(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 1000 else { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return false }
        if trimmed.range(of: #"^[A-Za-z0-9_.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil { return false }
        // 单号、验证码、电话：只有字母数字和连字符、空格，没有汉字也没有普通的词（至少一个数字）。
        if trimmed.range(of: #"^[A-Za-z0-9\-_ /#]+$"#, options: .regularExpression) != nil,
           trimmed.contains(where: \.isNumber) { return false }
        if trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace || $0.isSymbol }) { return false }
        return true
    }
}

/// 「待回的复制」（帮回并入润色 §3）：键盘看到剪贴板换了新内容，只看 changeCount / hasStrings，不读内容。
/// 不是键盘自己复制的、系统判断不是链接或纯数字（detectPatterns，不读内容、不弹横幅）、键盘第一次看到不到 10 分钟、还没帮回过。
struct HelpCopy: Codable, Equatable {
    var count: Int
    /// 键盘第一次看到这份复制的时间。
    var seen: Date
    /// 帮回过、键盘自己复制的、没有文字的：不再算待回。
    var used: Bool
    /// detectPatterns 的结果：nil 还没查，false 是链接或纯数字。
    var suits: Bool?

    static let window: TimeInterval = 600

    func pending(now: Date = Date()) -> Bool {
        !used && suits == true && now.timeIntervalSince(seen) >= 0 && now.timeIntervalSince(seen) < Self.window
    }

    /// 什么时候过期（10 分钟）。
    var expires: Date { seen.addingTimeInterval(Self.window) }

    /// 看一眼剪贴板：还是同一份就照旧；换了新内容记下第一次看到的时间。
    /// 第一次用（没有记录）：剪贴板里原来的内容不算新复制。
    static func observe(_ stored: HelpCopy?, count: Int, hasStrings: Bool, now: Date = Date()) -> HelpCopy {
        if var stored, stored.count == count {
            if !hasStrings { stored.used = true }
            return stored
        }
        return HelpCopy(count: count, seen: now, used: stored == nil || !hasStrings, suits: nil)
    }
}
