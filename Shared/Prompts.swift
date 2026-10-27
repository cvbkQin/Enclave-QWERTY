import Foundation

/// 三种操作的 prompt。润色和按要求改是单轮请求，帮我写保留多轮对话。
enum Prompts {
    static func system(style: StylePreset?) -> String {
        var text = """
        你是嵌在用户输入法里的写作助手。用户会把你的输出直接发给别人。
        规则：
        - 只输出最终正文，不要任何解释、前言或引号。
        - 不用 Markdown 符号（#、**、- 列表等），很多聊天软件不渲染。需要分点时用纯文本编号「1.」「2.」，子项用「①」「②」。
        - 使用用户原文的语言；中文一律用简体。
        - 不要编造用户没有提供的事实（时间、人名、数字等）。
        """
        if let style, !style.prompt.isEmpty {
            text += "\n\(style.prompt)"
        }
        return text
    }

    static func polish(_ content: String, style: StylePreset?) -> [ChatMessage] {
        // 风格只放在系统提示末尾时，模型常被下面详细的整理规则盖过，各风格出来几乎一样。
        // 所以在原文前面再单独强调一次，并说明它优先。
        var styleBlock = ""
        if let style, !style.prompt.isEmpty {
            styleBlock = """

            <本次风格>（必须体现，和上面的规则冲突时以它为准）
            \(style.prompt)
            </本次风格>
            事实不变，措辞、语气、长短和排版按这个风格改，和原文差别大也没关系。

            """
        }
        return [
            .system(system(style: style)),
            .user("""
            把下面这段口述整理成可以直接发送的文字。

            清理：
            - 删掉口头禅和填充词（嗯、那个、就是、然后、的话、对了 这类不带信息的词）和重复。
            - 说话中途改口的，只保留最后的说法。
            - 修正同音错字和标点，中英文之间加空格。

            排版，按内容决定，不要为排版而排版：
            - 简短的回复、闲聊、一两件事：写成一两句通顺的话，不分点、不加标题。
            - 包含多件事、多个步骤、进度或计划：按话题分组，每组一行小标题（如「上周进度：」「下周计划：」），组内用「1.」「2.」编号，细项用「①」「②」缩进两格。内容明显是一份文档（周报、纪要、清单）时，第一行加一个简短标题。
            - 组与组之间空一行。
            - 指定了风格时，风格的要求优先于上面的排版规则。

            不改变原意，不添加原文没有的信息，原文里的事实、数字、人名都要保留。
            \(styleBlock)
            <原文>
            \(content)
            </原文>
            """),
        ]
    }

    static func revise(original: String, current: String, instruction: String, style: StylePreset?) -> [ChatMessage] {
        var prompt = ""
        if original != current {
            prompt += """
            <最初草稿>（用户最初的意图，仅供参考）
            \(original)
            </最初草稿>

            """
        }
        prompt += """
        <当前版本>（可能包含用户的手动修改，这些修改必须保留）
        \(current)
        </当前版本>

        <修改要求>
        \(instruction)
        </修改要求>

        按修改要求改写当前版本。尽量少改动，要求没有涉及的地方保持原样。只输出修改后的完整正文。
        """
        if let block = requestStyleBlock(style) {
            prompt += "\n" + block
        }
        return [.system(system(style: style)), .user(prompt)]
    }

    static func writeSystem(style: StylePreset?) -> ChatMessage {
        .system(system(style: style) + "\n用户会描述想写的内容，你直接写出可以发送的正文。用户后续追加的要求，是对你上一版的修改意见。")
    }

    /// 帮我写：最后一条要求后面附上本次风格。会话里存的仍是用户的原话，换了风格再追问时按新风格写。
    static func write(_ conversation: [ChatMessage], style: StylePreset?) -> [ChatMessage] {
        var messages = [writeSystem(style: style)] + conversation
        if let block = requestStyleBlock(style), let last = messages.indices.last, messages[last].role == "user" {
            messages[last].content += "\n\n" + block
        }
        return messages
    }

