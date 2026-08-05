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
    bearer: String? = nil
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
    // Attach cookies for this URL (ephemeral jar).
    if let cookies = cookieStorage.cookies(for: req.url!) {
      let header = HTTPCookie.requestHeaderFields(with: cookies)
      for (k, v) in header { req.setValue(v, forHTTPHeaderField: k) }
    }
    return req
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let pair: (Data, URLResponse)
    do {
      pair = try await perform(request)
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
  private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
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
    okStatuses: Set<Int> = Set(200...299)
  ) async throws -> T {
    let dataBody: Data?
    if let body {
      dataBody = try JSONEncoder().encode(AnyEncodable(body))
    } else {
      dataBody = nil
    }
    let req = try request(method: method, path: path, body: dataBody, headers: headers, bearer: bearer)
    let (data, http) = try await send(req)
    if !okStatuses.contains(http.statusCode) {
      let message = Self.extractErrorMessage(data)
      if http.statusCode == 401 { throw PrismError.unauthenticated }
      throw PrismError.httpStatus(http.statusCode, message: message)
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
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
      let message = Self.extractErrorMessage(data)
      if http.statusCode == 401 { throw PrismError.unauthenticated }
      throw PrismError.httpStatus(http.statusCode, message: message)
    }
    return (data, http)
  }

  public static func extractErrorMessage(_ data: Data) -> String? {
    struct Err: Decodable { let error: String?; let message: String? }
    guard let e = try? JSONDecoder().decode(Err.self, from: data) else {
      return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
    }
    return e.error ?? e.message
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
