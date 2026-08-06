import Foundation
import PrismKit
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

/// Capture mono linear16 PCM @ 16 kHz for live Flux STT WebSocket.
@MainActor
final class LivePCMCapture: ObservableObject {
  @Published private(set) var isCapturing = false
  @Published private(set) var errorMessage: String?

  /// Called on a background queue with Int16 little-endian mono PCM frames.
  var onPCM: ((Data) -> Void)?

  #if canImport(AVFoundation) && os(iOS)
  private let engine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private let targetFormat: AVAudioFormat = {
    AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
  }()

  var hasPermission: Bool {
    AVAudioSession.sharedInstance().recordPermission == .granted
  }

  func requestPermission() async -> Bool {
    await withCheckedContinuation { cont in
      AVAudioSession.sharedInstance().requestRecordPermission { ok in
        cont.resume(returning: ok)
      }
    }
  }

  func start() throws {
    errorMessage = nil
    guard !isCapturing else { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setActive(true)

    let input = engine.inputNode
    let hw = input.outputFormat(forBus: 0)
    guard hw.sampleRate > 0, hw.channelCount > 0 else {
      throw PrismError.transport("No microphone input available.")
    }
    converter = AVAudioConverter(from: hw, to: targetFormat)
    input.removeTap(onBus: 0)
    let bufferSize: AVAudioFrameCount = 1024
    input.installTap(onBus: 0, bufferSize: bufferSize, format: hw) { [weak self] buffer, _ in
      guard let self else { return }
      self.convertAndEmit(buffer)
    }
    engine.prepare()
    try engine.start()
    isCapturing = true
  }

  func stop() {
    guard isCapturing else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    converter = nil
    isCapturing = false
  }

  private nonisolated func convertAndEmit(_ buffer: AVAudioPCMBuffer) {
    Task { @MainActor in
      guard let converter = self.converter else { return }
      let ratio = self.targetFormat.sampleRate / buffer.format.sampleRate
      let outCapacity = max(AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32, 1)
      guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outCapacity) else { return }
      var error: NSError?
      var consumed = false
      let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        if consumed {
          outStatus.pointee = .noDataNow
          return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
      }
      converter.convert(to: out, error: &error, withInputFrom: inputBlock)
      if let error {
        self.errorMessage = error.localizedDescription
        return
      }
      guard out.frameLength > 0, let channels = out.int16ChannelData else { return }
      let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
      let data = Data(bytes: channels[0], count: byteCount)
      self.onPCM?(data)
    }
  }
  #else
  var hasPermission: Bool { false }
  func requestPermission() async -> Bool { false }
  func start() throws { throw PrismError.transport("Live mic requires iOS.") }
  func stop() {}
  #endif
}
