#if DEBUG
import Foundation

/// 上机验证「不开完全访问也能打拼音」：记下这时键盘能读写哪些地方、词库从哪加载、内存占用。
/// 结果先写进扩展自己的容器；开了完全访问后再复制到共享目录 Diagnostics/，用 devicectl 取出来看。
enum KeyboardProbe {
    private static var done: Set<Bool> = []

    static func run(fullAccess: Bool, pinyinReady: Bool, source: String?) {
        guard !done.contains(fullAccess) else { return }
        done.insert(fullAccess)
        let fm = FileManager.default
        var report: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "fullAccess": fullAccess,
            "pinyinReady": pinyinReady,
            "rimeSource": source ?? "none",
            "physFootprintMB": footprintMB(),
        ]
        let group = SharedStorage.appGroupID.flatMap { fm.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        report["groupContainerURL"] = group?.path ?? "nil"
        if let group {
            report["groupListable"] = (try? fm.contentsOfDirectory(atPath: group.path)) != nil
            report["groupWritable"] = canWrite(group.appendingPathComponent("probe-write.tmp"))
        }
        if let id = SharedStorage.appGroupID {
            report["groupDefaultsDeployedVersion"] = UserDefaults(suiteName: id)?.string(forKey: "rime.deployedVersion") ?? "nil"
        }
        let own = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        report["ownContainer"] = own?.path ?? "nil"
        if let own {
            try? fm.createDirectory(at: own, withIntermediateDirectories: true)
            report["ownWritable"] = canWrite(own.appendingPathComponent("probe-write.tmp"))
            let rimeUser = own.appendingPathComponent("Rime")
            report["rimeUserFiles"] = (try? fm.contentsOfDirectory(atPath: rimeUser.path)) ?? []
        }
        let name = fullAccess ? "probe-on.json" : "probe-off.json"
        if let own, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: own.appendingPathComponent(name))
        }
        // 开了完全访问：把两份结果都复制到共享目录。
        if fullAccess, let own, let group {
            let out = group.appendingPathComponent("Diagnostics", isDirectory: true)
            try? fm.createDirectory(at: out, withIntermediateDirectories: true)
            for file in ["probe-off.json", "probe-on.json"] {
                let from = own.appendingPathComponent(file), to = out.appendingPathComponent(file)
                guard fm.fileExists(atPath: from.path) else { continue }
                try? fm.removeItem(at: to)
                try? fm.copyItem(at: from, to: to)
            }
        }
    }

    private static func canWrite(_ url: URL) -> Bool {
        do {
            try Data("ok".utf8).write(to: url)
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
#endif
