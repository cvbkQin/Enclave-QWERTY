import Foundation

/// RIME 拼音引擎（雾凇拼音）。词库由主 App 部署到共享目录，这里只加载。
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
    func prepare(schema wanted: String) -> Bool {
        guard prepare() else { return false }
        if wanted != schema {
            reset()
            guard enclave_rime_select_schema(session, wanted) else { return false }
            enclave_rime_set_option(session, "ascii_mode", false)
            schema = wanted
        }
        return true
    }

    private func prepare() -> Bool {
        guard RimeStore.isDeployed, let version = RimeStore.deployedVersion, let paths = RimeStore.paths else {
            return false
        }
        if loadedVersion != version {
            // App 重新部署过：重新加载新词库。
            if loadedVersion != nil {
                enclave_rime_finalize()
                session = 0
            }
            guard enclave_rime_start(paths.shared.path, paths.user.path, nil) else { return false }
            loadedVersion = version
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
