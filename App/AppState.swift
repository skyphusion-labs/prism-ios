import Foundation
import PrismKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// In-memory chat turn for the shell UI.
struct ChatTurn: Identifiable, Equatable {
  let id: UUID
  let role: Role
  var text: String

  enum Role: String, Equatable {
    case user
    case assistant
    case system
  }

  init(id: UUID = UUID(), role: Role, text: String) {
    self.id = id
    self.role = role
    self.text = text
  }
}

/// Which inference backend the app talks to.
enum BackendKind: String, CaseIterable, Identifiable {
  case playground
  case controlPlane

  var id: String { rawValue }

  var title: String {
    switch self {
    case .playground: return "Playground"
    case .controlPlane: return "Control plane"
    }
  }
}

@MainActor
final class AppState: ObservableObject {
  // MARK: - Backend

  @Published var backend: BackendKind = .playground

  /// Playground base URL (public or self-host).
  @Published var baseURLString: String = PrismClient.playBaseURL.absoluteString
  /// Control plane origin (`play-proxy.skyphusion.org`).
  @Published var controlPlaneURLString: String = ControlPlaneClient.productionBaseURL.absoluteString

  // MARK: - Auth (playground public)

  @Published var username: String = ""
  @Published var password: String = ""
  @Published var authenticated: Bool = false
  @Published var sessionUsername: String?

  // MARK: - Control plane device key

  @Published var enrollmentToken: String = ""
  @Published var deviceKeyPresent: Bool = false
  @Published var planeClientLabel: String?
  @Published var planeBalance: String?

  // MARK: - Catalog

  @Published var models: [ModelEntry] = []
  @Published var selectedModelId: String?
  @Published var authMode: String?

  // MARK: - Chat

  @Published var turns: [ChatTurn] = []
  @Published var draft: String = ""
  @Published var conversationId: String?
  @Published var useStream: Bool = true

  // MARK: - UI chrome

  @Published var isBusy: Bool = false
  @Published var banner: String?
  @Published var errorMessage: String?

  private let secrets: any SecretStore
  private var playground: PrismClient
  private var controlPlane: ControlPlaneClient

  init(secrets: (any SecretStore)? = nil) {
    let store = secrets ?? SecretStores.default()
    self.secrets = store
    playground = PrismClient(baseURL: PrismClient.playBaseURL)
    controlPlane = ControlPlaneClient()
    loadPersisted()
    rebuildClients(clearSession: false)
  }

  var chatModels: [ModelEntry] {
    models.filter { ($0.type ?? "chat") == "chat" }
  }

  var selectedModel: ModelEntry? {
    chatModels.first { $0.model == selectedModelId } ?? chatModels.first
  }

  /// True when the current backend can chat (signed-in playground, or plane with key).
  var canChat: Bool {
    switch backend {
    case .playground:
      if authMode == "public" { return authenticated }
      return true
    case .controlPlane:
      return deviceKeyPresent
    }
  }

  /// Show first-party login for public playground only.
  var needsPlaygroundLogin: Bool {
    backend == .playground && authMode == "public" && !authenticated
  }

  /// Show enrollment when plane is selected without a stored device key.
  var needsPlaneEnroll: Bool {
    backend == .controlPlane && !deviceKeyPresent
  }

  // MARK: - Lifecycle

  func bootstrap() async {
    rebuildClients(clearSession: false)
    await refreshModels()
  }

  func loadPersisted() {
    if let raw = try? secrets.get(SecretStoreKeys.backendMode),
       let kind = BackendKind(rawValue: raw) {
      backend = kind
    }
    if let u = try? secrets.get(SecretStoreKeys.playgroundBaseURL), !u.isEmpty {
      baseURLString = u
    }
    if let u = try? secrets.get(SecretStoreKeys.controlPlaneBaseURL), !u.isEmpty {
      controlPlaneURLString = u
    }
    if let key = try? secrets.get(SecretStoreKeys.controlPlaneDeviceKey), !key.isEmpty {
      controlPlane.setClientKey(key)
      deviceKeyPresent = true
    } else {
      deviceKeyPresent = false
    }
  }

  func persistSettings() {
    try? secrets.set(backend.rawValue, for: SecretStoreKeys.backendMode)
    try? secrets.set(baseURLString, for: SecretStoreKeys.playgroundBaseURL)
    try? secrets.set(controlPlaneURLString, for: SecretStoreKeys.controlPlaneBaseURL)
  }

