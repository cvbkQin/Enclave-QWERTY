import Foundation

/// 在结果卡里改字（修改模式）用到的纯文字计算。位置一律按「第几个字」（Character）算，和 KeyboardModel.cardCaret 一样；
/// 排版（NSLayoutManager、NSString）用 UTF-16，表情等一个字占两个单位，这里负责两边换算。
enum CardTextEditing {
    /// 第几个字 → UTF-16 位置。
    static func utf16Offset(_ index: Int, in text: String) -> Int {
        String(text.prefix(max(index, 0))).utf16.count
    }

    /// UTF-16 位置 → 第几个字。落在一个字中间（表情的两个单位之间）算到这个字后面。
    static func characterIndex(utf16 offset: Int, in text: String) -> Int {
        var count = 0
        var units = 0
        for character in text {
            if units >= offset { break }
            units += character.utf16.count
            count += 1
        }
        return count
    }

    /// 长按选词：点到的那个字所在的词。中文按系统分词选一个词，英文、数字选一个单词；
    /// 点在空格、标点上（不属于任何词）就只选这一个字。index 超出末尾时按最后一个字算；没有字时返回 nil。
    static func wordRange(at index: Int, in text: String) -> Range<Int>? {
        guard !text.isEmpty else { return nil }
        let at = min(max(index, 0), text.count - 1)
        let string = text as NSString
        let target = utf16Offset(at, in: text)
        var found: NSRange?
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length),
                                   options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if range.location > target {
                stop.pointee = true
            } else if NSLocationInRange(target, range) {
                found = range
                stop.pointee = true
            }
        }
        guard let found else { return at..<(at + 1) }
        let lower = characterIndex(utf16: found.location, in: text)
        let upper = characterIndex(utf16: NSMaxRange(found), in: text)
        return lower < upper ? lower..<upper : at..<(at + 1)
    }

    /// 两头不分先后的一段。
    static func range(_ a: Int, _ b: Int) -> Range<Int> { min(a, b)..<max(a, b) }

    /// range 里的字，超出的部分不算。
    static func substring(_ range: Range<Int>, of text: String) -> String {
        let lower = min(max(range.lowerBound, 0), text.count)
        let upper = min(max(range.upperBound, lower), text.count)
        return String(Array(text)[lower..<upper])
    }

    /// 把 range 换成 replacement（replacement 为空就是删掉），返回新的文字和光标（放在换进去的字后面）。
    static func replacing(_ range: Range<Int>, in text: String, with replacement: String) -> (text: String, caret: Int) {
        var characters = Array(text)
        let lower = min(max(range.lowerBound, 0), characters.count)
        let upper = min(max(range.upperBound, lower), characters.count)
        characters.replaceSubrange(lower..<upper, with: Array(replacement))
        let result = String(characters)
        return (result, min(lower + replacement.count, result.count))
    }
}
