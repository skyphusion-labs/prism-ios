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

  public func me() async throws -> AccountSummary {
    let key = try requireKey()
    return try await http.sendJSON(method: "GET", path: "/v1/clients/me", bearer: key)
  }

  // MARK: - Inference

  public func chatCompletions(_ body: ControlPlaneChatRequest) async throws -> ControlPlaneChatResponse {
    let key = try requireKey()
    let res: ControlPlaneChatResponse = try await http.sendJSON(
      method: "POST",
      path: "/v1/chat/completions",
      body: body,
      bearer: key
    )
    if let err = res.error {
      throw PrismError.serverError(err.message ?? err.code ?? "control plane error")
    }
    return res
  }

  /// Simple single-turn helper.
  public func chat(model: String, user: String, system: String? = nil) async throws -> String {
    var messages: [ControlPlaneChatMessage] = []
    if let system, !system.isEmpty {
      messages.append(ControlPlaneChatMessage(role: "system", content: system))
    }
    messages.append(ControlPlaneChatMessage(role: "user", content: user))
    let res = try await chatCompletions(ControlPlaneChatRequest(model: model, messages: messages))
    guard let text = res.firstContent, !text.isEmpty else {
      throw PrismError.serverError("Empty completion")
    }
    return text
  }
}
