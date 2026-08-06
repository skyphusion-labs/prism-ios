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
  /// Plane (or other) structured failure with machine code + human message.
  case api(code: String, message: String, httpStatus: Int?)
  case cancelled
}

extension PrismError: LocalizedError {
  public var errorDescription: String? {
    userFacingMessage
  }

  /// Action-oriented copy for UI (quota → top-up, i2v missing image, etc.).
  public var userFacingMessage: String {
    switch self {
    case .invalidURL(let s):
      return "Invalid URL: \(s)"
    case .httpStatus(let code, let message):
      return Self.mapHttp(code: code, message: message)
    case .decoding(let s):
      return "Could not read server response (\(s))."
    case .transport(let s):
      if s.localizedCaseInsensitiveContains("cancel") { return "Cancelled." }
      return s
    case .unauthenticated:
      return "Not signed in. Enroll a device key (control plane) or sign in (playground)."
    case .serverError(let s):
      return Self.mapMessage(s)
    case .api(let code, let message, let http):
      return Self.mapApi(code: code, message: message, httpStatus: http)
    case .cancelled:
      return "Cancelled."
    }
  }

  private static func mapHttp(code: Int, message: String?) -> String {
    if let message {
      let mapped = mapMessage(message)
      if mapped != message { return mapped }
      if let api = parsePlaneError(message) {
        return mapApi(code: api.code, message: api.message, httpStatus: code)
      }
    }
    switch code {
    case 402: return "Out of credit. Open Settings → Top up, or wait for monthly allowance reset."
    case 401: return "Session or device key rejected. Re-enroll or sign in again."
    case 403: return message.map { mapMessage($0) } ?? "Not allowed for this account or model."
    case 404: return message.map { mapMessage($0) } ?? "Not found."
    case 408, 504: return "Upstream timed out. Retry, or pick a faster model (e.g. Seedance Fast / Veo Fast)."
    case 429: return "Rate limited. Wait a moment and try again."
    case 502, 503: return message.map { mapMessage($0) } ?? "Service unavailable. Retry shortly."
    default:
      return message.map { "HTTP \(code): \(mapMessage($0))" } ?? "HTTP \(code)"
    }
  }

  private static func mapApi(code: String, message: String, httpStatus: Int?) -> String {
    switch code {
    case "quota_exhausted":
      return "Out of credit. Open Settings → Top up (prepaid) or wait for monthly allowance reset."
    case "rate_limited":
      return "Rate limited. Wait a moment and try again."
    case "model_not_entitled", "model_not_found":
      return "That model is not available on this plan. Pick another from the catalog."
    case "model_unpriced":
      return "That model has no price yet (unspendable). Pick a spendable model."
    case "unauthenticated", "client_revoked":
      return "Device key missing or revoked. Clear it in Settings and re-enroll."
    case "invalid_request":
      if message.localizedCaseInsensitiveContains("image")
        || message.localizedCaseInsensitiveContains("i2v")
        || message.localizedCaseInsensitiveContains("first_frame")
      {
        return "This model needs a reference image. Add a photo or https/data URL, or pick a text-only model (Veo / Seedance)."
      }
      return redactSecrets(message)
    case "upstream_timeout":
      return "Generation timed out. Retry, or use Seedance Fast / Veo Fast."
    case "upstream_error":
      if message.contains("7003") || message.localizedCaseInsensitiveContains("user input") {
        return "Provider rejected the request (7003). Prefer Veo or Seedance Fast for video; check the model footer."
      }
      if message.localizedCaseInsensitiveContains("upload_url")
        || message.localizedCaseInsensitiveContains("zero data retention")
      {
        return "Grok video needs plane 0.4.14+ (ZDR upload path). Update play-proxy, or use Veo / Seedance Fast."
      }
      return redactSecrets(message)
    case "unavailable":
      return redactSecrets(message)
    default:
      if let httpStatus, (402...402).contains(httpStatus) {
        return mapHttp(code: httpStatus, message: message)
      }
      return message.isEmpty ? code : redactSecrets(message)
    }
  }

