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
    /// 引擎收到的原始按键（九宫格是数字，选过拼音的部分是字母）。
    var rawInput: String { get }
    /// 整段换掉原始输入，用于九宫格在拼音列里选拼音。
    func replaceInput(_ raw: String)
    /// 候选只先取了第一屏；滑到头或展开整页时再往后取。
    func loadMoreCandidates()
}

extension InputEngine {
    var isComposing: Bool { !composition.isEmpty }
    var rawInput: String { "" }
    func replaceInput(_ raw: String) {}
    func loadMoreCandidates() {}
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
