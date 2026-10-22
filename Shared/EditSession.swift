import Foundation

/// 一次编辑会话：从一段原话或一句「帮我写」开始，之后每一轮生成一个新版本。
/// 存在共享存储里，键盘进程被系统回收后还能接着用。
struct EditSession: Codable, Equatable {
    enum Mode: String, Codable { case polish, write }

    var mode: Mode
    /// 润色模式：用户最初的原话。帮我写模式：第一句要求。
    var original: String
    var versions: [String] = []
    var currentIndex: Int = 0
    /// 帮我写模式的多轮对话（不含 system）。
    var conversation: [ChatMessage] = []

    var current: String? {
        versions.indices.contains(currentIndex) ? versions[currentIndex] : nil
    }

    mutating func append(_ version: String) {
        versions.append(version)
        currentIndex = versions.count - 1
    }
}

enum SessionStore {
    private static let key = "session.v1"

    static func load() -> EditSession? {
        guard let data = SharedStorage.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EditSession.self, from: data)
    }

    static func save(_ session: EditSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            SharedStorage.defaults.set(data, forKey: key)
        } else {
            SharedStorage.defaults.removeObject(forKey: key)
        }
    }
}

/// 解析输入框里的「内容 // 要求」。
enum CommandParser {
    struct Command: Equatable {
        var content: String
        var instruction: String
    }

    /// 取最后一个不属于网址（前面不是 ":"）的 "//" 作为分隔符。
    static func parse(_ text: String) -> Command {
        var searchEnd = text.endIndex
        while let range = text.range(of: "//", options: .backwards, range: text.startIndex..<searchEnd) {
            let isURL = range.lowerBound > text.startIndex && text[text.index(before: range.lowerBound)] == ":"
            if !isURL {
                return Command(
                    content: text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines),
                    instruction: text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            searchEnd = range.lowerBound
        }
        return Command(content: text.trimmingCharacters(in: .whitespacesAndNewlines), instruction: "")
    }
}