  private static func mapMessage(_ message: String) -> String {
    let lower = message.lowercased()
    if lower.contains("quota") || lower.contains("402") || lower.contains("credit") && lower.contains("exhaust") {
      return "Out of credit. Open Settings → Top up, or wait for monthly allowance reset."
    }
    if lower.contains("7003") {
      return "Provider rejected the request (7003). Prefer Veo or Seedance Fast for video."
    }
    if lower.contains("requires an image") || lower.contains("i2v") && lower.contains("image") {
      return "This model needs a reference image. Add a photo or URL, or pick Veo / Seedance for text-only video."
    }
    if lower.contains("upload_url") || lower.contains("zero data retention") {
      return "Grok video needs plane 0.4.14+ (ZDR upload path). Prefer Veo / Seedance Fast until then."
    }
    if lower.contains("invalid or expired media") || lower.contains("media download token")
      || lower.contains("media upload token")
    {
      return "Media link expired. Generate again to get a fresh download URL."
    }
    if lower.contains("cancel") {
      return "Cancelled."
    }
    return redactSecrets(message)
  }

  /// Never surface device keys or long secrets in UI copy.
  public static func redactSecrets(_ message: String) -> String {
    var s = message
    // pcp_<id>_<secret>
    if let re = try? NSRegularExpression(pattern: #"pcp_[A-Za-z0-9._-]{8,}"#, options: []) {
      let range = NSRange(s.startIndex..<s.endIndex, in: s)
      s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "pcp_…")
    }
    if let re = try? NSRegularExpression(pattern: #"Bearer\s+\S+"#, options: [.caseInsensitive]) {
      let range = NSRange(s.startIndex..<s.endIndex, in: s)
      s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "Bearer …")
    }
    return s
  }

  private static func parsePlaneError(_ raw: String) -> (code: String, message: String)? {
    // Tolerate "code: message" or JSON fragments embedded in HTTP messages.
    if let data = raw.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      if let err = obj["error"] as? [String: Any],
         let code = err["code"] as? String
      {
        let msg = (err["message"] as? String) ?? raw
        return (code, msg)
      }
      if let code = obj["code"] as? String {
        return (code, (obj["message"] as? String) ?? raw)
      }
    }
    return nil
  }
}

