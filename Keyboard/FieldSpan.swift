import Foundation

/// AI 这次读输入框里的哪一段。输入法不适合处理很长的文字，默认最多读光标前 100 字左右，
/// 而且按完整的句子或段落截：往回最多看 150 字找句号、问号、换行这类断点，取不超过 100 字的最长一段整句；
/// 100 字内没有断点就放宽到 150 字，再没有就退到逗号，实在没有才硬截 100 字。
/// 光标前后加起来不到 100 字就全读（光标在中间也一样）。「处理长文本」打开时是 200 / 250 字。
/// 替换时按 beforeCount / afterCount 删，读不到的字一个不动，撤销也能原样还原。
struct FieldSpan: Equatable {
    /// 平时 100 字、往回最多看 150 字；「处理长文本」打开时 200 / 250。
    static func limits(longText: Bool) -> (limit: Int, lookahead: Int) { longText ? (200, 250) : (100, 150) }

    let beforeCount: Int
    let afterCount: Int
    let text: String

    init(before: String, after: String, longText: Bool) {
        let (limit, lookahead) = Self.limits(longText: longText)
        if before.count + after.count <= limit {
            beforeCount = before.count
            afterCount = after.count
            text = before + after
            return
        }
        let chars = Array(before)
        let start = Self.start(in: chars, limit: limit, lookahead: lookahead)
        beforeCount = chars.count - start
        afterCount = 0
        text = String(chars[start...])
    }

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…", "\n", "\r"]
    private static let clauseEnds: Set<Character> = ["，", ",", "、", "：", ":"]

    /// 从哪个下标开始读（含）。
    static func start(in chars: [Character], limit: Int, lookahead: Int) -> Int {
        guard chars.count > limit else { return 0 }
        let count = chars.count
        // index 是一段的开头：前一个字是断点。英文句号后面跟空格也算。
        func isBoundary(_ index: Int, _ ends: Set<Character>) -> Bool {
            guard index > 0 else { return true }
            let previous = chars[index - 1]
            if ends.contains(previous) { return true }
            if ends == sentenceEnds, previous == " ", index >= 2, chars[index - 2] == "." { return true }
            return false
        }
        func earliest(within length: Int, _ ends: Set<Character>) -> Int? {
            let lowest = max(0, count - length)
            // 从最远处往近找，第一个断点就是最长的一段；跳过光标前紧挨着的空段。
            for index in lowest..<count where isBoundary(index, ends) && count - index > 0 {
                return index
            }
            return nil
        }
        return earliest(within: limit, sentenceEnds)
            ?? earliest(within: lookahead, sentenceEnds)
            ?? earliest(within: limit, clauseEnds)
            ?? count - limit
    }
}
