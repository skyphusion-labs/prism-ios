import Foundation

/// Minimal Server-Sent Events parser for `POST /api/chat/stream`.
///
/// Frames are `data: {json}\n\n`. Playground emits:
/// - `{ "type": "delta", "text": "..." }`
/// - `{ "type": "done", ...ChatResponse fields }`
/// - `{ "type": "error", "message": "..." }`
public enum SSEParser {
  public static func parseChatEvents(from text: String) -> [ChatStreamEvent] {
    var events: [ChatStreamEvent] = []
    var dataLines: [String] = []

    func flush() {
      guard !dataLines.isEmpty else { return }
      let payload = dataLines.joined(separator: "\n")
      dataLines.removeAll(keepingCapacity: true)
      guard !payload.isEmpty, payload != "[DONE]" else { return }
      guard let data = payload.data(using: .utf8) else {
        events.append(.unknown(payload))
        return
      }
      events.append(decodeChatEvent(data: data, raw: payload))
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let s = String(line)
      if s.isEmpty {
        flush()
        continue
      }
      if s.hasPrefix(":") { continue } // comment
      if s.hasPrefix("data:") {
        var rest = String(s.dropFirst(5))
        if rest.hasPrefix(" ") { rest = String(rest.dropFirst()) }
        dataLines.append(rest)
      }
      // event:/id: fields ignored for chat
    }
    flush()
    return events
  }

  private static func decodeChatEvent(data: Data, raw: String) -> ChatStreamEvent {
    struct Envelope: Decodable {
      let type: String?
      let text: String?
      let message: String?
      let output: String?
      let conversation_id: String?
      let model: String?
      let tokens_in: Int?
      let tokens_out: Int?
      let error: String?
    }
    guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
      return .unknown(raw)
    }
    switch env.type {
    case "delta":
      return .delta(env.text ?? "")
    case "done":
      return .done(
        ChatResponse(
          output: env.output ?? env.text,
          conversation_id: env.conversation_id,
          model: env.model,
          tokens_in: env.tokens_in,
          tokens_out: env.tokens_out,
          usage: nil,
          error: env.error
        )
      )
    case "error":
      return .error(env.message ?? env.error ?? raw)
    default:
      return .unknown(raw)
    }
  }
}
