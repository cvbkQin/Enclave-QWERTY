import XCTest

/// 输入框里的「内容 // 要求」。
final class CommandParserTests: XCTestCase {
    func testSplitsContentAndInstruction() {
        XCTAssertEqual(CommandParser.parse("明天开会 // 写正式一点"),
                       .init(content: "明天开会", instruction: "写正式一点"))
    }

    func testNoSeparator() {
        XCTAssertEqual(CommandParser.parse("  只有内容  "), .init(content: "只有内容", instruction: ""))
    }

    func testURLIsNotSeparator() {
        XCTAssertEqual(CommandParser.parse("看看 https://example.com/a"),
                       .init(content: "看看 https://example.com/a", instruction: ""))
        XCTAssertEqual(CommandParser.parse("看看 https://example.com // 总结一下"),
                       .init(content: "看看 https://example.com", instruction: "总结一下"))
    }

    func testUsesLastSeparator() {
        XCTAssertEqual(CommandParser.parse("a // b // c"), .init(content: "a // b", instruction: "c"))
    }

    func testOnlyInstruction() {
        XCTAssertEqual(CommandParser.parse("// 帮我写请假条"), .init(content: "", instruction: "帮我写请假条"))
    }
}
