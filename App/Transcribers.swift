import AVFoundation
import Foundation
import Speech

enum VoiceError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case notConfigured
    case badURL(String)
    case http(Int, String)
    case empty
    case recognition(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "没有麦克风权限，请到 设置 › Enclave 里打开麦克风。"
        case .speechDenied: return "没有语音识别权限，请到 设置 › Enclave 里打开语音识别。"
        case .recognizerUnavailable: return "苹果语音识别暂时不可用。请检查 设置 › 通用 › 键盘 里的「启用听写」是否打开。"
        case .onDeviceUnavailable: return "这台设备不支持中文离线识别。可以在设置里允许使用苹果服务器，或改用自定义接口。"
        case .notConfigured: return "还没有填写语音识别接口地址。"
        case .badURL(let url): return "语音识别接口地址不正确：\(url)"
        case .http(let code, let body): return "语音识别失败（HTTP \(code)）：\(body)"
        case .empty: return "没有识别到内容。如果一直这样，请检查 设置 › 通用 › 键盘 里的「启用听写」是否打开。"
        case .recognition(let detail): return "识别失败：\(detail)。请检查 设置 › 通用 › 键盘 里的「启用听写」是否打开。"
        }
    }
}

/// 一次录音的识别器。`append` 在音频线程调用。
protocol Transcriber: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel()
}

// MARK: - 苹果语音识别

final class AppleTranscriber: Transcriber {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    private let lock = NSLock()
    private var latest = ""
    private var lastError: Error?
    /// 中间结果回调，在识别器的线程调用。
    var onPartial: ((String) -> Void)?
    private var outcome: Result<String, Error>?
    private var continuation: CheckedContinuation<String, Error>?

    init(allowServer: Bool) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition || allowServer else {
            throw VoiceError.onDeviceUnavailable
        }
        self.recognizer = recognizer
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() async throws -> String {
        request.endAudio()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome)
                return
            }
            self.continuation = continuation
            lock.unlock()
            // 兜底：识别器迟迟不给最终结果时，用最后一次中间结果。
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.complete(with: nil)
            }
        }
    }

    func cancel() {
        task?.cancel()
        complete(with: .failure(CancellationError()))
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            lock.lock()
            latest = text
            lock.unlock()
            onPartial?(text)
            if result.isFinal { complete(with: nil) }
        } else if let error {
            lock.lock()
            lastError = error
            lock.unlock()
            complete(with: nil)
        }
    }

    /// nil 表示用目前识别到的文字作为结果。
    private func complete(with forced: Result<String, Error>?) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyError: Error = lastError.map { VoiceError.recognition($0.localizedDescription) } ?? VoiceError.empty
        let final = forced ?? (text.isEmpty ? .failure(emptyError) : .success(text))
        outcome = final
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: final)
    }
}

// MARK: - 自定义接口（OpenAI 兼容 /audio/transcriptions）

final class RemoteTranscriber: Transcriber {
    private let settings: EnclaveSettings
    private let apiKey: String?
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let fileURL: URL
    private var file: AVAudioFile?
    private let lock = NSLock()

    init(settings: EnclaveSettings, apiKey: String?, inputFormat: AVAudioFormat) throws {
        guard !settings.asrBaseURL.trimmingCharacters(in: .whitespaces).isEmpty else { throw VoiceError.notConfigured }
        // 16kHz 单声道 16 位，语音识别够用，文件也小。
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: format)
        else { throw VoiceError.recognizerUnavailable }
        self.settings = settings
        self.apiKey = apiKey
        self.outputFormat = format
        self.converter = converter
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
        file = try AVAudioFile(forWriting: fileURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return }
        lock.lock()
        try? file?.write(from: output)
        lock.unlock()
    }

    func finish() async throws -> String {
        lock.lock()
        file = nil  // 释放即写完文件头
        lock.unlock()

        var base = settings.asrBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/audio/transcriptions") ? base : base + "/audio/transcriptions"
        guard let url = URL(string: full), url.host != nil else { throw VoiceError.badURL(settings.asrBaseURL) }

        let boundary = "enclave-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", settings.asrModel.trimmingCharacters(in: .whitespaces))
        field("response_format", "json")
        field("language", "zh")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: fileURL))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VoiceError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        struct Reply: Decodable { var text: String }
        let text = try JSONDecoder().decode(Reply.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw VoiceError.empty }
        return text
    }

    func cancel() {
        lock.lock()
        file = nil
        lock.unlock()
    }
}
