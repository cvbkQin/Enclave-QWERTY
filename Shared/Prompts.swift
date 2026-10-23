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
        return [.system(system(style: style)), .user(prompt)]
    }

    static func writeSystem(style: StylePreset?) -> ChatMessage {
        .system(system(style: style) + "\n用户会描述想写的内容，你直接写出可以发送的正文。用户后续追加的要求，是对你上一版的修改意见。")
    }
}
