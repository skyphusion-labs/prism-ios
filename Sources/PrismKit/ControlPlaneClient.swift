import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the **Prism control plane** (metered inference, `play-proxy.skyphusion.org`).
///
/// Auth is a long-lived device key: `Authorization: Bearer pcp_<key_id>_<secret>`.
/// Store the key in Keychain; it is returned once at enrollment.
///
/// Contract: `prism-control-plane` `docs/CONTRACT.md` + `docs/openapi.yaml`.
public final class ControlPlaneClient: @unchecked Sendable {
  public let http: HTTPClient
  /// Device key (`pcp_...`). Nil until enroll or inject.
  public private(set) var clientKey: String?

  public static let productionBaseURL = URL(string: "https://play-proxy.skyphusion.org")!

  public init(baseURL: URL = ControlPlaneClient.productionBaseURL, clientKey: String? = nil) {
    self.http = HTTPClient(baseURL: baseURL)
    self.clientKey = clientKey
  }

  public init(http: HTTPClient, clientKey: String? = nil) {
    self.http = http
    self.clientKey = clientKey
  }

  public func setClientKey(_ key: String?) {
    clientKey = key
  }

  private func requireKey() throws -> String {
    guard let key = clientKey, !key.isEmpty else { throw PrismError.unauthenticated }
    return key
  }

  // MARK: - Health

  public func health() async throws -> ControlPlaneHealth {
    try await http.sendJSON(method: "GET", path: "/health")
  }

  // MARK: - Enrollment

