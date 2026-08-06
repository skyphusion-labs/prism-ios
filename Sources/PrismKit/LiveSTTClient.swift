import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live mic STT via plane `GET /v1/stt/stream` (Deepgram Flux, linear16 @ 16 kHz).
///
/// Native clients authenticate with `Authorization: Bearer pcp_…` on the upgrade
/// (never put the long-lived key in `Sec-WebSocket-Protocol`).
@available(iOS 15.0, macOS 12.0, *)
public actor LiveSTTClient {
  public enum Event: Sendable, Equatable {
    case partial(String)
    case final(String)
    case raw(String)
    case closed(String?)
    case failed(String)
  }

  private var task: URLSessionWebSocketTask?
  private var session: URLSession?
  private var listenTask: Task<Void, Never>?

  public init() {}

  /// Connect and start receiving transcript events. Caller sends PCM via `sendPCM`.
  public func connect(streamURL: URL, bearerKey: String) async throws {
    await disconnect()
    var req = URLRequest(url: streamURL)
    req.setValue("Bearer \(bearerKey)", forHTTPHeaderField: "Authorization")
    let session = URLSession(configuration: .default)
    self.session = session
    let task = session.webSocketTask(with: req)
    self.task = task
    task.resume()
  }

  public func sendPCM(_ data: Data) async throws {
    guard let task else {
      throw PrismError.transport("Live STT not connected")
    }
    try await task.send(.data(data))
  }

  public func sendText(_ text: String) async throws {
    guard let task else {
      throw PrismError.transport("Live STT not connected")
    }
    try await task.send(.string(text))
  }

  /// Async stream of transcript events until the socket closes.
  public func events() -> AsyncStream<Event> {
    AsyncStream { continuation in
      listenTask?.cancel()
      listenTask = Task {
        guard let task = self.task else {
          continuation.yield(.failed("not connected"))
          continuation.finish()
          return
        }
        while !Task.isCancelled {
          do {
            let message = try await task.receive()
            switch message {
            case .string(let s):
              for ev in Self.parseDeepgram(s) {
                continuation.yield(ev)
              }
            case .data(let d):
              if let s = String(data: d, encoding: .utf8) {
                for ev in Self.parseDeepgram(s) {
                  continuation.yield(ev)
                }
              }
            @unknown default:
              break
            }
          } catch {
            continuation.yield(.closed(error.localizedDescription))
            continuation.finish()
            return
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        Task { await self.disconnect() }
      }
    }
  }

  public func disconnect() async {
    listenTask?.cancel()
    listenTask = nil
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    session?.invalidateAndCancel()
    session = nil
  }

  /// Parse Deepgram Flux-style JSON for transcript text.
  public static func parseDeepgram(_ json: String) -> [Event] {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [.raw(json)]
    }
    // Common shapes: {type, transcript}, {channel:{alternatives:[{transcript}]}}, is_final / EndOfTurn
    var text: String?
    if let t = obj["transcript"] as? String { text = t }
    if text == nil, let channel = obj["channel"] as? [String: Any],
       let alts = channel["alternatives"] as? [[String: Any]],
       let t = alts.first?["transcript"] as? String
    {
      text = t
    }
    if text == nil, let r = obj["result"] as? [String: Any],
       let t = r["transcript"] as? String
    {
      text = t
    }
    let type = (obj["type"] as? String) ?? ""
    let isFinal =
      (obj["is_final"] as? Bool) == true
      || type.localizedCaseInsensitiveContains("EndOfTurn")
      || type.localizedCaseInsensitiveContains("final")
    if let text, !text.isEmpty {
      return [isFinal ? .final(text) : .partial(text)]
    }
    if type.localizedCaseInsensitiveContains("EndOfTurn") {
      return [.final("")]
    }
    return [.raw(json)]
  }
}
