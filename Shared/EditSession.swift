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
    /// 用户在卡片里手改后存下的版本序号，卡片上标「已改」。旧数据里没有这一项。
    var editedVersions: [Int]?
    /// 「识意」生成的版本序号，其中 answerVersions 是回答（不是可以直接发出去的正文）。卡片按它画边框颜色。旧数据里没有。
    var askVersions: [Int]?
    var answerVersions: [Int]?

    var current: String? {
        versions.indices.contains(currentIndex) ? versions[currentIndex] : nil
    }

    /// 正在显示的是手改过的版本。
    var currentIsEdited: Bool { editedVersions?.contains(currentIndex) ?? false }

    mutating func append(_ version: String, edited: Bool = false) {
        versions.append(version)
        currentIndex = versions.count - 1
        if edited { editedVersions = (editedVersions ?? []) + [currentIndex] }
    }

    /// 正在显示的是「识意」的回答 / 「识意」改写的一版。
    var currentIsAnswer: Bool { answerVersions?.contains(currentIndex) ?? false }
    var currentIsAsk: Bool { askVersions?.contains(currentIndex) ?? false }

    /// 「识意」的结果：replacingLast 时顶掉最后一版（同一句换了方式重做），否则接在后面。
    mutating func appendAsk(_ version: String, answer: Bool, replacingLast: Bool) {
        if replacingLast, !versions.isEmpty {
            let last = versions.count - 1
            versions[last] = version
            editedVersions?.removeAll { $0 == last }
            answerVersions?.removeAll { $0 == last }
            currentIndex = last
        } else {
            versions.append(version)
            currentIndex = versions.count - 1
        }
        if !(askVersions ?? []).contains(currentIndex) { askVersions = (askVersions ?? []) + [currentIndex] }
        if answer { answerVersions = (answerVersions ?? []) + [currentIndex] }
    }

    /// 输入框里的文字是否还是这次会话的内容：包含原话或任一版本。
    /// 发出消息后重新打字、换了聊天或输入框，文字对不上，这次会话就不该再参与。
    func belongs(to fieldText: String) -> Bool {
        let text = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        return ([original] + versions).contains { piece in
            let piece = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            return !piece.isEmpty && text.contains(piece)
        }
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