  /// Exchange a single-use enrollment token for a device key (returned once).
  public func enroll(enrollmentToken: String, label: String? = nil, platform: String = "ios") async throws -> EnrollmentResponse {
    struct Body: Encodable {
      let enrollment_token: String
      let label: String?
      let platform: String
    }
    let res: EnrollmentResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/clients",
      body: Body(enrollment_token: enrollmentToken, label: label, platform: platform),
      okStatuses: Set([200, 201])
    )
    clientKey = res.key
    return res
  }

  // MARK: - Account

  /// Account, plan, and current-period usage (`GET /v1/me`).
  public func me() async throws -> MeResponse {
    let key = try requireKey()
    return try await http.sendJSON(method: "GET", path: "/v1/me", bearer: key)
  }

  /// Current-period usage detail (`GET /v1/usage`).
  public func usage() async throws -> UsageSummary {
    let key = try requireKey()
    return try await http.sendJSON(method: "GET", path: "/v1/usage", bearer: key)
  }

  // MARK: - Models

  /// Entitled model list with prices (`GET /v1/models`). Absent models are not entitled.
  public func listModels() async throws -> ControlPlaneModelList {
    let key = try requireKey()
    return try await http.sendJSON(method: "GET", path: "/v1/models", bearer: key)
  }

  // MARK: - Inference

  public func chatCompletions(_ body: ControlPlaneChatRequest) async throws -> ControlPlaneChatResponse {
    let key = try requireKey()
    var payload = body
    payload.stream = false
    let res: ControlPlaneChatResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/chat/completions",
      body: payload,
      bearer: key
    )
    if let err = res.error {
      throw PrismError.serverError(err.message ?? err.code ?? "control plane error")
    }
    return res
  }

  /// Streaming chat (`stream: true`). Yields OpenAI-compatible SSE frames as
  /// ``ChatStreamEvent`` (delta / done / error). Same event shape as playground.
  public func chatCompletionsStream(
    _ body: ControlPlaneChatRequest
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let key = try requireKey()
          var payload = body
          payload.stream = true
          let dataBody = try JSONEncoder().encode(payload)
          let req = try http.request(
            method: "POST",
            path: "/v1/chat/completions",
            body: dataBody,
            headers: ["Accept": "text/event-stream"],
            bearer: key
          )
          for try await event in SSEStream.chatEvents(session: http.session, request: req) {
            if Task.isCancelled { break }
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Multi-turn chat (non-streaming). Prefer building `messages` from the UI transcript.
  public func chat(model: String, messages: [ControlPlaneChatMessage]) async throws -> String {
    let res = try await chatCompletions(ControlPlaneChatRequest(model: model, messages: messages, stream: false))
    guard let text = res.firstContent, !text.isEmpty else {
      throw PrismError.serverError("Empty completion")
    }
    return text
  }

  /// Collect stream deltas into one string.
  public func chatStreamText(model: String, messages: [ControlPlaneChatMessage]) async throws -> String {
    var parts: [String] = []
    var finalOut: String?
    let body = ControlPlaneChatRequest(model: model, messages: messages, stream: true)
    for try await e in chatCompletionsStream(body) {
      switch e {
      case .delta(let t): parts.append(t)
      case .done(let r):
        if let out = r.output, !out.isEmpty { finalOut = out }
      case .error(let m): throw PrismError.serverError(m)
      case .unknown: break
      }
    }
    let joined = parts.joined()
    if !joined.isEmpty { return joined }
    if let finalOut, !finalOut.isEmpty { return finalOut }
    throw PrismError.serverError("Empty stream completion")
  }

  /// Simple single-turn helper.
  public func chat(model: String, user: String, system: String? = nil) async throws -> String {
    var messages: [ControlPlaneChatMessage] = []
    if let system, !system.isEmpty {
      messages.append(ControlPlaneChatMessage(role: "system", content: system))
    }
    messages.append(ControlPlaneChatMessage(role: "user", content: user))
    return try await chat(model: model, messages: messages)
  }

  // MARK: - Image / video (unit-priced)

  /// Long-running non-chat doors; client wait above plane's nonchat ceiling (180s).
  public static let nonChatTimeout: TimeInterval = 200

  /// `POST /v1/images/generations` -- returns `data[].b64_json`.
  public func generateImage(_ body: ImageGenerationRequest) async throws -> ImageGenerationResponse {
    let key = try requireKey()
    let res: ImageGenerationResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/images/generations",
      body: body,
      bearer: key,
      timeout: Self.nonChatTimeout
    )
    if let err = res.error {
      throw PrismError.serverError(err.message ?? err.code ?? "image generation error")
    }
    guard res.firstBase64 != nil || res.firstDisplayURL != nil else {
      throw PrismError.serverError("Empty image payload")
    }
    return res
  }

  public func generateImage(model: String, prompt: String, image: String? = nil) async throws -> ImageGenerationResponse {
    try await generateImage(ImageGenerationRequest(model: model, prompt: prompt, image: image))
  }

  /// `POST /v1/videos/generations` -- `video` is a URL or inline asset.
  public func generateVideo(_ body: VideoGenerationRequest) async throws -> VideoGenerationResponse {
    let key = try requireKey()
    let res: VideoGenerationResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/videos/generations",
      body: body,
      bearer: key,
      timeout: Self.nonChatTimeout
    )
    if let err = res.error {
      throw PrismError.serverError(err.message ?? err.code ?? "video generation error")
    }
    guard let video = res.video, !video.isEmpty else {
      throw PrismError.serverError("Empty video payload")
    }
    return res
  }

  public func generateVideo(model: String, prompt: String, image: String? = nil) async throws -> VideoGenerationResponse {
    try await generateVideo(VideoGenerationRequest(model: model, prompt: prompt, image: image))
  }

  /// `POST /v1/audio/speech` -- metered TTS; returns base64 audio (mp3 by default).
  public func generateSpeech(_ body: SpeechGenerationRequest) async throws -> SpeechGenerationResponse {
    let key = try requireKey()
    let res: SpeechGenerationResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/audio/speech",
      body: body,
      bearer: key,
      timeout: Self.nonChatTimeout
    )
    if let err = res.error {
      throw PrismError.serverError(err.message ?? err.code ?? "speech generation error")
    }
    guard res.audioData != nil else {
      throw PrismError.serverError("Empty speech audio payload")
    }
    return res
  }

  public func generateSpeech(model: String, input: String) async throws -> SpeechGenerationResponse {
    try await generateSpeech(SpeechGenerationRequest(model: model, input: input))
  }

  // MARK: - Store

  /// Apply a StoreKit 2 signed transaction as prepaid credit (`POST /v1/store/redeem`).
  public func redeemStore(signedTransaction: String) async throws -> StoreRedeemResponse {
    let key = try requireKey()
    struct Body: Encodable {
      let signed_transaction: String
    }
    let res: StoreRedeemResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/store/redeem",
      body: Body(signed_transaction: signedTransaction),
      bearer: key,
      okStatuses: Set([200])
    )
    if let err = res.error {
      throw PrismError.api(
        code: err.code ?? "store_error",
        message: err.message ?? "store redeem failed",
        httpStatus: nil
      )
    }
    return res
  }
}
