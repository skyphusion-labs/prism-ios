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

  /// Model identifier used on chat requests.
  ///
  /// Live playground `GET /api/models` publishes this as `id` (not `model`).
  /// Older fixtures and some self-hosts use `model`. Decode accepts either.
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

  private enum CodingKeys: String, CodingKey {
    case model, id, label, type, provider, streaming, group, capabilities
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let m = try c.decodeIfPresent(String.self, forKey: .model), !m.isEmpty {
      model = m
    } else if let i = try c.decodeIfPresent(String.self, forKey: .id), !i.isEmpty {
      model = i
    } else {
      throw DecodingError.keyNotFound(
        CodingKeys.model,
        .init(codingPath: c.codingPath, debugDescription: "Expected model or id")
      )
    }
    label = try c.decodeIfPresent(String.self, forKey: .label)
    type = try c.decodeIfPresent(String.self, forKey: .type)
    provider = try c.decodeIfPresent(String.self, forKey: .provider)
    streaming = try c.decodeIfPresent(Bool.self, forKey: .streaming)
    group = try c.decodeIfPresent(String.self, forKey: .group)
    capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(model, forKey: .model)
    try c.encodeIfPresent(label, forKey: .label)
    try c.encodeIfPresent(type, forKey: .type)
    try c.encodeIfPresent(provider, forKey: .provider)
    try c.encodeIfPresent(streaming, forKey: .streaming)
    try c.encodeIfPresent(group, forKey: .group)
    try c.encodeIfPresent(capabilities, forKey: .capabilities)
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
  /// Picker hints: `text-to-image`, `image-input`, `image-input-required`, `text-to-video`, …
  public let capabilities: [String]?

  /// Map into the playground-shaped picker entry used by the app shell.
  public func asModelEntry() -> ModelEntry {
    var caps = capabilities ?? []
    if spendable == false, !caps.contains("unspendable") {
      caps.append("unspendable")
    }
    return ModelEntry(
      model: id,
      label: display_name,
      type: modality ?? "chat",
      provider: billing,
      streaming: streaming,
      group: tier,
      capabilities: caps.isEmpty ? nil : caps
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

// MARK: - Control plane image / video (unit-priced doors)

/// `POST /v1/images/generations` body. `image` is optional ref for i2i / edit.
public struct ImageGenerationRequest: Codable, Sendable, Equatable {
  public var model: String
  public var prompt: String
  /// Optional https or data: URL for models that accept reference images.
  public var image: String?

  public init(model: String, prompt: String, image: String? = nil) {
    self.model = model
    self.prompt = prompt
    self.image = image
  }
}

/// OpenAI-ish image envelope; plane returns `data[].b64_json` and/or `data[].url`.
///
/// Note: older plane builds mis-filed https URLs into `b64_json`. Clients should use
/// ``firstDisplayURL`` / ``firstBase64`` helpers which tolerate that.
public struct ImageGenerationResponse: Codable, Sendable, Equatable {
  public let created: Int?
  public let model: String?
  public let data: [ImageGenerationData]?
  public let error: ControlPlaneErrorBody?

  public struct ImageGenerationData: Codable, Sendable, Equatable {
    public let b64_json: String?
    public let url: String?
  }

  /// First image as raw base64 when the field is real base64 (not an https URL).
  public var firstBase64: String? {
    guard let raw = data?.first?.b64_json, !raw.isEmpty else { return nil }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return nil }
    if raw.hasPrefix("data:image/") {
      if let r = raw.range(of: "base64,") {
        return String(raw[r.upperBound...])
      }
    }
    return raw
  }

  /// First image URL (explicit `url` or legacy URL stuffed into `b64_json`).
  public var firstDisplayURL: String? {
    if let u = data?.first?.url, !u.isEmpty { return u }
    if let raw = data?.first?.b64_json,
       raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return raw
    }
    return nil
  }
}

/// `POST /v1/videos/generations` body. `image` is optional i2v (data: or https:).
public struct VideoGenerationRequest: Codable, Sendable, Equatable {
  public var model: String
  public var prompt: String?
  public var image: String?

  public init(model: String, prompt: String? = nil, image: String? = nil) {
    self.model = model
    self.prompt = prompt
    self.image = image
  }
}

/// Plane video envelope: `video` is a URL or inline asset string.
public struct VideoGenerationResponse: Codable, Sendable, Equatable {
  public let model: String?
  public let video: String?
  public let error: ControlPlaneErrorBody?
}

public struct HealthResponse: Codable, Sendable, Equatable {
  public let ok: Bool
  public let ts: Int?
  public let service: String?
}
