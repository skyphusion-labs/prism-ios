import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin async HTTP helper with cookie jar support for public Prism sessions.
public final class HTTPClient: @unchecked Sendable {
  public let baseURL: URL
  public let session: URLSession
  public let cookieStorage: HTTPCookieStorage

  public init(baseURL: URL, session: URLSession? = nil, cookieStorage: HTTPCookieStorage? = nil) {
    self.baseURL = baseURL
    // On Apple platforms HTTPCookieStorage() is fine; on Linux (FoundationNetworking)
    // only shared / named stores are available -- use shared for the default jar.
    let storage = cookieStorage ?? HTTPCookieStorage.shared
    self.cookieStorage = storage
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.ephemeral
      config.httpCookieStorage = storage
      config.httpCookieAcceptPolicy = .always
      config.httpShouldSetCookies = true
      // Fable (and other thinking models) can sit silent tens of seconds between SSE
      // frames while the model thinks. Default 60s idle kills the stream mid-think →
      // Empty stream completion. 5 min idle / 15 min resource covers long premium runs.
      config.timeoutIntervalForRequest = 300
      config.timeoutIntervalForResource = 900
      self.session = URLSession(configuration: config)
    }
  }

  public func url(path: String, query: [URLQueryItem] = []) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw PrismError.invalidURL(baseURL.absoluteString)
    }
    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
    if basePath.isEmpty {
      components.path = "/" + rel
    } else {
      components.path = "/" + basePath + "/" + rel
    }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw PrismError.invalidURL(path) }
    return url
  }

  public func request(
    method: String,
    path: String,
    body: Data? = nil,
    headers: [String: String] = [:],
    bearer: String? = nil,
    timeout: TimeInterval? = nil
  ) throws -> URLRequest {
    var req = URLRequest(url: try url(path: path))
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil {
      req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      req.httpBody = body
    }
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let bearer {
      req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    if let timeout {
      req.timeoutInterval = timeout
    }
    // Attach cookies for this URL (ephemeral jar).
    if let cookies = cookieStorage.cookies(for: req.url!) {
      let header = HTTPCookie.requestHeaderFields(with: cookies)
      for (k, v) in header { req.setValue(v, forHTTPHeaderField: k) }
    }
    return req
  }

  public func send(
    _ request: URLRequest,
    preferBackground: Bool = false
  ) async throws -> (Data, HTTPURLResponse) {
    let pair: (Data, URLResponse)
    do {
      pair = try await perform(request, preferBackground: preferBackground)
    } catch {
      throw PrismError.transport(error.localizedDescription)
    }
    let (body, response) = pair
    guard let http = response as? HTTPURLResponse else {
      throw PrismError.transport("Non-HTTP response")
    }
    // Persist Set-Cookie into our jar (needed when URLSession config does not).
    if let url = http.url {
      // allHeaderFields values are not always String on every platform.
      var fields: [String: String] = [:]
      for (k, v) in http.allHeaderFields {
        fields[String(describing: k)] = String(describing: v)
      }
      let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
      cookies.forEach { cookieStorage.setCookie($0) }
    }
    return (body, http)
  }

  /// URLSession.data(for:) is Apple-only in some toolchains; bridge via completion handler for Linux CI.
  ///
  /// When `preferBackground` is true on iOS, uses ``LongRunningURLSession`` so the
  /// request continues after lock / home (video, music, long non-chat doors).
  private func perform(
    _ request: URLRequest,
    preferBackground: Bool
  ) async throws -> (Data, URLResponse) {
    #if os(iOS)
    if preferBackground {
      return try await LongRunningURLSession.shared.perform(request)
    }
    #endif
    return try await performForeground(request)
  }

  private func performForeground(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation { cont in
      let task = session.dataTask(with: request) { data, response, error in
        if let error {
          cont.resume(throwing: error)
          return
        }
        guard let data, let response else {
          cont.resume(throwing: URLError(.badServerResponse))
          return
        }
        cont.resume(returning: (data, response))
      }
      task.resume()
    }
  }

  public func sendJSON<T: Decodable>(
    method: String,
    path: String,
    body: (any Encodable)? = nil,
    headers: [String: String] = [:],
    bearer: String? = nil,
    as type: T.Type = T.self,
    okStatuses: Set<Int> = Set(200...299),
    timeout: TimeInterval? = nil,
    preferBackground: Bool = false
  ) async throws -> T {
    let pair: (HTTPURLResponse, T) = try await sendJSONWithResponse(
      method: method,
      path: path,
      body: body,
      headers: headers,
      bearer: bearer,
      as: type,
      okStatuses: okStatuses,
      timeout: timeout,
      preferBackground: preferBackground
    )
    return pair.1
  }

  /// Like `sendJSON` but also returns the HTTP response (for `prism-usage-micro-usd`, etc.).
  public func sendJSONWithResponse<T: Decodable>(
    method: String,
    path: String,
    body: (any Encodable)? = nil,
    headers: [String: String] = [:],
    bearer: String? = nil,
    as type: T.Type = T.self,
    okStatuses: Set<Int> = Set(200...299),
    timeout: TimeInterval? = nil,
    preferBackground: Bool = false
  ) async throws -> (HTTPURLResponse, T) {
    let dataBody: Data?
    if let body {
      dataBody = try JSONEncoder().encode(AnyEncodable(body))
    } else {
      dataBody = nil
    }
    let req = try request(
      method: method,
      path: path,
      body: dataBody,
      headers: headers,
      bearer: bearer,
      timeout: timeout
    )
    let (data, http) = try await send(req, preferBackground: preferBackground)
    if !okStatuses.contains(http.statusCode) {
      throw Self.prismError(from: data, status: http.statusCode)
    }
    do {
      let value = try JSONDecoder().decode(T.self, from: data)
      return (http, value)
    } catch {
      throw PrismError.decoding(error.localizedDescription)
    }
  }

  public func sendRaw(
    method: String,
    path: String,
    body: Data? = nil,
    headers: [String: String] = [:],
    bearer: String? = nil,
    okStatuses: Set<Int> = Set(200...299)
  ) async throws -> (Data, HTTPURLResponse) {
    let req = try request(method: method, path: path, body: body, headers: headers, bearer: bearer)
    let (data, http) = try await send(req)
    if !okStatuses.contains(http.statusCode) {
      throw Self.prismError(from: data, status: http.statusCode)
    }
    return (data, http)
  }

  /// Prefer structured plane `{ error: { code, message } }` when present.
  public static func prismError(from data: Data, status: Int) -> PrismError {
    if status == 401 { return .unauthenticated }
    struct ErrObj: Decodable {
      let error: FlexibleError?
      let message: String?
      struct FlexibleError: Decodable {
        let message: String?
        let code: String?
      }
    }
    if let e = try? JSONDecoder().decode(ErrObj.self, from: data),
       let code = e.error?.code, !code.isEmpty
    {
      let msg = e.error?.message ?? e.message ?? code
      return .api(code: code, message: msg, httpStatus: status)
    }
    let message = extractErrorMessage(data)
    return .httpStatus(status, message: message)
  }

  public static func extractErrorMessage(_ data: Data) -> String? {
    struct ErrObj: Decodable {
      let error: FlexibleError?
      let message: String?
      struct FlexibleError: Decodable {
        let message: String?
        let code: String?
      }
    }
    if let e = try? JSONDecoder().decode(ErrObj.self, from: data) {
      if let m = e.error?.message ?? e.error?.code ?? e.message { return m }
    }
    struct ErrStr: Decodable { let error: String?; let message: String? }
    if let e = try? JSONDecoder().decode(ErrStr.self, from: data) {
      return e.error ?? e.message
    }
    return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
  }

  // MARK: - Cookie jar helpers (playground session)

  /// Value of a named cookie for `baseURL`, if present in the jar.
  public func cookieValue(named name: String) -> String? {
    guard let cookies = cookieStorage.cookies(for: baseURL) else { return nil }
    return cookies.first(where: { $0.name == name })?.value
  }

  /// Inject a host-only Secure cookie (suitable for `__Host-…` session cookies).
  @discardableResult
  public func setCookie(name: String, value: String, path: String = "/") -> Bool {
    let props: [HTTPCookiePropertyKey: Any] = [
      .name: name,
      .value: value,
      .path: path,
      .secure: "TRUE",
      .originURL: baseURL,
    ]
    // __Host- cookies must not set Domain; host-only via originURL.
    guard let cookie = HTTPCookie(properties: props) else { return false }
    cookieStorage.setCookie(cookie)
    return true
  }

  /// Drop cookies for `baseURL` (or all in this jar when `forBase` is false).
  public func clearCookies(forBaseOnly: Bool = true) {
    if forBaseOnly, let cookies = cookieStorage.cookies(for: baseURL) {
      for c in cookies { cookieStorage.deleteCookie(c) }
      return
    }
    if let all = cookieStorage.cookies {
      for c in all { cookieStorage.deleteCookie(c) }
    }
  }
}

/// Type-erased Encodable for optional request bodies.
struct AnyEncodable: Encodable {
  private let encodeFunc: (Encoder) throws -> Void
  init(_ value: any Encodable) {
    encodeFunc = value.encode
  }
  func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
