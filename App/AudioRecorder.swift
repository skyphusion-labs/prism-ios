import Foundation
import PrismKit
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

/// Simple m4a recorder for STT (Whisper-friendly).
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var elapsedSeconds: Int = 0

  #if canImport(AVFoundation) && os(iOS)
  private var recorder: AVAudioRecorder?
  private var timer: Timer?
  private var fileURL: URL?

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
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("prism-stt-\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    let rec = try AVAudioRecorder(url: url, settings: settings)
    rec.isMeteringEnabled = true
    guard rec.record() else {
      throw PrismError.transport("Could not start microphone recording.")
    }
    recorder = rec
    fileURL = url
    isRecording = true
    elapsedSeconds = 0
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.elapsedSeconds += 1
      }
    }
  }

  /// Stops and returns recorded data (m4a).
  func stop() -> (data: Data, url: URL)? {
    timer?.invalidate()
    timer = nil
    recorder?.stop()
    isRecording = false
    defer { recorder = nil }
    guard let url = fileURL, let data = try? Data(contentsOf: url), !data.isEmpty else {
      errorMessage = "No audio captured."
      return nil
    }
    return (data, url)
  }

  func cancel() {
    timer?.invalidate()
    timer = nil
    recorder?.stop()
    if let url = fileURL {
      try? FileManager.default.removeItem(at: url)
    }
    recorder = nil
    fileURL = nil
    isRecording = false
    elapsedSeconds = 0
  }
  #else
  var hasPermission: Bool { false }
  func requestPermission() async -> Bool { false }
  func start() throws { throw PrismError.transport("Recording requires iOS.") }
  func stop() -> (data: Data, url: URL)? { nil }
  func cancel() {}
  #endif
}
