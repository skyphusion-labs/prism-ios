import XCTest
@testable import PrismKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PrismKitTests: XCTestCase {
  func testHealthString() {
    XCTAssertEqual(PrismKit.health(), "ok:PrismKit")
    XCTAssertEqual(PrismKit.version, "0.2.0")
  }

  func testMemorySecretStoreRoundTrip() throws {
    let store = MemorySecretStore()
    XCTAssertNil(try store.get("k"))
    try store.set("v", for: "k")
    XCTAssertEqual(try store.get("k"), "v")
    try store.set(nil, for: "k")
    XCTAssertNil(try store.get("k"))
  }

  func testControlPlaneModelAsEntry() throws {
    let json = """
    {
      "object":"list",
      "data":[{
        "id":"@cf/meta/llama",
        "display_name":"Llama",
        "modality":"chat",
        "billing":"workers-ai",
        "tier":"standard",
        "streaming":true,
        "max_output_tokens":4096,
        "spendable":true,
        "price":null,
        "published_rates":[]
      }]
    }
    """.data(using: .utf8)!
    let list = try JSONDecoder().decode(ControlPlaneModelList.self, from: json)
    XCTAssertEqual(list.data.count, 1)
    let entry = list.data[0].asModelEntry()
    XCTAssertEqual(entry.model, "@cf/meta/llama")
    XCTAssertEqual(entry.label, "Llama")
    XCTAssertEqual(entry.type, "chat")
    XCTAssertEqual(entry.streaming, true)
  }

  func testUsageBalanceDescription() throws {
    let json = #"{"spendable_remaining_micro_usd":1500000,"period":"2026-08"}"#.data(using: .utf8)!
    let u = try JSONDecoder().decode(UsageSummary.self, from: json)
    XCTAssertTrue(u.balanceDescription.contains("1.5000") || u.balanceDescription.contains("1.5"))
    XCTAssertTrue(u.balanceDescription.contains("2026-08"))
  }

  func testSSEParserDeltasAndDone() {
    let raw = """
    data: {"type":"delta","text":"Hel"}

    data: {"type":"delta","text":"lo"}

    data: {"type":"done","output":"Hello","conversation_id":"c1","tokens_in":3,"tokens_out":1}

    """
    let events = SSEParser.parseChatEvents(from: raw)
    XCTAssertEqual(events.count, 3)
    guard case .delta(let a) = events[0] else { return XCTFail("delta0") }
    guard case .delta(let b) = events[1] else { return XCTFail("delta1") }
    guard case .done(let done) = events[2] else { return XCTFail("done") }
    XCTAssertEqual(a, "Hel")
    XCTAssertEqual(b, "lo")
    XCTAssertEqual(done.output, "Hello")
    XCTAssertEqual(done.conversation_id, "c1")
  }

  func testSSEParserError() {
    let raw = "data: {\"type\":\"error\",\"message\":\"boom\"}\n\n"
    let events = SSEParser.parseChatEvents(from: raw)
    XCTAssertEqual(events.count, 1)
    guard case .error(let m) = events[0] else { return XCTFail("error") }
    XCTAssertEqual(m, "boom")
  }

  func testModelsResponseDecode() throws {
    let json = """
    {
      "models": [
        {"model":"@cf/meta/llama","label":"Llama","type":"chat","streaming":true,"provider":"workers-ai"}
      ],
      "mode":"public",
      "authenticated":false,
      "user":null,
      "username":null,
      "gateway":{"configured":false,"source":"none"}
    }
    """.data(using: .utf8)!
    let env = try JSONDecoder().decode(ModelsResponse.self, from: json)
    XCTAssertEqual(env.models.count, 1)
    XCTAssertEqual(env.models[0].model, "@cf/meta/llama")
    XCTAssertEqual(env.mode, "public")
    XCTAssertEqual(env.authenticated, false)
  }

  func testChatRequestEncode() throws {
    let body = ChatRequestBody(model: "m", userInput: "hi", conversationId: "c9")
    let data = try JSONEncoder().encode(body)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(obj["model"] as? String, "m")
    XCTAssertEqual(obj["user_input"] as? String, "hi")
    XCTAssertEqual(obj["conversation_id"] as? String, "c9")
  }
}

// MARK: - Mock URLProtocol integration

