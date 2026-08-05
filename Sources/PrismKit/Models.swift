import Foundation

// Shared Codable shapes for Prism playground (`play.skyphusion.org` / self-host)
// and the commercial control plane. Keep additive-friendly decoding: unknown
// JSON fields are ignored by Codable defaults.

// MARK: - Errors

public enum PrismError: Error, Equatable, Sendable {
  case invalidURL(String)
  case httpStatus(Int, message: String?)
  case decoding(String)
  case transport(String)
  case unauthenticated
  case serverError(String)
}

extension PrismError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidURL(let s): return "Invalid URL: \(s)"
    case .httpStatus(let code, let message):
      return message.map { "HTTP \(code): \($0)" } ?? "HTTP \(code)"
    case .decoding(let s): return "Decode failed: \(s)"
    case .transport(let s): return s
    case .unauthenticated: return "Not authenticated"
    case .serverError(let s): return s
    }
  }
}

// MARK: - Playground models catalog

public struct ModelEntry: Codable, Sendable, Equatable, Identifiable {
  public var id: String { model }

  public let model: String
  public let label: String?
  public let type: String?
  public let provider: String?
  public let streaming: Bool?
  public let group: String?
  public let capabilities: [String]?

  public init(
    model: String,
    label: String? = nil,
    type: String? = nil,
    provider: String? = nil,
    streaming: Bool? = nil,
    group: String? = nil,
    capabilities: [String]? = nil
  ) {
    self.model = model
    self.label = label
    self.type = type
    self.provider = provider
    self.streaming = streaming
    self.group = group
    self.capabilities = capabilities
  }
}

public struct GatewayStatus: Codable, Sendable, Equatable {
  public let configured: Bool?
  public let source: String?
  public let gateway_id: String?
  public let cf_aig_token_set: Bool?
  public let control_plane_configured: Bool?
  public let control_plane_key_set: Bool?
}

/// Envelope of `GET /api/models` (boot probe; no session required).
public struct ModelsResponse: Codable, Sendable, Equatable {
  public let models: [ModelEntry]
  public let mode: String?
  public let authenticated: Bool?
  public let user: String?
  public let username: String?
  public let gateway: GatewayStatus?
}

// MARK: - Auth

public struct AuthUser: Codable, Sendable, Equatable {
  public let username: String
}

public struct AuthSuccess: Codable, Sendable, Equatable {
  public let user: AuthUser?
  public let ok: Bool?
  public let error: String?
}

// MARK: - Chat (playground Worker)

public struct ChatRequestBody: Codable, Sendable, Equatable {
  public var model: String
  public var user_input: String
  public var system_prompt: String?
  public var conversation_id: String?
  public var use_docs: Bool?
  public var use_web_search: Bool?

  public init(
    model: String,
    userInput: String,
    systemPrompt: String? = nil,
    conversationId: String? = nil,
    useDocs: Bool? = nil,
    useWebSearch: Bool? = nil
  ) {
    self.model = model
    self.user_input = userInput
    self.system_prompt = systemPrompt
    self.conversation_id = conversationId
    self.use_docs = useDocs
    self.use_web_search = useWebSearch
  }
}

public struct ChatUsage: Codable, Sendable, Equatable {
  public let prompt_tokens: Int?
  public let completion_tokens: Int?
  public let tokens_in: Int?
  public let tokens_out: Int?
}

public struct ChatResponse: Codable, Sendable, Equatable {
  public let output: String?
  public let conversation_id: String?
  public let model: String?
  public let tokens_in: Int?
  public let tokens_out: Int?
  public let usage: ChatUsage?
  public let error: String?
}

// MARK: - SSE stream events (playground)

public enum ChatStreamEvent: Sendable, Equatable {
  case delta(String)
  case done(ChatResponse)
  case error(String)
  case unknown(String)
}

// MARK: - Control plane

public struct ControlPlaneHealth: Codable, Sendable, Equatable {
  public let ok: Bool
  public let service: String?
}