  func rebuildClients(clearSession: Bool = true) {
    let playURL =
      URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
      ?? PrismClient.playBaseURL
    playground = PrismClient(baseURL: playURL)

    let planeURL =
      URL(string: controlPlaneURLString.trimmingCharacters(in: .whitespacesAndNewlines))
      ?? ControlPlaneClient.productionBaseURL
    let existingKey = try? secrets.get(SecretStoreKeys.controlPlaneDeviceKey)
    controlPlane = ControlPlaneClient(baseURL: planeURL, clientKey: existingKey)
    deviceKeyPresent = existingKey.map { !$0.isEmpty } ?? false

    persistSettings()

    if clearSession {
      authenticated = false
      sessionUsername = nil
      conversationId = nil
      turns = []
      models = []
      planeBalance = nil
      planeClientLabel = nil
    }
  }

  func setBackend(_ kind: BackendKind) {
    backend = kind
    rebuildClients(clearSession: true)
    Task { await refreshModels() }
  }

  func refreshModels() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    switch backend {
    case .playground:
      await refreshPlaygroundModels()
    case .controlPlane:
      await refreshPlaneModels()
    }
  }

  private func refreshPlaygroundModels() async {
    do {
      let res = try await playground.models()
      models = res.models
      authMode = res.mode
      authenticated = res.authenticated == true
      sessionUsername = res.username
      pickDefaultModel()
      banner = statusBannerPlayground(from: res)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshPlaneModels() async {
    authMode = "control-plane"
    guard deviceKeyPresent else {
      models = []
      banner = "Control plane · no device key · enroll in Settings"
      return
    }
    do {
      let list = try await controlPlane.listModels()
      models = list.data.map { $0.asModelEntry() }
      pickDefaultModel()
      if let me = try? await controlPlane.me() {
        planeClientLabel = me.client?.label ?? me.client?.id
        planeBalance = me.usage?.balanceDescription
        banner = statusBannerPlane(modelCount: models.count, me: me)
      } else {
        banner = "Control plane · \(models.count) models"
      }
      authenticated = true
    } catch {
      errorMessage = error.localizedDescription
      banner = "Control plane · error loading models"
    }
  }

  private func pickDefaultModel() {
    if selectedModelId == nil || !chatModels.contains(where: { $0.model == selectedModelId }) {
      selectedModelId = chatModels.first(where: { $0.streaming == true })?.model
        ?? chatModels.first?.model
    }
  }

  private func statusBannerPlayground(from res: ModelsResponse) -> String {
    let mode = res.mode ?? "unknown"
    if res.authenticated == true {
      let who = res.username ?? res.user ?? "signed in"
      return "\(mode) · \(who) · \(res.models.count) models"
    }
    return "\(mode) · not signed in · \(res.models.count) models"
  }

  private func statusBannerPlane(modelCount: Int, me: MeResponse) -> String {
    let who = me.client?.label ?? me.client?.id ?? "device"
    let bal = me.usage?.balanceDescription ?? ""
    if bal.isEmpty {
      return "control-plane · \(who) · \(modelCount) models"
    }
    return "control-plane · \(who) · \(bal)"
  }

  // MARK: - Auth (playground)

  func login() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      let res = try await playground.login(username: username, password: password)
      sessionUsername = res.user?.username ?? username
      authenticated = true
      password = ""
      await refreshModels()
    } catch {
      errorMessage = error.localizedDescription
      authenticated = false
    }
  }

  func signup() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      let res = try await playground.signup(username: username, password: password)
      sessionUsername = res.user?.username ?? username
      authenticated = true
      password = ""
      await refreshModels()
    } catch {
      errorMessage = error.localizedDescription
      authenticated = false
    }
  }

  func logout() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    if backend == .playground {
      do {
        try await playground.logout()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
    authenticated = false
    sessionUsername = nil
    conversationId = nil
    turns = []
    await refreshModels()
  }

  // MARK: - Control plane enroll

  func enrollPlane() async {
    let token = enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      errorMessage = "Paste an enrollment token first."
      return
    }
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      rebuildClients(clearSession: false)
      #if canImport(UIKit)
      let label = UIDevice.current.name
      #else
      let label = "ios"
      #endif
      let res = try await controlPlane.enroll(
        enrollmentToken: token,
        label: label,
        platform: "ios"
      )
      try secrets.set(res.key, for: SecretStoreKeys.controlPlaneDeviceKey)
      deviceKeyPresent = true
      enrollmentToken = ""
      planeClientLabel = res.client_id
      await refreshModels()
    } catch {
      errorMessage = error.localizedDescription
      deviceKeyPresent = false
    }
  }

  /// Paste or type a full `pcp_…` device key (recovery / side-load).
  func saveDeviceKey(_ key: String) async {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("pcp_") else {
      errorMessage = "Device key must start with pcp_."
      return
    }
    do {
      try secrets.set(trimmed, for: SecretStoreKeys.controlPlaneDeviceKey)
      controlPlane.setClientKey(trimmed)
      deviceKeyPresent = true
      errorMessage = nil
      await refreshModels()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func clearDeviceKey() async {
    try? secrets.set(nil, for: SecretStoreKeys.controlPlaneDeviceKey)
    controlPlane.setClientKey(nil)
    deviceKeyPresent = false
    models = []
    planeBalance = nil
    planeClientLabel = nil
    turns = []
    conversationId = nil
    banner = "Control plane · device key cleared"
  }

  // MARK: - Chat

  func send() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    guard let model = selectedModel else {
      errorMessage = "Pick a chat model first."
      return
    }
    if !canChat {
      errorMessage =
        backend == .controlPlane
        ? "Enroll a device key before chatting on the control plane."
        : "Sign in (or sign up) before chatting on the public playground."
      return
    }

    draft = ""
    turns.append(ChatTurn(role: .user, text: text))
    let assistantId = UUID()
    turns.append(ChatTurn(id: assistantId, role: .assistant, text: ""))

    isBusy = true
    errorMessage = nil
    defer { isBusy = false }

    do {
      switch backend {
      case .playground:
        try await sendPlayground(model: model, userText: text, assistantId: assistantId)
      case .controlPlane:
        try await sendPlane(model: model, assistantId: assistantId)
      }
    } catch {
      updateAssistant(id: assistantId, text: "(error) \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  private func sendPlayground(model: ModelEntry, userText: String, assistantId: UUID) async throws {
    let body = ChatRequestBody(
      model: model.model,
      userInput: userText,
      conversationId: conversationId
    )
    if useStream, model.streaming == true {
      var assembled = ""
      for try await event in playground.chatStreamEvents(body) {
        switch event {
        case .delta(let t):
          assembled += t
          updateAssistant(id: assistantId, text: assembled)
        case .done(let final):
          if let out = final.output, !out.isEmpty, assembled.isEmpty {
            updateAssistant(id: assistantId, text: out)
          } else if assembled.isEmpty {
            updateAssistant(id: assistantId, text: final.output ?? "")
          }
          if let cid = final.conversation_id { conversationId = cid }
        case .error(let m):
          throw PrismError.serverError(m)
        case .unknown:
          break
        }
      }
    } else {
      let res = try await playground.chat(body)
      updateAssistant(id: assistantId, text: res.output ?? "")
      if let cid = res.conversation_id { conversationId = cid }
    }
  }

  private func sendPlane(model: ModelEntry, assistantId: UUID) async throws {
    // Build OpenAI-style messages from transcript (exclude empty assistant bubble).
    var messages: [ControlPlaneChatMessage] = []
    for turn in turns where turn.id != assistantId {
      switch turn.role {
      case .user:
        messages.append(ControlPlaneChatMessage(role: "user", content: turn.text))
      case .assistant:
        if !turn.text.isEmpty {
          messages.append(ControlPlaneChatMessage(role: "assistant", content: turn.text))
        }
      case .system:
        messages.append(ControlPlaneChatMessage(role: "system", content: turn.text))
      }
    }

    if useStream, model.streaming == true {
      var assembled = ""
      let body = ControlPlaneChatRequest(model: model.model, messages: messages, stream: true)
      for try await event in controlPlane.chatCompletionsStream(body) {
        switch event {
        case .delta(let t):
          assembled += t
          updateAssistant(id: assistantId, text: assembled)
        case .done(let final):
          if assembled.isEmpty, let out = final.output, !out.isEmpty {
            updateAssistant(id: assistantId, text: out)
          }
        case .error(let m):
          throw PrismError.serverError(m)
        case .unknown:
          break
        }
      }
      if assembled.isEmpty,
         let i = turns.firstIndex(where: { $0.id == assistantId }),
         turns[i].text.isEmpty {
        throw PrismError.serverError("Empty stream completion")
      }
    } else {
      let text = try await controlPlane.chat(model: model.model, messages: messages)
      updateAssistant(id: assistantId, text: text)
    }

    // Refresh balance after a spend (best-effort; stream omits money headers).
    if let me = try? await controlPlane.me() {
      planeBalance = me.usage?.balanceDescription
      banner = statusBannerPlane(modelCount: models.count, me: me)
    }
  }

  private func updateAssistant(id: UUID, text: String) {
    guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
    turns[i].text = text
  }

  func clearChat() {
    turns = []
    conversationId = nil
  }
}