/// Map any thrown error to UI copy (PrismError or NSError cancellation).
public func prismUserFacingError(_ error: Error) -> String {
  if let p = error as? PrismError { return p.userFacingMessage }
  if error is CancellationError { return PrismError.cancelled.userFacingMessage }
  let ns = error as NSError
  if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
    return PrismError.cancelled.userFacingMessage
  }
  // Re-enter via a lightweight PrismError so mapping stays in one place.
  return PrismError.serverError(error.localizedDescription).userFacingMessage
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
  /// Optional human price snippet for pickers (e.g. "$0.04/image").
  public let priceLabel: String?

  public init(
    model: String,
    label: String? = nil,
    type: String? = nil,
    provider: String? = nil,
    streaming: Bool? = nil,
    group: String? = nil,
    capabilities: [String]? = nil,
    priceLabel: String? = nil
  ) {
    self.model = model
    self.label = label
    self.type = type
    self.provider = provider
    self.streaming = streaming
    self.group = group
    self.capabilities = capabilities
    self.priceLabel = priceLabel
  }

  private enum CodingKeys: String, CodingKey {
    case model, id, label, type, provider, streaming, group, capabilities, priceLabel
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
    priceLabel = try c.decodeIfPresent(String.self, forKey: .priceLabel)
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
    try c.encodeIfPresent(priceLabel, forKey: .priceLabel)
  }

  public var isSpendable: Bool {
    !(capabilities ?? []).contains("unspendable")
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

// MARK: - Conversation compact (playground Worker v0.175.7)

/// Compact summary the Worker injects into model context instead of older raw turns.
/// The full UI transcript is unchanged; only the wire history shrinks.
public struct ConversationCompactState: Codable, Sendable, Equatable {
  public var summary: String
  /// Highest server `turn_index` covered by the summary.
  public var through_turn_index: Int
  public var keep_recent: Int
  public var model: String
  public var updated_at: String?

  public init(
    summary: String,
    through_turn_index: Int,
    keep_recent: Int,
    model: String,
    updated_at: String? = nil
  ) {
    self.summary = summary
    self.through_turn_index = through_turn_index
    self.keep_recent = keep_recent
    self.model = model
    self.updated_at = updated_at
  }

  /// System block to prepend when compact is active (matches prism `buildCompactSystemBlock`).
  public var systemBlock: String {
    ConversationCompact.buildSystemBlock(summary: summary)
  }
}

/// `POST /api/conversations/:id/compact` body.
public struct ConversationCompactRequest: Codable, Sendable, Equatable {
  public var keep_recent: Int?
  public var model: String?

  public init(keepRecent: Int? = 2, model: String? = nil) {
    self.keep_recent = keepRecent
    self.model = model
  }
}

/// `POST /api/conversations/:id/compact` response.
public struct ConversationCompactResponse: Codable, Sendable, Equatable {
  public let conversation_id: String?
  public let compact: ConversationCompactState?
  public let turns_summarized: Int?
  public let turns_kept_raw: Int?
  public let ai_gateway_log_id: String?
  public let error: String?
  public let code: String?
}

/// `DELETE /api/conversations/:id/compact` response.
public struct ConversationCompactClearResponse: Codable, Sendable, Equatable {
  public let conversation_id: String?
  public let compact: ConversationCompactState?
  public let cleared: Bool?
  public let error: String?
}

/// Minimal `GET /api/conversations/:id` envelope (turns optional; compact is the compact field).
public struct ConversationDetailResponse: Codable, Sendable, Equatable {
  public let conversation_id: String?
  public let compact: ConversationCompactState?
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
  public let price: ControlPlaneTokenPrice?
  public let unit_price: ControlPlaneUnitPrice?

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
      capabilities: caps.isEmpty ? nil : caps,
      priceLabel: Self.priceSnippet(token: price, unit: unit_price, modality: modality)
    )
  }

  private static func priceSnippet(
    token: ControlPlaneTokenPrice?,
    unit: ControlPlaneUnitPrice?,
    modality: String?
  ) -> String? {
    if let u = unit?.micro_usd_per_unit {
      let usd = Double(u) / 1_000_000.0
      let unitName = unit?.unit ?? "unit"
      if usd == 0 { return "included" }
      if usd >= 0.01 {
        return String(format: "$%.2f/%@", usd, unitName)
      }
      return String(format: "$%.4f/%@", usd, unitName)
    }
    if let inp = token?.input_micro_usd_per_mtok, let out = token?.output_micro_usd_per_mtok {
      let i = Double(inp) / 1_000_000.0
      let o = Double(out) / 1_000_000.0
      return String(format: "$%.2f/$%.2f /MTok", i, o)
    }
    _ = modality
    return nil
  }
}

public struct ControlPlaneTokenPrice: Codable, Sendable, Equatable {
  public let input_micro_usd_per_mtok: Int?
  public let output_micro_usd_per_mtok: Int?
  public let priced_at: String?
  public let source: String?
}

public struct ControlPlaneUnitPrice: Codable, Sendable, Equatable {
  public let micro_usd_per_unit: Int?
  public let unit: String?
  public let priced_at: String?
  public let source: String?
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

  /// Single-line balance for banners.
  public var balanceDescription: String {
    let spendable = spendable_remaining_micro_usd ?? remaining_micro_usd
    if let s = spendable {
      let usd = Double(s) / 1_000_000.0
      let period = period.map { " · \($0)" } ?? ""
      let o = overage == true ? " · overage" : ""
      return String(format: "$%.4f spendable%@%@", usd, period, o)
    }
    return "usage unknown"
  }