/// Nested account blob on enrollment (subset; plane may add fields).
public struct AccountSummary: Codable, Sendable, Equatable {
  public let id: String?
  public let credit_micro_usd: Int?
  public let plan: String?
  public let plan_id: String?
  public let status: String?
}

public struct EnrollmentResponse: Codable, Sendable, Equatable {
  public let client_id: String
  public let key: String
  public let account: AccountSummary?
}

// MARK: Control plane catalog (`GET /v1/models`)

public struct ControlPlaneModelList: Codable, Sendable, Equatable {
  public let object: String?
  public let data: [ControlPlaneModel]
}

public struct ControlPlaneModel: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let display_name: String?
  public let modality: String?
  public let billing: String?
  public let tier: String?
  public let streaming: Bool?
  public let max_output_tokens: Int?
  /// Whether the plane will run this model today (`false` => grey out, do not drop).
  public let spendable: Bool?

  /// Map into the playground-shaped picker entry used by the app shell.
  public func asModelEntry() -> ModelEntry {
    ModelEntry(
      model: id,
      label: display_name,
      type: modality ?? "chat",
      provider: billing,
      streaming: streaming,
      group: tier,
      capabilities: spendable == false ? ["unspendable"] : nil
    )
  }
}

// MARK: Control plane account (`GET /v1/me`, `GET /v1/usage`)

public struct MeResponse: Codable, Sendable, Equatable {
  public let client: MeClientInfo?
  public let account: AccountSummary?
  public let plan: PlanSummary?
  public let usage: UsageSummary?
}

public struct MeClientInfo: Codable, Sendable, Equatable {
  public let id: String?
  public let label: String?
  public let platform: String?
  public let created_at: String?
}

public struct PlanSummary: Codable, Sendable, Equatable {
  public let id: String?
  public let name: String?
  public let monthly_included_micro_usd: Int?
}

/// Dual-pool usage (prepaid credit + monthly allowance). All fields optional for decode resilience.
public struct UsageSummary: Codable, Sendable, Equatable {
  public let credit_micro_usd: Int?
  public let spent_micro_usd: Int?
  public let remaining_micro_usd: Int?
  public let monthly_included_micro_usd: Int?
  public let allowance_spent_micro_usd: Int?
  public let allowance_remaining_micro_usd: Int?
  public let spendable_remaining_micro_usd: Int?
  public let overage: Bool?
  public let period: String?
  public let period_micro_usd: Int?
  public let period_requests: Int?

  /// Human-readable balance line for Settings (micro-USD -> USD).
  public var balanceDescription: String {
    let spendable = spendable_remaining_micro_usd ?? remaining_micro_usd
    if let s = spendable {
      let usd = Double(s) / 1_000_000.0
      let period = period.map { " · \($0)" } ?? ""
      return String(format: "$%.4f remaining%@", usd, period)
    }
    return "usage unknown"
  }
}

public struct ControlPlaneChatMessage: Codable, Sendable, Equatable {
  public var role: String
  public var content: String

  public init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

public struct ControlPlaneChatRequest: Codable, Sendable, Equatable {
  public var model: String
  public var messages: [ControlPlaneChatMessage]
  public var stream: Bool?

  public init(model: String, messages: [ControlPlaneChatMessage], stream: Bool? = false) {
    self.model = model
    self.messages = messages
    self.stream = stream
  }
}

/// OpenAI-shaped completion response (control plane `/v1/chat/completions`).
public struct ControlPlaneChatResponse: Codable, Sendable, Equatable {
  public let id: String?
  public let choices: [Choice]?
  public let usage: ChatUsage?
  public let error: ControlPlaneErrorBody?

  public struct Choice: Codable, Sendable, Equatable {
    public let index: Int?
    public let message: ControlPlaneChatMessage?
    public let finish_reason: String?
  }

  public var firstContent: String? {
    choices?.first?.message?.content
  }
}

public struct ControlPlaneErrorBody: Codable, Sendable, Equatable {
  public let code: String?
  public let message: String?
}

public struct HealthResponse: Codable, Sendable, Equatable {
  public let ok: Bool
  public let ts: Int?
  public let service: String?
}
