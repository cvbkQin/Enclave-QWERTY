import Foundation

/// 隐私政策里 iCloud 同步的段落按包里有没有同步能力显示（05 标，04 三审第 5 条）。
/// 写法 `[[iCloud:有同步时的文字||没有同步时的文字]]`；「||」和后半段可以省，表示没有同步时整段去掉。
/// 段落前后的空行由标的人包进标记里（05 已按纯文本核对过）。不支持嵌套，文字里不能有「]]」「||」。
/// 网页和 PRIVACY.md 由 scripts/gen-privacy.py 按 Configs/Base.xcconfig 的 ICLOUD_SYNC 做同样的处理。
enum PolicyFilter {
    static func apply(_ text: String, iCloudSync on: Bool) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: "[[iCloud:") {
            result += rest[..<open.lowerBound]
            let body = rest[open.upperBound...]
            // 没配对：原样留下（gen-privacy.py 会报错，App 里不至于把后面的字吞掉）。
            guard let close = body.range(of: "]]") else { return result + rest[open.lowerBound...] }
            let inner = body[..<close.lowerBound]
            if let bar = inner.range(of: "||") {
                result += on ? inner[..<bar.lowerBound] : inner[bar.upperBound...]
            } else if on {
                result += inner
            }
            rest = body[close.upperBound...]
        }
        return result + rest
    }
}
