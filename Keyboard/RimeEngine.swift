import Foundation

/// RIME 拼音引擎（词库来自万象拼音）。词库由主 App 部署到共享目录，这里只加载。
final class RimeEngine: InputEngine {
    static let shared = RimeEngine()

    private(set) var composition = ""
    private(set) var candidates: [String] = []
    private var session: UInt64 = 0
    private var loadedVersion: String?
    private var schema = RimeStore.schemaID

    private static let candidateLimit = 150
    private static let backspaceKey: Int32 = 0xff08

    /// 准备好引擎并切到指定方案；词库没部署或读不到共享目录时返回 false。
    /// useShared：开了完全访问时用 App 部署到共享目录的词库（带模糊拼音）；否则用键盘自带的那份。
    func prepare(schema wanted: String, useShared: Bool) -> Bool {
        self.useShared = useShared
        guard prepare() else { return false }
        if wanted != schema {
            reset()
            guard enclave_rime_select_schema(session, wanted) else { return false }
            enclave_rime_set_option(session, "ascii_mode", false)
            schema = wanted
        }
        return true
    }

    /// 把常用词写成两份短语表（全拼、九宫格数字）放进现在用的用户目录。内容变了就重建会话，让引擎重新读。
    func updatePhrases(_ entries: [(text: String, code: String)]) {
        guard let (paths, _) = location() else { return }
        var changed = false
        let files = [
            ("enclave_phrase", CommonWordStore.phraseTable(entries, nineKey: false)),
            ("enclave_phrase_t9", CommonWordStore.phraseTable(entries, nineKey: true)),
            // 九宫格拼写栏显示常用词的拼音用（enclave_t9_preedit.lua 读）。
            // 同一个词有全拼和简码时只记第一个（全拼）。
            ("enclave_phrase_t9_pinyin", firstCodes(entries).map { "\($0.text)\t\($0.code)" }.joined(separator: "\n") + "\n"),
        ]
        for (name, table) in files {
            let url = paths.user.appendingPathComponent(name + ".txt")
            guard (try? String(contentsOf: url, encoding: .utf8)) != table else { continue }
            try? table.write(to: url, atomically: true, encoding: .utf8)
            changed = true
        }
        if changed && session != 0 {
            enclave_rime_destroy_session(session)
            session = 0
        }
    }

    private func firstCodes(_ entries: [(text: String, code: String)]) -> [(text: String, code: String)] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.text).inserted }
    }

    private var useShared = true
    /// 现在加载的是哪一份词库，调试时记下来。
    private(set) var source: String?

    private func location() -> (paths: RimeStore.Paths, version: String)? {
        if useShared, RimeStore.isDeployed, let version = RimeStore.deployedVersion, let paths = RimeStore.paths {
            return (paths, "shared:" + version)
        }
        return RimeStore.bundled.map { ($0.paths, "bundled:" + $0.version) }
    }

    private func prepare() -> Bool {
        guard let (paths, version) = location() else { return false }
        if loadedVersion != version {
            // App 重新部署过：重新加载新词库。
            if loadedVersion != nil {
                enclave_rime_finalize()
                session = 0
            }
            guard enclave_rime_start(paths.shared.path, paths.user.path, nil) else { return false }
            loadedVersion = version
            source = version
        }
        if !enclave_rime_session_alive(session) {
            session = enclave_rime_create_session(schema)
            guard session != 0 else { return false }
            enclave_rime_set_option(session, "ascii_mode", false)
        }
        return true
    }

    func input(_ letter: String) -> String? {
        guard prepare() else { return letter }
        var handled = false
        for scalar in letter.unicodeScalars {
            handled = enclave_rime_process_key(session, Int32(scalar.value), 0) || handled
        }
        let commit = refresh()
        // 引擎不接的键（比如没在组字时的个别符号）原样上屏。
        if !handled && !isComposing { return (commit ?? "") + letter }
        return commit
    }

    func backspace() -> Bool {
        guard isComposing, session != 0 else { return false }
        enclave_rime_process_key(session, Self.backspaceKey, 0)
        _ = refresh()
        return true
    }

    func select(_ index: Int) -> String? {
        guard session != 0, index >= 0 else { return nil }
        enclave_rime_select_candidate(session, index)
        return refresh()
    }

    func commitComposition() -> String? {
        guard session != 0 else { return nil }
        // 九宫格的原始输入是数字，回车时上屏拼写栏里的拼音。
        let raw = schema == RimeStore.nineKeySchemaID
            ? composition.filter { $0 != " " && $0 != "'" }
            : takeString(enclave_rime_get_input(session))
        enclave_rime_clear(session)
        _ = refresh()
        return raw
    }

    var rawInput: String {
        guard session != 0 else { return "" }
        return takeString(enclave_rime_get_input(session)) ?? ""
    }

    func replaceInput(_ raw: String) {
        guard session != 0 else { return }
        enclave_rime_clear(session)
        for scalar in raw.unicodeScalars {
            enclave_rime_process_key(session, Int32(scalar.value), 0)
        }
        _ = refresh()
    }

    func reset() {
        if session != 0 { enclave_rime_clear(session) }
        composition = ""
        candidates = []
    }

    /// 读出上屏文字、拼写和候选词。
    private func refresh() -> String? {
        let commit = takeString(enclave_rime_get_commit(session))
        composition = takeString(enclave_rime_get_preedit(session)) ?? ""
        if composition.isEmpty {
            candidates = []
        } else {
            var buffer = [UnsafeMutablePointer<CChar>?](repeating: nil, count: Self.candidateLimit)
            let count = enclave_rime_get_candidates(session, &buffer, Self.candidateLimit)
            candidates = (0..<count).compactMap { takeString(buffer[$0]) }
        }
        return commit
    }

    private func takeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
