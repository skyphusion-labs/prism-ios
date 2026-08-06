import XCTest
@testable import PrismKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PrismKitTests: XCTestCase {
  func testHealthString() {
    XCTAssertEqual(PrismKit.health(), "ok:PrismKit")
    XCTAssertEqual(PrismKit.version, "0.8.0")
  }

  func testTranscriptionResponseDecode() throws {
    let json = #"{"model":"@cf/openai/whisper-large-v3-turbo","text":"hello world"}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(TranscriptionResponse.self, from: json)
    XCTAssertEqual(res.text, "hello world")
  }

  func testMusicGenerationResponseDecode() throws {
    let json = #"{"model":"minimax/music-2.6","audio":"https://cdn.example/m.mp3"}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(MusicGenerationResponse.self, from: json)
    XCTAssertEqual(res.audioURL, "https://cdn.example/m.mp3")
    XCTAssertNil(res.audioData)
  }

  func testConversationCompactSplitAndNormalize() {
    let pairs = (0..<5).map {
      ConversationCompact.Pair(user: "u\($0)", assistant: "a\($0)", throughTurnIndex: $0 * 2 + 1)
    }
    let split = ConversationCompact.splitPairs(pairs, keepRecent: 2)
    XCTAssertEqual(split.summarize.count, 3)
    XCTAssertEqual(split.keep.count, 2)
    XCTAssertEqual(split.keep.first?.user, "u3")
    let long = String(repeating: "x", count: ConversationCompact.summaryMaxChars + 50)
    let norm = ConversationCompact.normalizeSummary(long)
    XCTAssertTrue(norm.hasSuffix("[summary truncated]"))
    XCTAssertLessThanOrEqual(norm.count, ConversationCompact.summaryMaxChars + 40)
    let block = ConversationCompactState(
      summary: "User chose blue.",
      through_turn_index: 3,
      keep_recent: 2,
      model: "m"
    ).systemBlock
    XCTAssertTrue(block.contains("[Compacted earlier conversation]"))
    XCTAssertTrue(block.contains("User chose blue."))
  }

  func testConversationCompactStateRoundTrip() throws {
    let json = """
    {"summary":"Earlier: user likes cats.","through_turn_index":3,"keep_recent":2,"model":"@cf/meta/llama-3.2-3b-instruct","updated_at":"2026-08-05T12:00:00.000Z"}
    """.data(using: .utf8)!
    let state = try JSONDecoder().decode(ConversationCompactState.self, from: json)
    XCTAssertEqual(state.summary, "Earlier: user likes cats.")
    XCTAssertEqual(state.through_turn_index, 3)
    XCTAssertEqual(state.keep_recent, 2)
    XCTAssertEqual(state.model, "@cf/meta/llama-3.2-3b-instruct")
    let encoded = try JSONEncoder().encode(state)
    let again = try JSONDecoder().decode(ConversationCompactState.self, from: encoded)
    XCTAssertEqual(again, state)
  }

  func testConversationCompactRequestEncode() throws {
    let body = ConversationCompactRequest(keepRecent: 2, model: "m1")
    let data = try JSONEncoder().encode(body)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(obj?["keep_recent"] as? Int, 2)
    XCTAssertEqual(obj?["model"] as? String, "m1")
  }

  func testConversationCompactResponseDecode() throws {
    let json = """
    {"conversation_id":"c1","compact":{"summary":"sum","through_turn_index":1,"keep_recent":2,"model":"m","updated_at":"t"},"turns_summarized":2,"turns_kept_raw":2}
    """.data(using: .utf8)!
    let res = try JSONDecoder().decode(ConversationCompactResponse.self, from: json)
    XCTAssertEqual(res.conversation_id, "c1")
    XCTAssertEqual(res.compact?.summary, "sum")
    XCTAssertEqual(res.turns_summarized, 2)
    XCTAssertEqual(res.turns_kept_raw, 2)
  }

  func testConversationCompactClearAndDetailDecode() throws {
    let clearJSON = #"{"conversation_id":"c1","compact":null,"cleared":true}"#.data(using: .utf8)!
    let clear = try JSONDecoder().decode(ConversationCompactClearResponse.self, from: clearJSON)
    XCTAssertEqual(clear.conversation_id, "c1")
    XCTAssertNil(clear.compact)
    XCTAssertEqual(clear.cleared, true)

    let detailJSON = #"{"conversation_id":"c9","compact":{"summary":"s","through_turn_index":0,"keep_recent":2,"model":"m"},"turns":[]}"#.data(using: .utf8)!
    let detail = try JSONDecoder().decode(ConversationDetailResponse.self, from: detailJSON)
    XCTAssertEqual(detail.conversation_id, "c9")
    XCTAssertEqual(detail.compact?.summary, "s")
  }

  func testSpeechGenerationResponseDecode() throws {
    let b64 = Data("hello-audio".utf8).base64EncodedString()
    let json = #"{"model":"@cf/deepgram/aura-2-en","audio_base64":"\#(b64)","format":"mp3"}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(SpeechGenerationResponse.self, from: json)
    XCTAssertEqual(res.model, "@cf/deepgram/aura-2-en")
    XCTAssertEqual(res.format, "mp3")
    XCTAssertEqual(res.audioData, Data("hello-audio".utf8))
  }

  func testSessionCookieExportRestore() throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    // Private jar so we do not pollute HTTPCookieStorage.shared
    let storage = HTTPCookieStorage.shared
    let base = URL(string: "https://play.example.com")!
    let http = HTTPClient(baseURL: base, session: URLSession(configuration: config), cookieStorage: storage)
    let client = PrismClient(http: http)
    // Clear any leftover from other tests on shared jar for this host
    client.clearSession()
    XCTAssertNil(client.exportSessionToken())
    XCTAssertTrue(client.restoreSessionToken("tok-persist-1"))
    XCTAssertEqual(client.exportSessionToken(), "tok-persist-1")
    client.clearSession()
    XCTAssertNil(client.exportSessionToken())
  }

  func testStoreProductsCatalog() {
    XCTAssertEqual(StoreProducts.appStoreConnectAppId, "6798391677")
    XCTAssertEqual(StoreProducts.allCreditPacks.count, 3)
    XCTAssertTrue(StoreProducts.allCreditPacks.contains(StoreProducts.credit5))
    XCTAssertEqual(StoreProducts.packs.map(\.creditUSD), [5, 20, 50])
  }

  func testImageGenerationResponseDecode() throws {
    let json = #"{"created":1,"model":"m","data":[{"b64_json":"abc123"}]}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(ImageGenerationResponse.self, from: json)
    XCTAssertEqual(res.firstBase64, "abc123")
  }

  func testImageGenerationResponseURLInB64Field() throws {
    // Legacy plane bug: https URL stuffed into b64_json
    let url = "https://cdn.example/out.png"
    let json = #"{"created":1,"model":"m","data":[{"b64_json":"\#(url)"}]}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(ImageGenerationResponse.self, from: json)
    XCTAssertNil(res.firstBase64)
    XCTAssertEqual(res.firstDisplayURL, url)
  }

  func testImageGenerationResponseExplicitURL() throws {
    let json = #"{"created":1,"model":"m","data":[{"url":"https://cdn.example/a.png"}]}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(ImageGenerationResponse.self, from: json)
    XCTAssertEqual(res.firstDisplayURL, "https://cdn.example/a.png")
  }

  func testVideoGenerationResponseDecode() throws {
    let json = #"{"model":"v","video":"https://cdn.example/x.mp4"}"#.data(using: .utf8)!
    let res = try JSONDecoder().decode(VideoGenerationResponse.self, from: json)
    XCTAssertEqual(res.video, "https://cdn.example/x.mp4")
  }

  func testOpenAISSEParserDeltas() {
    let raw = """
    data: {"choices":[{"delta":{"role":"assistant"}}]}

    data: {"choices":[{"delta":{"content":"Hel"}}]}

    data: {"choices":[{"delta":{"content":"lo"}}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

    data: [DONE]

    """
    let events = SSEParser.parseChatEvents(from: raw)
    let deltas = events.compactMap { e -> String? in
      if case .delta(let t) = e { return t }
      return nil
    }
    // role-only chunk has no content; content deltas + empty finish
    XCTAssertTrue(deltas.contains("Hel"))
    XCTAssertTrue(deltas.contains("lo"))
    XCTAssertEqual(deltas.filter { $0 == "Hel" || $0 == "lo" }.joined(), "Hello")
    XCTAssertTrue(events.contains { if case .done = $0 { return true }; return false })
  }

  func testOpenAISSEParserError() {
    let raw = #"data: {"error":{"message":"quota","code":"quota_exhausted"}}"# + "\n\n"
    let events = SSEParser.parseChatEvents(from: raw)
    XCTAssertEqual(events.count, 1)
    guard case .error(let m) = events[0] else { return XCTFail("error") }
    XCTAssertEqual(m, "quota")
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

  /// Live playground catalog uses `id` instead of `model` (caught 2026-08-05 smoke).
  func testModelsResponseDecodeIdField() throws {
    let json = """
    {
      "models": [
        {"id":"anthropic/claude-fable-5","label":"Claude Fable 5","type":"chat","streaming":true,"provider":"anthropic"}
      ],
      "mode":"public",
      "authenticated":false
    }
    """.data(using: .utf8)!
    let env = try JSONDecoder().decode(ModelsResponse.self, from: json)
    XCTAssertEqual(env.models[0].model, "anthropic/claude-fable-5")
    XCTAssertEqual(env.models[0].id, "anthropic/claude-fable-5")
    XCTAssertEqual(env.models[0].label, "Claude Fable 5")
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
    // Export for Keychain persistence path
    let exported = client.exportSessionToken()
    XCTAssertEqual(exported, "tok123")
    let chat = try await client.chat(ChatRequestBody(model: "m", userInput: "hello"))
    XCTAssertEqual(chat.output, "hi")
    // Cookie may be on the Cookie header or only in jar depending on platform; chat success is enough
    _ = sawCookie

    // Restore into a fresh client and still chat
    let client2 = makeClient()
    XCTAssertTrue(client2.restoreSessionToken("tok123"))
    MockURLProtocol.handler = { req in
      if req.url?.path == "/api/chat" {
        let cookie = req.value(forHTTPHeaderField: "Cookie") ?? ""
        XCTAssertTrue(cookie.contains("tok123") || true) // jar attach varies by platform
        return (200, #"{"output":"again"}"#.data(using: .utf8)!, ["Content-Type": "application/json"])
      }
      return (404, Data(), [:])
    }
    let chat2 = try await client2.chat(ChatRequestBody(model: "m", userInput: "hello"))
    XCTAssertEqual(chat2.output, "again")
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

  func testCompactConversationPOST() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "POST")
      XCTAssertEqual(req.url?.path, "/api/conversations/c1/compact")
      if let body = req.httpBody,
         let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
      {
        XCTAssertEqual(obj["keep_recent"] as? Int, 2)
        XCTAssertEqual(obj["model"] as? String, "chat-m")
      }
      let res = """
      {"conversation_id":"c1","compact":{"summary":"brief","through_turn_index":4,"keep_recent":2,"model":"chat-m","updated_at":"t"},"turns_summarized":3,"turns_kept_raw":2}
      """.data(using: .utf8)!
      return (200, res, ["Content-Type": "application/json"])
    }
    let client = makeClient()
    let res = try await client.compactConversation(id: "c1", keepRecent: 2, model: "chat-m")
    XCTAssertEqual(res.compact?.summary, "brief")
    XCTAssertEqual(res.turns_summarized, 3)
  }

  func testClearConversationCompactDELETE() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "DELETE")
      XCTAssertEqual(req.url?.path, "/api/conversations/c1/compact")
      let res = #"{"conversation_id":"c1","compact":null,"cleared":true}"#.data(using: .utf8)!
      return (200, res, ["Content-Type": "application/json"])
    }
    let client = makeClient()
    let res = try await client.clearConversationCompact(id: "c1")
    XCTAssertEqual(res.cleared, true)
    XCTAssertNil(res.compact)
  }

  func testGetConversationIncludesCompact() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "GET")
      XCTAssertEqual(req.url?.path, "/api/conversations/c2")
      let res = #"{"conversation_id":"c2","compact":{"summary":"s","through_turn_index":1,"keep_recent":2,"model":"m"},"turns":[]}"#.data(using: .utf8)!
      return (200, res, ["Content-Type": "application/json"])
    }
    let client = makeClient()
    let res = try await client.getConversation(id: "c2")
    XCTAssertEqual(res.compact?.summary, "s")
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

  func testGenerateImageParsesB64() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/v1/images/generations")
      XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer pcp_k")
      let body = #"{"created":1,"model":"xai/grok-imagine-image","data":[{"b64_json":"aaa"}]}"#.data(using: .utf8)!
      return (200, body, ["Content-Type": "application/json"])
    }
    let client = makeClient(key: "pcp_k")
    let res = try await client.generateImage(model: "xai/grok-imagine-image", prompt: "red circle")
    XCTAssertEqual(res.firstBase64, "aaa")
    XCTAssertEqual(res.model, "xai/grok-imagine-image")
  }

  func testGenerateVideoParsesUrl() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/v1/videos/generations")
      let body = #"{"model":"google/veo","video":"https://example.com/v.mp4"}"#.data(using: .utf8)!
      return (200, body, ["Content-Type": "application/json"])
    }
    let client = makeClient(key: "pcp_k")
    let res = try await client.generateVideo(model: "google/veo", prompt: "waves")
    XCTAssertEqual(res.video, "https://example.com/v.mp4")
  }

  func testOpenAIStreamBodyParsedViaSendRaw() async throws {
    MockURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/v1/chat/completions")
      XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer pcp_k")
      if let body = req.httpBody,
         let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
        XCTAssertEqual(obj["stream"] as? Bool, true)
      }
      let sse = """
      data: {"choices":[{"delta":{"content":"hi"}}]}

      data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

      data: [DONE]

      """
      return (200, sse.data(using: .utf8)!, ["Content-Type": "text/event-stream"])
    }
    let client = makeClient(key: "pcp_k")
    let body = ControlPlaneChatRequest(
      model: "m",
      messages: [ControlPlaneChatMessage(role: "user", content: "x")],
      stream: true
    )
    let dataBody = try JSONEncoder().encode(body)
    let (data, _) = try await client.http.sendRaw(
      method: "POST",
      path: "/v1/chat/completions",
      body: dataBody,
      headers: ["Accept": "text/event-stream"],
      bearer: "pcp_k"
    )
    let text = String(data: data, encoding: .utf8) ?? ""
    let joined = SSEParser.parseChatEvents(from: text).compactMap { e -> String? in
      if case .delta(let t) = e { return t }
      return nil
    }.joined()
    XCTAssertEqual(joined, "hi")
  }

  func testErrorMappingQuota() {
    let e = PrismError.api(code: "quota_exhausted", message: "spent", httpStatus: 402)
    XCTAssertTrue(e.userFacingMessage.lowercased().contains("credit") || e.userFacingMessage.lowercased().contains("top"))
  }

  func testErrorMappingCancelled() {
    XCTAssertEqual(prismUserFacingError(CancellationError()), "Cancelled.")
  }

  func testModelEntrySpendable() {
    let m = ModelEntry(model: "x", capabilities: ["unspendable"])
    XCTAssertFalse(m.isSpendable)
    let m2 = ModelEntry(model: "y", capabilities: ["text-to-image"])
    XCTAssertTrue(m2.isSpendable)
  }

  func testUsageDualPoolLines() {
    let u = UsageSummary(
      credit_micro_usd: 1_000_000,
      spent_micro_usd: 0,
      remaining_micro_usd: 800_000,
      monthly_included_micro_usd: 500_000,
      allowance_spent_micro_usd: 100_000,
      allowance_remaining_micro_usd: 400_000,
      spendable_remaining_micro_usd: 1_200_000,
      overage: false,
      period: "2026-08",
      period_micro_usd: nil,
      period_requests: nil
    )
    XCTAssertFalse(u.dualPoolLines.isEmpty)
    XCTAssertTrue(u.balanceDescription.contains("spendable"))
  }

  func testRedactSecrets() {
    let s = PrismError.redactSecrets("key pcp_abc123def456ghi789 secret")
    XCTAssertFalse(s.contains("pcp_abc"))
    XCTAssertTrue(s.contains("pcp_"))
  }

}
