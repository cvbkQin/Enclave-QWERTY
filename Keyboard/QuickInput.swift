import Foundation

/// 快捷输入（0.95 A6），和搜狗、百度这些输入法的习惯一样：
/// - 全键盘打 rq、sj、xq：候选第二个起给出今天的日期、现在的时间、星期几；
/// - 全键盘先打 v 再打数字（123.45）：候选是大写金额、大写数字、中文数字；
/// - 打完「1+2=」这样的算式：候选栏给出结果，点一下接着上屏。
enum QuickInput {
    // MARK: 日期、时间、星期

    /// rq、sj、xq 对应的候选；别的输入为 nil。
    static func dateCandidates(for raw: String, now: Date = Date()) -> [String]? {
        let calendar = Calendar(identifier: .gregorian)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        guard let year = c.year, let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute,
              let weekday = c.weekday else { return nil }
        let week = ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]
        let time = String(format: "%02d:%02d", hour, minute)
        switch raw {
        case "rq":
            return ["\(year)年\(month)月\(day)日", String(format: "%04d-%02d-%02d", year, month, day), "\(month)月\(day)日"]
        case "sj":
            return [time, "\(hour)点\(minute)分", "\(year)年\(month)月\(day)日 \(time)"]
        case "xq":
            return ["星期\(week)", "周\(week)", "\(month)月\(day)日 星期\(week)"]
        default:
            return nil
        }
    }

    // MARK: v + 数字

    /// v 后面能接的键：数字和小数点。
    static func isNumberKey(_ key: String) -> Bool {
        key.count == 1 && (key.first!.isASCII && key.first!.isNumber || key == ".")
    }

    /// v 后面打的数字：大写金额（壹佰贰拾叁元肆角伍分）、大写数字（壹佰贰拾叁点肆伍）、中文数字（一百二十三点四五），最后是数字本身。
    static func numberCandidates(_ digits: String) -> [String] {
        guard let (integer, fraction) = split(digits) else { return [digits] }
        var result: [String] = []
        if let amount = amount(integer: integer, fraction: fraction) { result.append(amount) }
        let upper = chinese(integer, upper: true) + (fraction.isEmpty ? "" : "点" + fraction.map { upperDigits[$0.wholeNumberValue!] }.joined())
        let lower = chinese(integer, upper: false) + (fraction.isEmpty ? "" : "点" + fraction.map { lowerDigits[$0.wholeNumberValue!] }.joined())
        for text in [upper, lower, digits] where !result.contains(text) { result.append(text) }
        return result
    }

    private static let upperDigits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
    private static let lowerDigits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 整数部分去掉开头的 0，最多 16 位；小数点只能有一个。
    private static func split(_ digits: String) -> (String, String)? {
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !digits.isEmpty, digits != "." else { return nil }
        var integer = String(parts[0].drop { $0 == "0" })
        if integer.isEmpty { integer = "0" }
        guard integer.count <= 16 else { return nil }
        return (integer, parts.count == 2 ? String(parts[1]) : "")
    }

    /// 大写金额：小数最多两位（角、分）；整数是 0 时只写角分，都是 0 写「零元整」。
    private static func amount(integer: String, fraction: String) -> String? {
        guard fraction.count <= 2 else { return nil }
        let jiao = fraction.first?.wholeNumberValue ?? 0
        let fen = fraction.count > 1 ? fraction.last!.wholeNumberValue! : 0
        var text = integer == "0" ? "" : chinese(integer, upper: true) + "元"
        if jiao == 0 && fen == 0 { return (text.isEmpty ? "零元" : text) + "整" }
        if jiao > 0 { text += upperDigits[jiao] + "角" } else if !text.isEmpty { text += "零" }
        if fen > 0 { text += upperDigits[fen] + "分" } else { text += "整" }
        return text
    }

    /// 整数读成中文：四位一节（个、万、亿、兆），节内拾佰仟，中间的 0 读一个「零」。
    private static func chinese(_ integer: String, upper: Bool) -> String {
        let digits = upper ? upperDigits : lowerDigits
        let units = upper ? ["", "拾", "佰", "仟"] : ["", "十", "百", "千"]
        let sections = ["", "万", "亿", "兆"]
        let values = integer.compactMap(\.wholeNumberValue)
        if values.allSatisfy({ $0 == 0 }) { return digits[0] }
        var groups: [[Int]] = []
        var rest = values
        while !rest.isEmpty {
            groups.insert(Array(rest.suffix(4)), at: 0)
            rest = Array(rest.dropLast(4))
        }
        var result = ""
        var needZero = false
        for (g, group) in groups.enumerated() {
            let section = sections[groups.count - 1 - g]
            if group.allSatisfy({ $0 == 0 }) {
                needZero = !result.isEmpty
                continue
            }
            let padded = Array(repeating: 0, count: 4 - group.count) + group
            for (i, value) in padded.enumerated() {
                if value == 0 {
                    if !result.isEmpty { needZero = true }
                    continue
                }
                if needZero { result += digits[0]; needZero = false }
                result += digits[value] + units[3 - i]
            }
            result += section
            needZero = padded.last == 0
        }
        // 「一十二」读作「十二」（只在开头、小写时）。
        if !upper, result.hasPrefix("一十") { result.removeFirst() }
        return result
    }

    // MARK: 算式

    /// 输入框里光标前以「=」结尾的算式（1+2=、3×4.5=、(1+2)÷3=），算出结果；不是算式或算不出时为 nil。
    static func calculate(before text: String) -> String? {
        guard text.hasSuffix("=") || text.hasSuffix("＝") else { return nil }
        let allowed = Set("0123456789.+-*/×÷()（）＋－＊／")
        let expression = String(text.dropLast().reversed().prefix { allowed.contains($0) }.reversed())
        guard expression.contains(where: \.isNumber),
              expression.contains(where: { "+-*/×÷＋－＊／".contains($0) }) else { return nil }
        var parser = Parser(Array(expression.map { normalized($0) }))
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return format(value)
    }

    private static func normalized(_ c: Character) -> Character {
        switch c {
        case "×", "＊": return "*"
        case "÷", "／": return "/"
        case "＋": return "+"
        case "－": return "-"
        case "（": return "("
        case "）": return ")"
        default: return c
        }
    }

    /// 最多 10 位有效数字，去掉末尾的 0。
    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.10g", value)
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// 加减乘除和括号，先乘除后加减。
    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { index == chars.count }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < chars.count, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]; index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while index < chars.count, chars[index] == "*" || chars[index] == "/" {
                let op = chars[index]; index += 1
                guard let rhs = factor() else { return nil }
                if op == "/" && rhs == 0 { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        mutating func factor() -> Double? {
            guard index < chars.count else { return nil }
            if chars[index] == "-" { index += 1; return factor().map { -$0 } }
            if chars[index] == "(" {
                index += 1
                guard let value = expression(), index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            return index > start ? Double(String(chars[start..<index])) : nil
        }
    }
}
