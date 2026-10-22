import AVFoundation
import AVKit
import UIKit

/// 悬浮窗模式：用画中画小窗让 App 在后台保持运行，麦克风只在说话时打开。
///
/// 画中画的画面来自 AVSampleBufferDisplayLayer，内容是一张小状态卡（待命 / 录音中 / 识别中），
/// 状态变化时重新画一帧。用户可以把小窗推到屏幕边上藏起来；在后台关掉小窗就结束会话。
@MainActor
final class VoicePiP: NSObject {
    /// 用户在后台关掉了小窗。
    var onClosed: (() -> Void)?
    private(set) var isActive = false

    private let sourceView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var state: VoiceState = .ready
    private var refresh: Timer?

    /// 小窗画面的像素尺寸，决定小窗的长宽比。
    private let frameSize = CGSize(width: 540, height: 180)

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// 开始显示小窗。音频会话需要先激活，否则系统不允许画中画。
    func start() throws {
        guard Self.isSupported else { throw VoiceError.pipUnsupported }
        guard controller == nil else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { throw VoiceError.pipFailed("找不到窗口") }

        // 画中画要求图层在窗口里，用一个 1pt 的视图挂着。
        displayLayer.frame = sourceView.bounds
        displayLayer.videoGravity = .resizeAspect
        sourceView.layer.addSublayer(displayLayer)
        sourceView.isUserInteractionEnabled = false
        window.addSubview(sourceView)
        render()

        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
        isActive = true
        // 一旦可以开启就立刻开，用户返回别的 App 时小窗已经在了。
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { pip, _ in
            guard pip.isPictureInPicturePossible, !pip.isPictureInPictureActive else { return }
            Task { @MainActor in pip.startPictureInPicture() }
        }
        // 有的系统版本长时间不来新帧会把小窗画面当成卡住，定时补一帧。
        refresh = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        refresh?.invalidate()
        refresh = nil
        possibleObservation = nil
        controller?.stopPictureInPicture()
        controller = nil
        displayLayer.flushAndRemoveImage()
        sourceView.removeFromSuperview()
    }

    func update(_ state: VoiceState) {
        self.state = state
        if isActive { render() }
    }

    // MARK: - 画面

    private func render() {
        guard let buffer = makeSampleBuffer() else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(buffer)
    }

    private var title: String {
        switch state {
        case .idle: return "已结束"
        case .ready: return "Enclave 待命"
        case .recording: return "正在听…"
        case .transcribing: return "识别中…"
        }
    }

    private var tint: UIColor {
        switch state {
        case .recording: return .systemRed
        case .transcribing: return .systemOrange
        default: return .systemBlue
        }
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: frameSize, format: format).image { context in
            UIColor(white: 0.1, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: frameSize))
            let dot = CGRect(x: 40, y: frameSize.height / 2 - 22, width: 44, height: 44)
            tint.setFill()
            UIBezierPath(ovalIn: dot).fill()
            let symbol = state == .recording ? "waveform" : "mic.fill"
            if let icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                icon.draw(in: CGRect(x: dot.midX - icon.size.width / 2, y: dot.midY - icon.size.height / 2,
                                     width: icon.size.width, height: icon.size.height))
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let text = NSAttributedString(string: title, attributes: attributes)
            let size = text.size()
            text.draw(at: CGPoint(x: dot.maxX + 28, y: (frameSize.height - size.height) / 2))
        }
    }

    private func makeSampleBuffer() -> CMSampleBuffer? {
        guard let cgImage = makeImage().cgImage else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(frameSize.width), Int(frameSize.height),
                                  kCVPixelFormatType_32BGRA, attributes, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                   width: Int(frameSize.width), height: Int(frameSize.height), bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(cgImage, in: CGRect(origin: .zero, size: frameSize))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription, sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        if let sampleBuffer, let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}

// MARK: - 画中画回调

extension VoicePiP: AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    /// 小窗不是视频：没有暂停、没有进度，一直当作直播。
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            // 回到 App 时小窗会自动收起，这不算关掉；在后台点了小窗的关闭才结束会话。
            guard self.isActive, UIApplication.shared.applicationState != .active else { return }
            self.onClosed?()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in VoiceBridge.errorMessage = "悬浮窗没能打开：\(error.localizedDescription)" }
    }
}
