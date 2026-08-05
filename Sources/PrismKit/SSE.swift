import Foundation

/// Server-Sent Events parser for chat streams.
///
/// **Playground** (`POST /api/chat/stream`): frames like
/// `{ "type": "delta", "text": "..." }` / `done` / `error`.
///
/// **Control plane** (`stream: true` on `/v1/chat/completions`): OpenAI-compatible
/// frames `{"choices":[{"delta":{"content":"..."}}]}` ending with `data: [DONE]`.
public enum SSEParser {
  public static func parseChatEvents(from text: String) -> [ChatStreamEvent] {
    var events: [ChatStreamEvent] = []
    var dataLines: [String] = []

    func flush() {
      guard !dataLines.isEmpty else { return }
      let payload = dataLines.joined(separator: "\n")
      dataLines.removeAll(keepingCapacity: true)
      if payload.isEmpty { return }
      if payload == "[DONE]" {
        events.append(
          .done(
            ChatResponse(
              output: nil,
              conversation_id: nil,
              model: nil,
              tokens_in: nil,
              tokens_out: nil,
              usage: nil,
              error: nil
            )
          )
        )
        return
      }
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
    // Playground envelope
    struct PlaygroundEnvelope: Decodable {
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
    if let env = try? JSONDecoder().decode(PlaygroundEnvelope.self, from: data),
       let type = env.type {
      switch type {
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
        break
      }
    }

    // OpenAI / control-plane shape
    struct OpenAIChunk: Decodable {
      struct Choice: Decodable {
        struct Delta: Decodable {
          let content: String?
          let role: String?
        }
        struct Message: Decodable {
          let content: String?
          let role: String?
        }
        let delta: Delta?
        let message: Message?
        let finish_reason: String?
      }
      struct Err: Decodable {
        let message: String?
        let code: String?
      }
      let choices: [Choice]?
      let error: Err?
      let usage: ChatUsage?
    }

    if let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data) {
      if let err = chunk.error {
        return .error(err.message ?? err.code ?? raw)
      }
      if let choice = chunk.choices?.first {
        if let content = choice.delta?.content {
          return .delta(content)
        }
        if let content = choice.message?.content {
          return .done(
            ChatResponse(
              output: content,
              conversation_id: nil,
              model: nil,
              tokens_in: chunk.usage?.prompt_tokens ?? chunk.usage?.tokens_in,
              tokens_out: chunk.usage?.completion_tokens ?? chunk.usage?.tokens_out,
              usage: chunk.usage,
              error: nil
            )
          )
        }
        if choice.finish_reason != nil {
          return .done(
            ChatResponse(
              output: nil,
              conversation_id: nil,
              model: nil,
              tokens_in: chunk.usage?.prompt_tokens ?? chunk.usage?.tokens_in,
              tokens_out: chunk.usage?.completion_tokens ?? chunk.usage?.tokens_out,
              usage: chunk.usage,
              error: nil
            )
          )
        }
      }
      // Usage-only trailing frame (no choices)
      if chunk.usage != nil, chunk.choices == nil || chunk.choices?.isEmpty == true {
        return .done(
          ChatResponse(
            output: nil,
            conversation_id: nil,
            model: nil,
            tokens_in: chunk.usage?.prompt_tokens ?? chunk.usage?.tokens_in,
            tokens_out: chunk.usage?.completion_tokens ?? chunk.usage?.tokens_out,
            usage: chunk.usage,
            error: nil
          )
        )
      }
    }

    return .unknown(raw)
  }
}
