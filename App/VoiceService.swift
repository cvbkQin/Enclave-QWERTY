import AVFoundation
import Speech
import SwiftUI

/// 把音频线程的数据转给当前的识别器。
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var target: Transcriber?

    func set(_ transcriber: Transcriber?) {
        lock.lock(); target = transcriber; lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let current = target; lock.unlock()
        current?.append(buffer)
    }
}

/// 主 App 里的麦克风会话。
///
/// iOS 不允许键盘扩展录音，也不允许 App 在后台重新打开麦克风，所以做法是：
/// 用户从键盘跳到 App 时开启会话，音频引擎一直运行（后台音频模式让 App 保持活着），
/// 平时丢弃数据，键盘发来「开始」时才把数据交给识别器。
@MainActor
final class VoiceService: ObservableObject {
    static let shared = VoiceService()

    @Published private(set) var state: VoiceState = .idle
    @Published private(set) var lastText = ""
    @Published private(set) var partialText = ""
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var transcriber: Transcriber?
    private var observers: [DarwinObserver] = []
    private var heartbeat: Timer?
    private var lastActivity = Date()
    private var recordingStartedAt: Date?
    private var recordingMode: VoiceMode = .content
    private var lastPartialPost = Date.distantPast

    /// 单次录音最长 10 分钟。
    private let maxRecordingSeconds: TimeInterval = 600

    private init() {
        observers = [
            DarwinObserver(VoiceBridge.startNote) { [weak self] in self?.startRecording(mode: VoiceBridge.mode) },
            DarwinObserver(VoiceBridge.stopNote) { [weak self] in self?.stopRecording() },
            DarwinObserver(VoiceBridge.cancelNote) { [weak self] in self?.cancelRecording() },
        ]
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // 来电等打断会让音频引擎停下，会话随之结束，下次再从键盘跳转开启。
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.endSession() }
        }
        // 上次 App 被系统结束时可能留下旧状态。
        VoiceBridge.state = .idle
    }

    var settings: EnclaveSettings { SettingsStore.load() }

    // MARK: - 会话

    func startSession() async {
        errorMessage = nil
        guard state == .idle else { return }
        do {
            try await requestPermissions()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [sink] buffer, _ in
                sink.append(buffer)
            }
            engine.prepare()
            try engine.start()

            lastActivity = Date()
            setState(.ready)
            heartbeat?.invalidate()
            heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            tick()
        } catch {
            fail(error)
            endSession()
        }
    }

    func endSession() {
        cancelRecording()
        heartbeat?.invalidate()
        heartbeat = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        setState(.idle)
    }

    private func tick() {
        VoiceBridge.beat()
        let minutes = settings.voiceSessionMinutes
        if state == .ready, minutes > 0, Date().timeIntervalSince(lastActivity) > Double(minutes) * 60 {
            endSession()
        }
        if state == .recording, let start = recordingStartedAt, Date().timeIntervalSince(start) > maxRecordingSeconds {
            stopRecording()
        }
    }

    // MARK: - 录音

    func startRecording(mode: VoiceMode) {
        guard state == .ready else { return }
        errorMessage = nil
        VoiceBridge.errorMessage = nil
        let settings = self.settings
        do {
            let next: Transcriber
            switch settings.asrProvider {
            case .apple:
                let apple = try AppleTranscriber(allowServer: settings.allowAppleServerASR)
                apple.onPartial = { [weak self] text in
                    Task { @MainActor in self?.updatePartial(text) }
                }
                next = apple
            case .custom:
                next = try RemoteTranscriber(settings: settings, apiKey: SettingsStore.asrApiKey,
                                             inputFormat: engine.inputNode.outputFormat(forBus: 0))
            }
            transcriber = next
            updatePartial("", force: true)
            sink.set(next)
            recordingMode = mode
            recordingStartedAt = Date()
            lastActivity = Date()
            setState(.recording)
        } catch {
            fail(error)
        }
    }

    func stopRecording() {
        guard state == .recording, let current = transcriber else { return }
        sink.set(nil)
        transcriber = nil
        recordingStartedAt = nil
        setState(.transcribing)
        let mode = recordingMode
        Task {
            do {
                let text = try await current.finish()
                lastText = text
                VoiceBridge.publish(VoiceResult(id: UUID(), text: text, mode: mode))
            } catch {
                fail(error)
            }
            lastActivity = Date()
            if state == .transcribing { setState(.ready) }
        }
    }

    func cancelRecording() {
        guard let current = transcriber else { return }
        sink.set(nil)
        transcriber = nil
        recordingStartedAt = nil
        current.cancel()
        if state == .recording || state == .transcribing { setState(.ready) }
    }

    // MARK: - 辅助

    /// 实时文字最多每 0.3 秒同步给键盘一次。
    private func updatePartial(_ text: String, force: Bool = false) {
        partialText = text
        guard force || Date().timeIntervalSince(lastPartialPost) > 0.3 else { return }
        lastPartialPost = Date()
        VoiceBridge.partialText = text
        VoiceBridge.post(VoiceBridge.updatedNote)
    }

    private func requestPermissions() async throws {
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard micGranted else { throw VoiceError.microphoneDenied }

        if settings.asrProvider == .apple {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { throw VoiceError.speechDenied }
        }
    }

    private func setState(_ newState: VoiceState) {
        state = newState
        VoiceBridge.state = newState
        VoiceBridge.beat()
        VoiceBridge.post(VoiceBridge.updatedNote)
    }

    private func fail(_ error: Error) {
        if error is CancellationError { return }
        let message = error.localizedDescription
        errorMessage = message
        VoiceBridge.errorMessage = message
        VoiceBridge.post(VoiceBridge.updatedNote)
    }
}
