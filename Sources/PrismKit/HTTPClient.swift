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
    let storage = cookieStorage ?? HTTPCookieStorage()
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
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw PrismError.transport(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else {
      throw PrismError.transport("Non-HTTP response")
    }
    // Persist Set-Cookie into our jar (needed when URLSession config does not).
    if let url = http.url, let fields = http.allHeaderFields as? [String: String] {
      let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
      cookies.forEach { cookieStorage.setCookie($0) }
    }
    return (data, http)
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
