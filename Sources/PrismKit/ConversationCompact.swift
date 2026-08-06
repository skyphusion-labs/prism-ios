import Foundation

/// Pure helpers for client-side compact (control plane) mirroring prism
/// `src/conversation-context.ts` (v0.175.7). Playground compact runs on the Worker.

public enum ConversationCompact {
  public static let defaultKeepRecent = 2
  public static let summaryMaxChars = 12_000
  /// Minimum completed chat pairs before compact is useful (`keep_recent` + 1).
  public static let minTurnsToCompact = defaultKeepRecent + 1

  public static let systemPrompt =
    "You compress multi-turn chat history into a continuity brief for another "
    + "assistant that will continue the conversation. Preserve: decisions, facts, "
    + "names, constraints, open questions, and anything the user asked to remember. "
    + "Drop chit-chat and repeated boilerplate. Write in neutral third person or "
    + "tight bullet form. No preamble like 'Here is a summary'."

  /// One completed user/assistant exchange. `throughTurnIndex` is the assistant
  /// turn's index in the linear local transcript (used as `through_turn_index`).
  public struct Pair: Sendable, Equatable {
    public let user: String
    public let assistant: String
    public let throughTurnIndex: Int

    public init(user: String, assistant: String, throughTurnIndex: Int) {
      self.user = user
      self.assistant = assistant
      self.throughTurnIndex = throughTurnIndex
    }
  }

  public static func normalizeSummary(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.count > summaryMaxChars {
      s = String(s.prefix(summaryMaxChars)) + "\n[summary truncated]"
    }
    return s
  }

  /// System block injected when compact is active (matches prism `buildCompactSystemBlock`).
  public static func buildSystemBlock(summary: String) -> String {
    let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return "" }
    return """
    [Compacted earlier conversation]
    The following is a summary of earlier turns in this thread. Treat it as authoritative context. Recent turns (if any) follow as normal messages.

    \(s)

    [End compacted context]
    """
  }

  public static func formatPairsForSummary(_ pairs: [Pair]) -> String {
    pairs.map { p in
      let u = p.user.isEmpty ? "(empty)" : p.user
      let a = p.assistant.isEmpty ? "(empty)" : p.assistant
      return "User:\n\(u)\n\nAssistant:\n\(a)"
    }.joined(separator: "\n\n---\n\n")
  }

  public static func splitPairs(
    _ pairs: [Pair],
    keepRecent: Int
  ) -> (summarize: [Pair], keep: [Pair]) {
    let k = max(0, keepRecent)
    if pairs.isEmpty { return ([], []) }
    if k == 0 { return (pairs, []) }
    if pairs.count <= k { return ([], pairs) }
    let cut = pairs.count - k
    return (Array(pairs.prefix(cut)), Array(pairs.suffix(k)))
  }
}