  /// Multi-line dual-pool detail for Settings.
  public var dualPoolLines: [String] {
    var lines: [String] = []
    if let s = spendable_remaining_micro_usd ?? remaining_micro_usd {
      lines.append(String(format: "Spendable: $%.4f", Double(s) / 1_000_000.0))
    }
    if let c = remaining_micro_usd ?? credit_micro_usd {
      // Prefer prepaid remaining when both pools exist.
      if let prepaid = remaining_micro_usd {
        lines.append(String(format: "Prepaid remaining: $%.4f", Double(prepaid) / 1_000_000.0))
      } else {
        lines.append(String(format: "Prepaid credit: $%.4f", Double(c) / 1_000_000.0))
      }
    }
    if let a = allowance_remaining_micro_usd {
      lines.append(String(format: "Monthly remaining: $%.4f", Double(a) / 1_000_000.0))
    } else if let incl = monthly_included_micro_usd, let spent = allowance_spent_micro_usd {
      let rem = max(0, incl - spent)
      lines.append(String(format: "Monthly remaining: $%.4f", Double(rem) / 1_000_000.0))
    }
    if let p = period { lines.append("Period: \(p)") }
    if overage == true { lines.append("Overage: yes") }
    return lines
  }
}

/// `POST /v1/store/redeem` response.
public struct StoreRedeemResponse: Codable, Sendable, Equatable {
  public let applied: Bool?
  public let transaction_id: String?
  public let product_id: String?
  public let credit_granted_micro_usd: Int?
  public let credit_micro_usd: Int?
  public let spent_micro_usd: Int?
  public let environment: String?
  public let verified: String?
  public let error: APIErrorBody?

  public struct APIErrorBody: Codable, Sendable, Equatable {
    public let code: String?
    public let message: String?
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

// MARK: - Control plane TTS (`POST /v1/audio/speech`)

/// `POST /v1/audio/speech` body. Plane accepts `input` or `text`.
public struct SpeechGenerationRequest: Codable, Sendable, Equatable {
  public var model: String
  public var input: String

  public init(model: String, input: String) {
    self.model = model
    self.input = input
  }
}

/// Plane TTS envelope: base64 audio (typically mp3).
public struct SpeechGenerationResponse: Codable, Sendable, Equatable {
  public let model: String?
  public let audio_base64: String?
  public let format: String?
  public let error: ControlPlaneErrorBody?

  /// Decoded audio bytes when `audio_base64` is present.
  public var audioData: Data? {
    guard let raw = audio_base64, !raw.isEmpty else { return nil }
    var s = raw
    if let r = s.range(of: "base64,") {
      s = String(s[r.upperBound...])
    }
    return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
  }
}

// MARK: - Control plane STT (`POST /v1/audio/transcriptions`)

/// `POST /v1/audio/transcriptions` body. `audio` is raw base64 or a data: URL.
public struct TranscriptionRequest: Codable, Sendable, Equatable {
  public var model: String
  public var audio: String

  public init(model: String, audio: String) {
    self.model = model
    self.audio = audio
  }
}

/// Plane STT envelope: transcript text.
public struct TranscriptionResponse: Codable, Sendable, Equatable {
  public let model: String?
  public let text: String?
  public let error: ControlPlaneErrorBody?
}

// MARK: - Control plane music (`POST /v1/music/generations`)

/// `POST /v1/music/generations` body.
public struct MusicGenerationRequest: Codable, Sendable, Equatable {
  public var model: String
  public var prompt: String
  public var lyrics: String?

  public init(model: String, prompt: String, lyrics: String? = nil) {
    self.model = model
    self.prompt = prompt
    self.lyrics = lyrics
  }
}

/// Plane music envelope: `audio` is a URL or inline base64/data asset.
public struct MusicGenerationResponse: Codable, Sendable, Equatable {
  public let model: String?
  public let audio: String?
  public let error: ControlPlaneErrorBody?

  /// When `audio` is raw base64 or a data URL, decoded bytes; nil for https URLs.
  public var audioData: Data? {
    guard let raw = audio, !raw.isEmpty else { return nil }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return nil }
    var s = raw
    if let r = s.range(of: "base64,") {
      s = String(s[r.upperBound...])
    }
    return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
  }

  public var audioURL: String? {
    guard let raw = audio, raw.hasPrefix("http://") || raw.hasPrefix("https://") else { return nil }
    return raw
  }
}

public struct HealthResponse: Codable, Sendable, Equatable {
  public let ok: Bool
  public let ts: Int?
  public let service: String?
}
