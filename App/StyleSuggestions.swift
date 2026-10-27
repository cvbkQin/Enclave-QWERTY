import SwiftUI
import UIKit

/// 编辑风格页提示词下面的建议标签：点一下加进提示词，再点一下拿掉。
enum StyleSuggestions {
    /// 每条 20 个左右，常用的排前面。
    private static let byName: [String: [String]] = [
        "润色": ["修改错别字", "梳理表达", "补全标点", "保持原意", "不改语气", "去掉重复", "去掉口头禅", "中英文之间加空格",
               "理顺语序", "改掉病句", "统一用词", "数字用阿拉伯数字", "长句拆短", "删掉多余的字", "保留原来的分段",
               "不加新内容", "专有名词不改", "保留表情符号", "保留原来的称呼", "改动尽量少"],
        "正式": ["语气礼貌客观", "用完整句子", "称呼用「您」", "去掉口语词", "先说结论", "语气委婉一点", "不用感叹号", "适合发邮件",
               "开头加问候", "结尾加致谢", "不用网络用语", "不用表情", "用词准确专业", "避免绝对化说法", "条理清楚",
               "适合发给领导", "适合发给客户", "日期时间写完整", "数字写清楚单位", "不卑不亢"],
        "口语": ["语气轻松自然", "句子简短", "可以用口头语", "不要书面套话", "加点语气词", "可以加表情", "像朋友聊天", "别太客气",
               "幽默一点", "热情一点", "像发微信", "可以用网络用语", "少用成语", "一句一行", "像说话一样", "带点调侃",
               "亲切一点", "别太正经", "不要分点", "保留本人的说法"],
        "简短": ["只留关键信息", "删掉客套", "一句话说完", "不超过 50 字", "去掉重复", "保留数字和时间",
               "不超过 100 字", "删掉解释", "删掉铺垫", "只说结论", "保留人名地名", "去掉形容词", "能省则省",
               "不要开头问候", "不要结尾客套", "保留原意", "用短句", "像发短信", "保留待办事项", "三句以内"],
        "结构": ["分点列出", "先说结论", "按时间顺序", "加小标题", "每点一句话", "最后写下一步",
               "按重要程度排", "分成问题和方案", "加编号", "每点不超过 20 字", "提炼三个要点", "最后加总结",
               "待办写负责人", "保留数字", "按「背景 / 进展 / 计划」分组", "分优点和缺点", "列出时间节点",
               "去掉无关细节", "适合做会议纪要", "适合写周报"],
    ]
    /// 自己加的风格用通用建议。
    private static let generic = ["语气委婉一点", "修改错别字", "更简短", "分点列出", "先说结论", "翻成英文",
                                  "翻成日语", "语气礼貌", "语气轻松", "保持原意", "不加新内容", "适合发邮件",
                                  "适合发微信", "适合发给领导", "适合发给客户", "加个标题", "不超过 100 字",
                                  "去掉重复", "可以加表情", "不用感叹号"]

    /// 内置风格按名字认出来。
    static func builtIn(_ style: StylePreset) -> StylePreset? {
        StylePreset.defaults.first { $0.name == style.name }
    }

    static func tags(for style: StylePreset) -> [String] {
        byName[style.name] ?? generic
    }

    /// 接在提示词末尾，用「，」连上，保留结尾的「。」。
    static func adding(_ tag: String, to prompt: String) -> String {
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "。.，,；;".contains(last) { text.removeLast() }
        return (text.isEmpty ? tag : text + "，" + tag) + "。"
    }

    /// 把这句连同旁边的分隔符一起拿掉。
    static func removing(_ tag: String, from prompt: String) -> String {
        var text = prompt
        for pattern in ["，" + tag, tag + "，", "、" + tag, tag + "、", "；" + tag, tag] {
            if let range = text.range(of: pattern) {
                text.removeSubrange(range)
                break
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "，,、；;".contains(first) { text.removeFirst() }
        return text == "。" ? "" : text
    }
}

/// 一排排自动换行的标签。
struct SuggestionChips: View {
    let tags: [String]
    @Binding var prompt: String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let selected = prompt.contains(tag)
                Button {
                    // 点标签不该让名称框抢到焦点弹出键盘。
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    prompt = selected ? StyleSuggestions.removing(tag, from: prompt) : StyleSuggestions.adding(tag, to: prompt)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selected ? "checkmark" : "plus").font(.system(size: 11, weight: .semibold))
                        Text(tag).font(.system(size: 14, weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(AppColor.deepPurple)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(selected ? AppColor.chipSelectedFill : Color(.secondarySystemGroupedBackground)))
                    .overlay(Capsule().strokeBorder(selected ? AppColor.chipSelectedRing : AppColor.chipRing, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 从左往右排，排不下换行。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
