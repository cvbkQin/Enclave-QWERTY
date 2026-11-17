import Foundation

/// 选词上屏的写法（T9 限字数框 × #24 闲鱼）。只在测试工具里能切，正式版一直是「换标记区」。
///
/// - replaceMarked（原来的，dd45c72）：把标记区直接换成要上屏的字（非空 setMarkedText）再 unmark。
///   各家输入框都认，闲鱼 / 标签打印这类 Flutter 框也对；但不经过对方的 shouldChangeCharactersIn，限 10 个字的框管不住（T9）。
/// - selectThenInsert（新）：先把标记区的拼音整段选中（setMarkedText 原样再设一次，选区盖住整段），再 insertText 选的字，最后 unmark。
///   普通 UIKit 框里 insertText 替换标记区、会问对方 shouldChangeCharactersIn，限长框能拒；
///   Flutter 3.x 引擎的 insertText 替换的是「当前选区」（不是标记区，所以以前直接 insertText 会变成「hao de好的」），
///   选区先盖住整段拼音，替换的正好就是拼音。最后 unmark：旧版 Flutter 插入后标记区不清，不 unmark 下一次打拼音会把刚上屏的字换掉。
///   不用空的 setMarkedText 收尾：旧版 Flutter 里标记区还指着刚上屏的字，空的一设就把字删了。
enum CommitStyle: String, CaseIterable {
    case replaceMarked
    case selectThenInsert

    private static let key = "debug.commitStyle"

    /// 测试工具里手动选的；没选过是 nil。
    static var chosen: CommitStyle? {
        get { SharedStorage.defaults.string(forKey: key).flatMap(CommitStyle.init(rawValue:)) }
        set { SharedStorage.defaults.set(newValue?.rawValue, forKey: key) }
    }

    /// 实际用的：正式版、内测、公测一直是原来的；开发版（含模拟器 DEBUG）默认试新的，测试工具里能切回去。
    static var current: CommitStyle {
        guard canChoose else { return .replaceMarked }
        return chosen ?? .selectThenInsert
    }

    /// 只在开发版能切（含 DEBUG）。
    static var canChoose: Bool {
        #if DEBUG
        return true
        #else
        return BuiltinAPI.isDevBuild
        #endif
    }
}