    /// 按要求改和帮我写时的风格：只放在系统提示里会被「尽量少改动」和要求本身盖过，
    /// 所以和润色一样在用户消息里再强调一次。选了「自动」时没有。
    private static func requestStyleBlock(_ style: StylePreset?) -> String? {
        guard let style, !style.prompt.isEmpty else { return nil }
        return """
        <本次风格>「\(style.name)」
        \(style.prompt)
        </本次风格>
        按要求写，同时整体的语气和措辞用这个风格，为了贴合风格可以多改一些，不受「尽量少改动」限制。
        要求里明确写了的（比如字数、要不要分点、具体的说法）以要求为准。
        """
    }

    /// 「识意」：一句话，可能是修改要求（或让它帮忙写），也可能是问题。输入框里的原文作为上下文，空就不带。
    /// 让模型第一行先写「改写」或「问答」，键盘据此决定直接替换还是展开卡片；forceAnswer 为 nil 时由模型判断。
    /// search：问答接口能联网（千问、Kimi、智谱）。模型判断要查最新信息时第一行写「联网」，键盘按三档决定联不联网；
    /// 联网时只拿用户的话原样去搜（隐私政策写明只发问题本身，不带输入框里的字）。
    /// results：Kimi 搜到的资料（WebSearch.digest）；有资料时按问答回答，末尾一行写来源。
    /// builtinSearch：这次请求打开了服务商自带的联网（千问、智谱），只带问题，这里交代日期和来源的写法。
    /// offline：要联网但没允许（拒绝或禁止后选了直接回答），按已有知识答并说明可能不是最新的。
    /// answerStyle：问答风格（AI 栏蓝色那颗），换掉「问答的正文」那一行，并在用户消息里再强调一次；空就按简短直接。
    /// tendency：联网倾向 0–4，档位越高「联网的情况」清单越长；0 不告诉模型能联网（只能点「使用联网查询」）。
    static func ask(_ question: String, context: String, forceAnswer: Bool?,
                    search: Bool = false, builtinSearch: Bool = false, offline: Bool = false,
                    results: String? = nil, answerStyle: StylePreset? = nil, tendency: Int = 2) -> [ChatMessage] {
        let answerRule = answerStyle.map(\.prompt).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "简短直接，几句话说清楚。"
        var system = """
        你是嵌在用户输入法里的助手。用户在聊天输入框里写了一段话（可能为空），又在键盘上的小框里对你说了一句话：可能是对这段话的修改要求（包括翻译、换语气、帮忙写一段），也可能是一个问题。
        先判断是哪种：
        - 改写：要你产出一段可以直接发出去的文字。
        - 问答：要你解释、比较、给建议或回答问题，用户看完自己决定怎么写。
        输出格式：第一行只写「改写」或「问答」两个字，从第二行开始写正文，不要别的说明。
        改写的正文：只输出最终可以发送的完整文字，不要解释、前言或引号；尽量少改动，要求没涉及的地方保持原样；没有原文时直接写。
        问答的正文：\(answerRule)
        都要遵守：不用 Markdown 符号（#、**、- 列表等），需要分点时用「1.」「2.」；回答用用户说话的语言，中文一律用简体；不要编造原文没有的事实。
        """
        let today = Self.today()
        if let results {
            system += """

            今天是 \(today)。下面 <搜索资料> 是刚联网搜到的，这次按「问答」处理：先给结论，只用和问题直接相关的一两条资料，不复述资料、不铺垫；资料不够就直说，不要编。
            正文最后单独一行写「来源：」，后面最多列两个用到的网站名，用「、」隔开，不写链接。
            """
        } else if search && tendency > 0 {
            system += "\n\n今天是 \(today)。你可以联网。" + searchRules(tendency)
        } else if builtinSearch {
            system += """

            今天是 \(today)。这次必须先联网搜索再回答，根据搜到的资料：先给结论，只用和问题直接相关的一两条，不复述资料、不铺垫；资料不够就直说，不要编。
            正文最后单独一行写「来源：」，后面最多列两个用到的网站名，用「、」隔开，不写链接。
            """
        } else if offline {
            system += """

            今天是 \(today)。这次不能联网，按已有的知识回答；只有确实涉及实时信息时，才说明可能不是最新的。
            """
        } else {
            system += "\n\n今天是 \(today)。"
        }
        var prompt = ""
        if !context.isEmpty {
            prompt += """
            <输入框原文>
            \(context)
            </输入框原文>

            """
        }
        prompt += """
        <用户的话>
        \(question)
        </用户的话>
        """
        if let chosen = answerStyle, !chosen.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 和改写风格一样在用户消息里再说一次，不然会被搜索资料盖过去。只管问答，改写照旧。
            prompt += """


            <问答风格>「\(chosen.name)」
            \(chosen.prompt)
            </问答风格>
            如果这次是问答，正文按这个风格写；是改写就不管它。
            """
        }
        if let results {
            prompt += "\n\n<搜索资料>\n\(results)\n</搜索资料>\n\n这次按「问答」处理：第一行写「问答」，然后回答。"
            return [.system(system), .user(prompt)]
        }
        if let forceAnswer {
            prompt += forceAnswer
                ? "\n\n这次按「问答」处理：第一行写「问答」，然后回答。"
                : "\n\n这次按「改写」处理：第一行写「改写」，然后只输出改好的完整正文。"
        }
        return [.system(system), .user(prompt)]
    }

    /// 联网倾向第 1–4 档的规则：「联网的情况」逐档多一条，每档都带「不联网」清单（规格第 6 节）。
    static func searchRules(_ tendency: Int) -> String {
        let cases = [
            "用户明确说要查、搜、要最新的",
            "今天的天气、实时价格、汇率、比分",
            "新闻、近期发生的事、刚发布的产品或版本",
            "某个产品、公司、人物、政策现在的情况（比如现任负责人、现在的价格和规定、最新进展）",
            "你不确定的具体事实，比如数字、日期、时刻表、参数规格；宁可查一下，也不要凭印象给出可能不准的数字",
        ]
        let count = min(max(tendency, 1), 4) + 1
        let list = cases.prefix(count).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "；")
        let ending = tendency >= 4 ? "列表以外的问题直接回答。" : "其他情况拿不准时，直接回答。"
        return """
        只有遇到下面列出的情况才联网：第一行只写「联网」两个字，不要写别的，键盘会拿用户的话去搜，搜到的资料再发给你。\
        不在列表里就照常按上面的格式回答，不要写「联网」。下面这些一律不联网：解释概念、写作、翻译、计算、给建议、闲聊、改写。
        联网的情况：\(list)。\(ending)
        """
    }

    enum SearchProbe: Equatable { case pending, search, no }

    /// 识意输出开头是不是「联网」。还没写够两个字、看不出来时 pending。
    static func searchProbe(_ text: String, final: Bool) -> SearchProbe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "联网"
        if trimmed.hasPrefix(marker) { return .search }
        return marker.hasPrefix(trimmed) && !final ? .pending : .no
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 拆出「识意」输出第一行的类型。还没写完第一行时返回 nil；final 时没写类型就当 fallback。
    static func splitAsk(_ text: String, final: Bool, fallback: Bool) -> (answer: Bool, body: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers: [(String, Bool)] = [("改写", false), ("问答", true), ("回答", true)]
        let head = trimmed.prefix(8).trimmingCharacters(in: CharacterSet(charactersIn: "【】[]「」:：*# "))
        for (marker, answer) in markers where head.hasPrefix(marker) {
            // 类型后面的正文：第一行剩下的（模型偶尔写在同一行）加上后面几行。
            guard let markerRange = trimmed.range(of: marker) else { break }
            let skip = CharacterSet(charactersIn: "】]」:：*# \n")
            let rest = trimmed[markerRange.upperBound...].drop { $0.unicodeScalars.allSatisfy(skip.contains) }
            return (answer, String(rest))
        }
        // 第一行已经写完（或够长）还不是类型：模型没按格式来，整段当正文。
        if final || trimmed.contains("\n") || trimmed.count > 8 {
            return (fallback, trimmed)
        }
        return nil
    }
}
