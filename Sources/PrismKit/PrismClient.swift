import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the **Prism playground Worker** (`play.skyphusion.org` or self-host).
///
/// Public mode (`AUTH_MODE=public`) uses an httpOnly session cookie
/// (`__Host-prism_session`). This client keeps an in-memory cookie jar and
/// replays `Set-Cookie` from login/signup.
///
/// Access mode (self-host behind CF Access) needs Access headers on every call;
/// pass them via `defaultHeaders` (e.g. service-token headers for automation).
public final class PrismClient: @unchecked Sendable {
  public let http: HTTPClient
  public var defaultHeaders: [String: String]

  /// Hosted public playground.
  public static let playBaseURL = URL(string: "https://play.skyphusion.org")!

  public init(baseURL: URL = PrismClient.playBaseURL, defaultHeaders: [String: String] = [:]) {
    self.http = HTTPClient(baseURL: baseURL)
    self.defaultHeaders = defaultHeaders
  }

  /// Inject a preconfigured HTTP stack (tests).
  public init(http: HTTPClient, defaultHeaders: [String: String] = [:]) {
    self.http = http
    self.defaultHeaders = defaultHeaders
  }

  // MARK: - Health / catalog

  public func health() async throws -> HealthResponse {
    try await http.sendJSON(method: "GET", path: "/health", headers: defaultHeaders)
  }

  /// Boot probe: models + auth mode + whether the session is live.
  public func models() async throws -> ModelsResponse {
    try await http.sendJSON(method: "GET", path: "/api/models", headers: defaultHeaders)
  }

  // MARK: - Auth (public mode)

  public func signup(username: String, password: String) async throws -> AuthSuccess {
    struct Body: Encodable { let username: String; let password: String }
    return try await http.sendJSON(
      method: "POST",
      path: "/api/auth/signup",
      body: Body(username: username, password: password),
      headers: defaultHeaders,
      okStatuses: Set([200, 201])
    )
  }

  public func login(username: String, password: String) async throws -> AuthSuccess {
    struct Body: Encodable { let username: String; let password: String }
    return try await http.sendJSON(
      method: "POST",
      path: "/api/auth/login",
      body: Body(username: username, password: password),
      headers: defaultHeaders
    )
  }

  public func logout() async throws {
    struct Ok: Decodable { let ok: Bool? }
    _ = try await http.sendJSON(
      method: "POST",
      path: "/api/auth/logout",
      headers: defaultHeaders,
      as: Ok.self
    )
  }

  // MARK: - Chat

  public func chat(_ body: ChatRequestBody) async throws -> ChatResponse {
    let response: ChatResponse = try await http.sendJSON(
      method: "POST",
      path: "/api/chat",
      body: body,
      headers: defaultHeaders
    )
    if let err = response.error, !err.isEmpty {
      throw PrismError.serverError(err)
    }
    return response
  }

  /// Streaming chat via SSE (`POST /api/chat/stream`).
  ///
  /// Yields delta/done/error events as they arrive. The full response body is
  /// buffered then parsed (URLSession async bytes would be a follow-up).
  public func chatStream(_ body: ChatRequestBody) async throws -> [ChatStreamEvent] {
    let dataBody = try JSONEncoder().encode(body)
    let (data, _) = try await http.sendRaw(
      method: "POST",
      path: "/api/chat/stream",
      body: dataBody,
      headers: defaultHeaders
    )
    let text = String(data: data, encoding: .utf8) ?? ""
    return SSEParser.parseChatEvents(from: text)
  }

  /// Convenience: stream and concatenate delta text.
  public func chatStreamText(_ body: ChatRequestBody) async throws -> (text: String, final: ChatResponse?) {
    let events = try await chatStream(body)
    var parts: [String] = []
    var final: ChatResponse?
    for e in events {
      switch e {
      case .delta(let t): parts.append(t)
      case .done(let r): final = r
      case .error(let m): throw PrismError.serverError(m)
      case .unknown: break
      }
    }
    let joined = parts.joined()
    if let out = final?.output, !out.isEmpty { return (out, final) }
    return (joined, final)
  }
}
