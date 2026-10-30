#if DEBUG
import Foundation

/// 纠错测试（0.94）：用 App 部署好的词库，把 Tests/Correction/eval_inputs.json 里的输入一个个喂给引擎，记下前几个候选。
/// 启动参数 -rimeEval：输入文件先放进 App 的 Documents/rime-eval-inputs.json（scripts/correction/run-eval.sh 会放），
/// 结果写到 Documents/rime-eval.json，写完再放一个 rime-eval.done。
/// 用临时的用户目录（链接到已编译的词库和整句模型），不读也不改用户词库，学到的词频不影响结果。
enum RimeEval {
    static let candidatesPerInput = 5

    static func runWhenDeployed() {
        Task.detached(priority: .userInitiated) {
            // 等 App 启动时的部署做完，最多 10 分钟。
            for _ in 0..<1200 {
                let ready = await MainActor.run { !RimeDeployer.shared.needsDeploy && RimeDeployer.shared.state != .deploying }
                if ready { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            run()
        }
    }

    private struct Layout: Decodable {
        let schema: String
        let cases: [[String]]
        let prefixes: [String]
    }

    private static func run() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first, let paths = RimeStore.paths else { return }
        let done = docs.appendingPathComponent("rime-eval.done")
        try? fm.removeItem(at: done)
        guard let data = try? Data(contentsOf: docs.appendingPathComponent("rime-eval-inputs.json")),
              let layouts = try? JSONDecoder().decode([String: Layout].self, from: data) else {
            try? "no inputs".write(to: done, atomically: true, encoding: .utf8)
            return
        }

        // 临时用户目录：build 和整句模型链接过去，别的（用户词库、常用词短语表）都不带。
        let user = fm.temporaryDirectory.appendingPathComponent("rime-eval-user", isDirectory: true)
        try? fm.removeItem(at: user)
        try? fm.createDirectory(at: user, withIntermediateDirectories: true)
        let linked = ((try? fm.contentsOfDirectory(atPath: paths.user.path)) ?? []).filter { $0 == "build" || $0.hasSuffix(".gram") }
        for name in linked {
            try? fm.createSymbolicLink(at: user.appendingPathComponent(name), withDestinationURL: paths.user.appendingPathComponent(name).resolvingSymlinksInPath())
        }

        let started = Date()
        enclave_rime_finalize()
        _ = enclave_rime_start(paths.shared.path, user.path, nil)
        var results: [String: [String: [String]]] = [:]
        for (name, layout) in layouts {
            let session = enclave_rime_create_session(layout.schema)
            guard session != 0 else { continue }
            enclave_rime_set_option(session, "ascii_mode", false)
            var out: [String: [String]] = [:]
            let inputs = Set(layout.cases.compactMap { $0.last } + layout.prefixes)
            for input in inputs.sorted() {
                enclave_rime_clear(session)
                for scalar in input.unicodeScalars {
                    enclave_rime_process_key(session, Int32(scalar.value), 0)
                }
                var buffer = [UnsafeMutablePointer<CChar>?](repeating: nil, count: candidatesPerInput)
                let count = enclave_rime_get_candidates(session, &buffer, candidatesPerInput)
                out[input] = (0..<count).compactMap { index in
                    guard let pointer = buffer[index] else { return nil }
                    defer { free(pointer) }
                    return String(cString: pointer)
                }
            }
            enclave_rime_destroy_session(session)
            results[name] = out
        }
        enclave_rime_finalize()

        let report: [String: Any] = [
            "deployedVersion": RimeStore.deployedVersion ?? "",
            "grammar": linked.contains { $0.hasSuffix(".gram") },
            "app": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "",
            "seconds": Date().timeIntervalSince(started),
            "results": results,
        ]
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? json.write(to: docs.appendingPathComponent("rime-eval.json"))
        }
        try? "ok".write(to: done, atomically: true, encoding: .utf8)
    }
}
#endif
