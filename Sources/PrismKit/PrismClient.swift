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

  /// Streaming chat via SSE (`POST /api/chat/stream`), full-body then parse.
  /// Prefer ``chatStreamEvents`` for token-by-token UI updates on Apple platforms.
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

  /// Incremental SSE: yields events as frames arrive (Darwin `URLSession.bytes`;
  /// Linux buffers then parses -- same event shape either way).
  ///
  /// Note: `URLProtocol` mocks often deliver an empty `AsyncBytes` stream; unit
  /// tests should assert via ``chatStream`` (full body) instead of this path.
  public func chatStreamEvents(_ body: ChatRequestBody) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let dataBody = try JSONEncoder().encode(body)
          var headers = defaultHeaders
          if headers["Accept"] == nil {
            headers["Accept"] = "text/event-stream"
          }
          let req = try http.request(
            method: "POST",
            path: "/api/chat/stream",
            body: dataBody,
            headers: headers
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

  /// Convenience: stream and concatenate delta text (full-body parse; reliable in tests).
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
