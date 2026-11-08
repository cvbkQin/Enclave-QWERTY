import Foundation

/// AI 帮回（T16）：复制了对方的话，点「帮回」，用润色接口（主接口，11-08 起）写回复，一次写一种风格。
/// 不联网搜索；对方的名字键盘读不到，不发给模型。只发对方的话、风格的要求和用户填的回复方向。
enum HelpReply {
    /// 一次写几条：每种风格一条，按卡片上的顺序。direction：用户在下面框里写的回复方向（可空）。
    static func messages(message: String, styles: [StylePreset], direction: String) -> [ChatMessage] {
        let direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = """
        你在帮用户回复别人发来的消息。用户复制了对方说的话，请以用户本人的口吻，写几条可以直接发出去的回复，每条按指定的风格。
        要求：
        - 只写回复本身，不解释、不加引号、不写「回复：」之类的前缀；不用 Markdown 符号。
        - 用对方消息的语言回复（风格里要求用英文时用英文）；中文一律用简体。
        - 像真人在聊天软件里打字，长度和对方的话差不多，不要客套过头，不要编造对方没提到的具体事实（时间、地点、人名可以照对方说的）。
        - 几条之间要有区别，不要只换几个字。
        输出格式：每条前面单独一行写编号，形如「【1】」「【2】」，编号后的下一行开始写这一条，不要别的内容。
        """
        var prompt = """
        <对方的话>
        \(message)
        </对方的话>

        要写 \(styles.count) 条：
        """
        for (index, style) in styles.enumerated() {
            let rule = style.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            prompt += "\n【\(index + 1)】风格「\(style.name)」" + (rule.isEmpty ? "" : "：\(rule)")
        }
        if !direction.isEmpty {
            prompt += "\n\n回复方向（每条都按这个方向写）：\(direction)"
        }
        return [.system(system), .user(prompt)]
    }

    /// 一次只写一种（cvbk 11-06）：只写一条，直接输出回复本身，边写边显示。
    static func messages(message: String, style: StylePreset, direction: String) -> [ChatMessage] {
        let direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = """
        你在帮用户回复别人发来的消息。用户复制了对方说的话，请以用户本人的口吻，写一条可以直接发出去的回复。
        要求：
        - 只输出回复本身，不解释、不加引号、不写「回复：」之类的前缀，不写编号；不用 Markdown 符号。
        - 用对方消息的语言回复（风格里要求用英文时用英文）；中文一律用简体。
        - 像真人在聊天软件里打字，长度和对方的话差不多，不要客套过头，不要编造对方没提到的具体事实（时间、地点、人名可以照对方说的）。
        """
        let rule = style.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = """
        <对方的话>
        \(message)
        </对方的话>

        风格「\(style.name)」
        """ + (rule.isEmpty ? "" : "：\(rule)")
        if !direction.isEmpty {
            prompt += "\n回复方向：\(direction)"
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

    /// 从模型输出里拆出 count 条。认「【1】」编号；没写编号时退回按「1.」开头的行、再退回按空行分段。
    /// 拆不出来返回空数组；拆出的比要的多只取前 count 条。
    static func parse(_ raw: String, count: Int) -> [String] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var parts = split(text, pattern: #"(?m)^\s*【\s*\d+\s*】\s*"#)
        if parts.count < min(count, 2) {
            parts = split(text, pattern: #"(?m)^\s*(?:\d+[\.、．)）]|[（(]\d+[)）])\s*"#)
        }
        if parts.count < min(count, 2) {
            parts = text.components(separatedBy: "\n\n")
        }
        let cleaned = parts.map(clean).filter { !$0.isEmpty }
        return Array(cleaned.prefix(count))
    }

    private static func split(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }
        var parts: [String] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            parts.append(ns.substring(with: NSRange(location: start, length: max(end - start, 0))))
        }
        return parts
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

    /// 帮回卡上点润色：输入框里的字还算不算替换进去的那条回复（允许手改）。
    /// 一半以上的字还在（按字数算，不管顺序），而且没比回复长出一倍多，就算同一条。
    static func related(_ field: String, _ reply: String) -> Bool {
        let field = field.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !field.isEmpty, !reply.isEmpty else { return false }
        if field.contains(reply) { return field.count <= reply.count * 2 + 20 }
        guard field.count <= reply.count * 2 + 20 else { return false }
        var pool: [Character: Int] = [:]
        for ch in field where !ch.isWhitespace { pool[ch, default: 0] += 1 }
        var kept = 0, total = 0
        for ch in reply where !ch.isWhitespace {
            total += 1
            if let n = pool[ch], n > 0 {
                kept += 1
                pool[ch] = n - 1
            }
        }
        return total > 0 && Double(kept) / Double(total) >= 0.5
    }

    /// 剪贴板记录里哪条显示「帮回」：单号、链接、纯数字、邮箱这类不显示（T16 入口二）。
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
