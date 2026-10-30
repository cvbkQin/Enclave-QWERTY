import Foundation

/// RIME 拼音引擎（词库来自万象拼音）。词库由主 App 部署到共享目录，这里只加载。
/// 不是线程安全的：键盘里只通过 QueuedEngine 在它的串行队列上调用。
final class RimeEngine: InputEngine {
    static let shared = RimeEngine()

    private(set) var composition = ""
    private(set) var candidates: [String] = []
    private(set) var selections: [InputSelection] = []
    /// 分段选词后接着整句的剩下部分（见 select），排在候选第一个；Rime 自己的候选从 candidates[hintOffset] 开始。
    private var remainder: String?
    private var hintOffset: Int { remainder == nil ? 0 : 1 }
    private var session: UInt64 = 0
    private var loadedVersion: String?
    private var schema = RimeStore.schemaID

    /// 每次按键只取够候选栏第一屏的数量，取得越多 Rime 要往后查得越深；滑到头或展开整页时再补到 candidateLimit。
    static let firstPage = 30
    static let candidateLimit = 150
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
            warmUp()
        }
        return true
    }

    /// 有没有能加载的词库（只看文件，不启动引擎），用来在引擎准备好之前先决定用不用拼音。
    static func hasDictionary(useShared: Bool) -> Bool {
        (useShared && RimeStore.isDeployed) || RimeStore.bundled != nil
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
            // 马上重建，免得下一个按键等它。
            _ = prepare()
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
            // 内测包自带整句模型：App 升级后包路径变了，先把用户目录里的链接指回来。
            if version.hasPrefix("shared:") { GrammarModel.linkBundled() }
            guard enclave_rime_start(paths.shared.path, paths.user.path, nil) else { return false }
            loadedVersion = version
            source = version
        }
        if !enclave_rime_session_alive(session) {
            session = enclave_rime_create_session(schema)
            guard session != 0 else { return false }
            enclave_rime_set_option(session, "ascii_mode", false)
            warmUp()
        }
        return true
    }

    /// 按键时用：词库换没换在每次弹出时（prepare(schema:)）已经查过，这里只看会话还在不在，
    /// 不再每个键都读共享存储、查方案文件在不在。
    private func ensureSession() -> Bool {
        if loadedVersion != nil, session != 0, enclave_rime_session_alive(session) { return true }
        return prepare()
    }

    /// 新会话先拼一个字母再清掉：词典和方案在这时读进内存，用户的第一个键就不用等。
    private func warmUp() {
        enclave_rime_process_key(session, 0x6e, 0) // n
        enclave_rime_process_key(session, 0x69, 0) // i
        var buffer = [UnsafeMutablePointer<CChar>?](repeating: nil, count: Self.firstPage)
        let count = enclave_rime_get_candidates(session, &buffer, Self.firstPage)
        for index in 0..<count { free(buffer[index]) }
        enclave_rime_clear(session)
    }

    func input(_ letter: String) -> String? {
        remainder = nil
        guard ensureSession() else { return letter }
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
        remainder = nil
        // 分段选过词时，Rime 的删除先把最后选的词退回成拼音。
        enclave_rime_process_key(session, Self.backspaceKey, 0)
        _ = refresh()
        return true
    }

    /// 选了首选整句的开头一段（「天道酬勤」里选「天道」）时，Rime 会把剩下的输入当成新的一段重新组词，和前文无关；
    /// 这时把整句剩下的「酬勤」放在候选第一个，选它就照原来的整句上屏。
    func select(_ index: Int) -> String? {
        guard session != 0, index >= 0 else { return nil }
        if remainder != nil && index == 0 { return selectRemainder() }
        let top = candidates.first
        let chosen = candidates.indices.contains(index) ? candidates[index] : nil
        let rimeIndex = index - hintOffset
        remainder = nil
        enclave_rime_select_candidate(session, rimeIndex)
        let commit = refresh()
        if commit == nil, !composition.isEmpty, let top, let chosen, !chosen.isEmpty, top.count > chosen.count, top.hasPrefix(chosen) {
            let rest = String(top.dropFirst(chosen.count))
            if candidates.first != rest {
                remainder = rest
                candidates.insert(rest, at: 0)
            }
        }
        return commit
    }

    /// 选「整句剩下的部分」：在 Rime 的候选里一段段选出同样的字（先挑最长的），学词、上屏都照常走 Rime。
    /// 中途找不到对应的字就停下，已经选到的留着，剩下的照常显示候选。
    private func selectRemainder() -> String? {
        guard var rest = remainder else { return nil }
        remainder = nil
        _ = refresh()
        var commit = ""
        while !rest.isEmpty && !composition.isEmpty {
            loadMoreCandidates()
            let match = candidates.enumerated()
                .filter { !$0.element.isEmpty && rest.hasPrefix($0.element) }
                .max { $0.element.count < $1.element.count }
            guard let match else { break }
            enclave_rime_select_candidate(session, match.offset)
            if let text = refresh() { commit += text }
            rest.removeFirst(match.element.count)
        }
        return commit.isEmpty ? nil : commit
    }

    func deleteCandidate(_ index: Int) -> Bool {
        guard session != 0, index >= hintOffset else { return false }
        let deleted = enclave_rime_delete_candidate(session, index - hintOffset)
        remainder = nil
        _ = refresh()
        return deleted
    }

    func commitComposition() -> String? {
        guard session != 0 else { return nil }
        // 九宫格的原始输入是数字，回车时上屏拼写栏里的拼音。
        let raw = schema == RimeStore.nineKeySchemaID
            ? composition.filter { $0 != " " && $0 != "'" }
            : takeString(enclave_rime_get_input(session))
        enclave_rime_clear(session)
        remainder = nil
        _ = refresh()
        return raw
    }

    var rawInput: String {
        guard session != 0 else { return "" }
        return takeString(enclave_rime_get_input(session)) ?? ""
    }

    func replaceInput(_ raw: String, keeping kept: [InputSelection]) {
        guard session != 0 else { return }
        remainder = nil
        enclave_rime_clear(session)
        for scalar in raw.unicodeScalars {
            enclave_rime_process_key(session, Int32(scalar.value), 0)
        }
        _ = refresh()
        // 把分段选过的词按原来的位置再选一遍：同样的字、选完停在原来的位置（后面多了分词符也算）。
        for selection in kept {
            loadMoreCandidates()
            guard let index = candidates.firstIndex(of: selection.text) else { break }
            enclave_rime_select_candidate(session, index)
            _ = refresh()
            guard let last = selections.last, last.text == selection.text, last.end >= selection.end else { break }
        }
    }

    /// 键盘收起时关掉会话：用户词库（LevelDB 的 *.userdb）在 App Group 里，开着就一直锁着 LOCK 文件，
    /// 扩展被挂起时还锁着共享容器里的文件，系统会直接杀掉（0xDEAD10CC），下次在别的 App 里弹出时可能等不到我们、换成系统键盘。
    /// 会话一关，librime 里最后一个引用放掉，用户词库随之关闭、解锁；下次弹出时 prepare 再建会话。
    func closeSession() {
        if session != 0 {
            enclave_rime_destroy_session(session)
            session = 0
        }
        composition = ""
        candidates = []
        selections = []
        remainder = nil
    }

    func reset() {
        if session != 0 { enclave_rime_clear(session) }
        composition = ""
        candidates = []
        selections = []
        remainder = nil
    }

    /// 读出上屏文字、拼写和候选词。
    private func refresh() -> String? {
        let commit = takeString(enclave_rime_get_commit(session))
        composition = takeString(enclave_rime_get_preedit(session)) ?? ""
        candidates = composition.isEmpty ? [] : fetchCandidates(from: 0, limit: Self.firstPage)
        selections = composition.isEmpty ? [] : readSelections()
        if let remainder { candidates.insert(remainder, at: 0) }
        return commit
    }

    /// 九宫格方案的 enclave_t9_state.lua 写的：每行「结束位置<Tab>文字」。全键盘方案没有，是空的。
    private func readSelections() -> [InputSelection] {
        guard let value = takeString(enclave_rime_get_property(session, "enclave_selected")) else { return [] }
        return value.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let end = Int(parts[0]) else { return nil }
            return InputSelection(end: end, text: String(parts[1]))
        }
    }

    /// 候选栏滑到头、展开整页时调用：在已经取到的后面接着取，一共到 candidateLimit 个。
    func loadMoreCandidates() {
        let loaded = candidates.count - hintOffset
        guard session != 0, !composition.isEmpty, loaded >= Self.firstPage, loaded < Self.candidateLimit else { return }
        candidates += fetchCandidates(from: loaded, limit: Self.candidateLimit - loaded)
    }

    private func fetchCandidates(from start: Int, limit: Int) -> [String] {
        var buffer = [UnsafeMutablePointer<CChar>?](repeating: nil, count: limit)
        let count = enclave_rime_get_candidates_from(session, &buffer, start, limit)
        return (0..<count).compactMap { takeString(buffer[$0]) }
    }

    private func takeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
