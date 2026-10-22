import Foundation

/// 键盘扩展拿不到麦克风，录音由主 App 在后台完成。
/// 两边通过 App Group 里的 UserDefaults 交换状态，用 Darwin 通知互相提醒。
enum VoiceState: String, Codable {
    /// 没有麦克风会话。
    case idle
    /// 会话已开启，随时可以开始录音。
    case ready
    case recording
    case transcribing
}

enum VoiceMode: String, Codable {
    /// 说的是内容：识别结果填进输入框。
    case content
    /// 说的是修改要求：相当于在输入框末尾打「// 要求」。
    case instruction
}

struct VoiceResult: Codable, Equatable {
    var id: UUID
    var text: String
    var mode: VoiceMode
}

enum VoiceBridge {
    private static let prefix = (SharedStorage.appGroupID ?? "enclave") + ".voice"

    /// 键盘 → App
    static let startNote = prefix + ".start"
    static let stopNote = prefix + ".stop"
    static let cancelNote = prefix + ".cancel"
    /// App → 键盘：状态或结果有变化。
    static let updatedNote = prefix + ".updated"

    private static let stateKey = "voice.state"
    private static let heartbeatKey = "voice.heartbeat"
    private static let modeKey = "voice.mode"
    private static let resultKey = "voice.result"
    private static let consumedKey = "voice.consumedResultID"
    private static let errorKey = "voice.error"

    private static var defaults: UserDefaults { SharedStorage.defaults }

    // MARK: - 状态

    static var state: VoiceState {
        get { defaults.string(forKey: stateKey).flatMap(VoiceState.init(rawValue:)) ?? .idle }
        set { defaults.set(newValue.rawValue, forKey: stateKey) }
    }

    /// 键盘请求的录音模式。
    static var mode: VoiceMode {
        get { defaults.string(forKey: modeKey).flatMap(VoiceMode.init(rawValue:)) ?? .content }
        set { defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    static var errorMessage: String? {
        get { defaults.string(forKey: errorKey) }
        set { defaults.set(newValue, forKey: errorKey) }
    }

    static func beat() {
        defaults.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
    }

    /// App 每秒写一次心跳；超过 3 秒没更新说明 App 已经被系统结束。
    static var isSessionAlive: Bool {
        let last = defaults.double(forKey: heartbeatKey)
        return state != .idle && Date().timeIntervalSince1970 - last < 3
    }

    /// 键盘看到的有效状态：App 没在跑就当作没有会话。
    static var effectiveState: VoiceState { isSessionAlive ? state : .idle }

    // MARK: - 结果

    static func publish(_ result: VoiceResult) {
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: resultKey)
        }
    }

    /// 取出还没被键盘处理过的识别结果，取出即标记为已处理。
    static func takePendingResult() -> VoiceResult? {
        guard let data = defaults.data(forKey: resultKey),
              let result = try? JSONDecoder().decode(VoiceResult.self, from: data),
              defaults.string(forKey: consumedKey) != result.id.uuidString
        else { return nil }
        defaults.set(result.id.uuidString, forKey: consumedKey)
        return result
    }

    // MARK: - Darwin 通知

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// 监听一个 Darwin 通知，回调在主线程执行；对象释放时自动取消监听。
final class DarwinObserver {
    private let handler: () -> Void

    init(_ name: String, handler: @escaping () -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.handler() }
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }
}
