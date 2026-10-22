import Foundation

/// 把字母键变成文字的输入引擎。
/// 第 1 步只有直通引擎（字母原样上屏），第 2 步在这里接入 RIME 拼音。
protocol InputEngine: AnyObject {
    /// 正在拼写、还没上屏的字母，例如 "nihao"。
    var composition: String { get }
    /// 当前候选词。
    var candidates: [String] { get }

    /// 输入一个字母。返回需要立刻上屏的文字；返回 nil 表示进入了组字。
    func input(_ letter: String) -> String?
    /// 组字中按删除键时由引擎处理并返回 true；没在组字返回 false。
    func backspace() -> Bool
    /// 选择候选词，返回要上屏的文字。
    func select(_ index: Int) -> String?
    /// 放弃候选，把拼写的字母原样上屏（回车键）。
    func commitComposition() -> String?
    func reset()
}

extension InputEngine {
    var isComposing: Bool { !composition.isEmpty }
}

/// 字母原样上屏，用于英文模式，也是接入拼音之前的默认引擎。
final class DirectEngine: InputEngine {
    var composition: String { "" }
    var candidates: [String] { [] }
    func input(_ letter: String) -> String? { letter }
    func backspace() -> Bool { false }
    func select(_ index: Int) -> String? { nil }
    func commitComposition() -> String? { nil }
    func reset() {}
}
