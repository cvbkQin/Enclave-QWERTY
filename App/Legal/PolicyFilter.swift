import Foundation

/// 隐私政策里只在某种包里才有的说法（05 标，04 三审第 5 条）：
/// - `[[icloud]]…[[/icloud]]`：只在带 iCloud 同步能力的包里显示；
/// - `[[no-icloud]]…[[/no-icloud]]`：只在不带的包里显示（换掉上面那句时用）。
/// 标记可以包一句话，也可以包整行、整段：从行首包到行尾时连这一行的换行一起去掉，列表里去掉一项不会多出空行。
/// 去掉整段后多出来的空行合成一个。网页版和 PRIVACY.md 跟着 Configs/Base.xcconfig 的 ICLOUD_SYNC 默认值生成（scripts/gen-privacy.py 里同样的规则）：
/// 网页也是 App Store 里填的隐私政策网址，正式包不带同步时不写同步。
enum PolicyFilter {
    static func apply(_ text: String, iCloudSync: Bool) -> String {
        let drop = iCloudSync ? "no-icloud" : "icloud"
        let keep = iCloudSync ? "icloud" : "no-icloud"
        // 不跨过结束标记：一行里有好几处、或者后面还有别的块时，只去掉这一块。
        let block = "\\[\\[\(drop)\\]\\](?:(?!\\[\\[/\(drop)\\]\\])[\\s\\S])*\\[\\[/\(drop)\\]\\]"
        var result = text.replacingOccurrences(of: "(?m)^" + block + "\\n", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: block, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[\\[/?\(keep)\\]\\]", with: "", options: .regularExpression)
        return result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    }
}