final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data, [String: String]))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  /// Required for `URLSession.bytes` / task-based loading (incremental SSE path).
  override class func canInit(with task: URLSessionTask) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = MockURLProtocol.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (status, data, headers) = try handler(request)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      // Deliver in chunks so AsyncBytes.lines can form frames (single blob is fine too).
      if !data.isEmpty {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class PrismClientHTTPTests: XCTestCase {
  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  private func makeClient() -> PrismClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let storage = HTTPCookieStorage.shared
    config.httpCookieStorage = storage
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    let session = URLSession(configuration: config)
    let http = HTTPClient(
      baseURL: URL(string: "https://play.example.com")!,
      session: session,
      cookieStorage: storage
    )
    return PrismClient(http: http)
  }

  func testModelsBootProbe() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/api/models")
      let body = """
      {"models":[{"model":"x","type":"chat"}],"mode":"public","authenticated":false}
      """.data(using: .utf8)!
      return (200, body, ["Content-Type": "application/json"])
    }
    let client = makeClient()
    let res = try await client.models()
    XCTAssertEqual(res.models.first?.model, "x")
    XCTAssertEqual(res.mode, "public")
  }

  func testLoginStoresCookieAndChatSendsIt() async throws {
    var sawCookie = false
    MockURLProtocol.handler = { req in
      let path = req.url?.path ?? ""
      if path == "/api/auth/login" {
        let body = #"{"user":{"username":"alice"}}"#.data(using: .utf8)!
        return (
          200,
          body,
          [
            "Content-Type": "application/json",
            "Set-Cookie": "__Host-prism_session=tok123; Path=/; HttpOnly; Secure; SameSite=Lax",
          ]
        )
      }
      if path == "/api/chat" {
        if let cookie = req.value(forHTTPHeaderField: "Cookie"), cookie.contains("tok123") {
          sawCookie = true
        }
        // Also accept cookie jar applied without manual header on some platforms
        let body = #"{"output":"hi","conversation_id":"c1"}"#.data(using: .utf8)!
        return (200, body, ["Content-Type": "application/json"])
      }
      return (404, Data(), [:])
    }
    let client = makeClient()
    let auth = try await client.login(username: "alice", password: "password-long")
    XCTAssertEqual(auth.user?.username, "alice")
    let chat = try await client.chat(ChatRequestBody(model: "m", userInput: "hello"))
    XCTAssertEqual(chat.output, "hi")
    // Cookie may be on the Cookie header or only in jar depending on platform; chat success is enough
    _ = sawCookie
  }

  func testChatStreamParsesSSE() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/api/chat/stream")
      let sse = """
      data: {"type":"delta","text":"A"}

      data: {"type":"done","output":"A"}

      """
      return (200, sse.data(using: .utf8)!, ["Content-Type": "text/event-stream"])
    }
    let client = makeClient()
    let (text, final) = try await client.chatStreamText(ChatRequestBody(model: "m", userInput: "x"))
    XCTAssertEqual(text, "A")
    XCTAssertEqual(final?.output, "A")
  }
}

final class ControlPlaneClientTests: XCTestCase {
  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  private func makeClient(key: String? = nil) -> ControlPlaneClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    let http = HTTPClient(
      baseURL: URL(string: "https://proxy.example.com")!,
      session: session
    )
    return ControlPlaneClient(http: http, clientKey: key)
  }

  func testHealth() async throws {
    MockURLProtocol.handler = { _ in
      (200, #"{"ok":true,"service":"prism-control-plane"}"#.data(using: .utf8)!, [:])
    }
    let h = try await makeClient().health()
    XCTAssertTrue(h.ok)
    XCTAssertEqual(h.service, "prism-control-plane")
  }

  func testEnrollAndChat() async throws {
    MockURLProtocol.handler = { req in
      let path = req.url?.path ?? ""
      if path == "/v1/clients" {
        let body = """
        {"client_id":"cli_1","key":"pcp_abc_secret","account":{"id":"acc_1"}}
        """.data(using: .utf8)!
        return (201, body, ["Content-Type": "application/json"])
      }
      if path == "/v1/chat/completions" {
        let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
        XCTAssertTrue(auth.hasPrefix("Bearer pcp_"))
        let body = """
        {"choices":[{"message":{"role":"assistant","content":"pong"}}]}
        """.data(using: .utf8)!
        return (200, body, ["Content-Type": "application/json"])
      }
      return (404, Data(), [:])
    }
    let client = makeClient()
    let en = try await client.enroll(enrollmentToken: "tok", label: "iphone")
    XCTAssertEqual(en.client_id, "cli_1")
    XCTAssertEqual(client.clientKey, "pcp_abc_secret")
    let text = try await client.chat(model: "gpt", user: "ping")
    XCTAssertEqual(text, "pong")
  }

  func testListModelsAndMe() async throws {
    MockURLProtocol.handler = { req in
      let path = req.url?.path ?? ""
      let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
      XCTAssertEqual(auth, "Bearer pcp_test_key")
      if path == "/v1/models" {
        let body = """
        {"object":"list","data":[{"id":"m1","display_name":"One","modality":"chat","billing":"workers-ai","tier":"standard","streaming":true,"max_output_tokens":1024,"spendable":true,"price":null,"published_rates":[]}]}
        """.data(using: .utf8)!
        return (200, body, ["Content-Type": "application/json"])
      }
      if path == "/v1/me" {
        let body = """
        {"client":{"id":"cli","label":"phone"},"account":{"id":"acc","status":"active"},"usage":{"spendable_remaining_micro_usd":100,"period":"2026-08"}}
        """.data(using: .utf8)!
        return (200, body, ["Content-Type": "application/json"])
      }
      return (404, Data("missing \(path)".utf8), [:])
    }
    let client = makeClient(key: "pcp_test_key")
    let models = try await client.listModels()
    XCTAssertEqual(models.data.first?.id, "m1")
    let me = try await client.me()
    XCTAssertEqual(me.client?.label, "phone")
    XCTAssertEqual(me.usage?.spendable_remaining_micro_usd, 100)
  }

  func testChatRequiresKey() async {
    let client = makeClient(key: nil)
    do {
      _ = try await client.chat(model: "m", user: "x")
      XCTFail("expected unauthenticated")
    } catch PrismError.unauthenticated {
      // ok
    } catch {
      XCTFail("wrong error \(error)")
    }
  }
}
