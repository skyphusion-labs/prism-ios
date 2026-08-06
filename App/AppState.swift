import Foundation
import PrismKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// In-memory chat turn for the shell UI.
///
/// Context is **client-side**: every send rebuilds the OpenAI message list from
/// `turns` (plane) or reuses `conversationId` (playground). Switching
/// `selectedModelId` never clears turns -- same chat, next model.
struct ChatTurn: Identifiable, Equatable {
  let id: UUID
  let role: Role
  var text: String
  /// Model that produced this assistant turn (nil for user / system).
  var modelId: String?
  var modelLabel: String?

  enum Role: String, Equatable {
    case user
    case assistant
    case system
  }

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    modelId: String? = nil,
    modelLabel: String? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.modelId = modelId
    self.modelLabel = modelLabel
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

  /// Product default is control plane; playground lives under Settings → Developer.
  @Published var backend: BackendKind = .controlPlane
  /// When false (default), Settings hides playground/URL tinkering.
  @Published var showDeveloperSettings: Bool = false

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
  /// Dual-pool detail lines for Settings.
  @Published var planeUsageLines: [String] = []
  @Published var modelSearch: String = ""
  /// Hide unspendable models in pickers (default on for plane).
  @Published var hideUnspendable: Bool = true

  // MARK: - Catalog

  @Published var models: [ModelEntry] = []
  @Published var selectedModelId: String?
  @Published var selectedImageModelId: String?
  @Published var selectedVideoModelId: String?
  @Published var authMode: String?

  // MARK: - Chat

  @Published var turns: [ChatTurn] = []
  @Published var draft: String = ""
  @Published var conversationId: String?
  @Published var useStream: Bool = true

  // MARK: - Image / video (control plane)

  @Published var imagePrompt: String = ""
  /// Optional reference image (https or data:) for i2i / edit models.
  @Published var imageImageRef: String = ""
  @Published var lastImageBase64: String?
  @Published var lastImageURL: String?
  @Published var lastImageModel: String?
  @Published var videoPrompt: String = ""
  /// Optional i2v still: data URL or https URL.
  @Published var videoImageRef: String = ""
  @Published var lastVideoURL: String?
  @Published var lastVideoModel: String?
  @Published var mediaBusy: Bool = false
  @Published var mediaError: String?
  @Published var mediaStatus: String?

  // MARK: - UI chrome

  @Published var isBusy: Bool = false
  @Published var banner: String?
  @Published var errorMessage: String?

  private let secrets: any SecretStore
  private var playground: PrismClient
  private var controlPlane: ControlPlaneClient
  private var chatTask: Task<Void, Never>?
  private var mediaTask: Task<Void, Never>?

  init(secrets: (any SecretStore)? = nil) {
    let store = secrets ?? SecretStores.default()
    self.secrets = store
    playground = PrismClient(baseURL: PrismClient.playBaseURL)
    controlPlane = ControlPlaneClient()
    loadPersisted()
    rebuildClients(clearSession: false)
  }

  private func appliesSpendableFilter(_ m: ModelEntry) -> Bool {
    if backend != .controlPlane || !hideUnspendable { return true }
    return m.isSpendable
  }

  private func matchesSearch(_ m: ModelEntry) -> Bool {
    let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return true }
    let hay = "\(m.label ?? "") \(m.model) \(m.provider ?? "") \(m.group ?? "")".lowercased()
    return hay.contains(q)
  }

  var chatModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "chat") == "chat" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { ($0.label ?? $0.model) < ($1.label ?? $1.model) }
  }

  var imageModels: [ModelEntry] {
    // Pure t2i first (prompt-only), then dual i2i (+ref), then i2i-required.
    models
      .filter { ($0.type ?? "") == "image" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { a, b in
        let ar = imageRefRank(a)
        let br = imageRefRank(b)
        if ar != br { return ar < br }
        return (a.label ?? a.model) < (b.label ?? b.model)
      }
  }

  /// 0 = pure t2i, 1 = optional ref (i2i dual), 2 = ref required.
  private func imageRefRank(_ m: ModelEntry) -> Int {
    let caps = m.capabilities ?? []
    if caps.contains("image-input-required") { return 2 }
    if caps.contains("image-input") { return 1 }
    return 0
  }

  var videoModels: [ModelEntry] {
    // Prefer working models first; Grok video last (ZDR path needs plane 0.4.14+).
    models
      .filter { ($0.type ?? "") == "video" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { a, b in
        let ag = a.model.hasPrefix("xai/grok-imagine-video")
        let bg = b.model.hasPrefix("xai/grok-imagine-video")
        if ag != bg { return !ag && bg }
        return (a.label ?? a.model) < (b.label ?? b.model)
      }
  }

  /// All chat models ignoring search filter (selection must survive search/filter).
  var allChatModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "chat") == "chat" }
      .filter(appliesSpendableFilter)
  }

  /// Resolve the selected chat model from the **full** chat catalog, not the search-filtered list.
  /// Falling back to `chatModels.first` would send with a wrong model when the user is searching.
  var selectedModel: ModelEntry? {
    if let id = selectedModelId,
       let m = allChatModels.first(where: { $0.model == id })
        ?? models.first(where: { $0.model == id && ($0.type ?? "chat") == "chat" })
    {
      return m
    }
    return allChatModels.first ?? chatModels.first
  }

  /// Number of completed user/assistant pairs (context depth).
  var chatContextTurnCount: Int {
    turns.filter { $0.role == .user || ($0.role == .assistant && !$0.text.isEmpty) }.count
  }

  /// Change chat model without clearing transcript (web parity: switch model, keep context).
  func selectChatModel(_ modelId: String) {
    guard models.contains(where: { $0.model == modelId && ($0.type ?? "chat") == "chat" })
            || modelId.isEmpty
    else { return }
    // Never clear turns / conversationId here -- that is only newChat().
    selectedModelId = modelId.isEmpty ? nil : modelId
  }

  var selectedImageModel: ModelEntry? {
    // Do not silently fall back to first model when picker id is stale (wrong model bug).
    if let id = selectedImageModelId, let m = imageModels.first(where: { $0.model == id }) {
      return m
    }
    return imageModels.first
  }

  var selectedVideoModel: ModelEntry? {
    if let id = selectedVideoModelId, let m = videoModels.first(where: { $0.model == id }) {
      return m
    }
    return videoModels.first
  }

  /// Image/video doors are control-plane only.
  var canUseMediaDoors: Bool {
    backend == .controlPlane && deviceKeyPresent
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
    } else {
      // First launch: commercial plane, not playground lab mode.
      backend = .controlPlane
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
    if let dev = try? secrets.get("prism.showDeveloperSettings") {
      showDeveloperSettings = (dev == "1" || dev == "true")
    }
  }

  func persistSettings() {
    try? secrets.set(backend.rawValue, for: SecretStoreKeys.backendMode)
    try? secrets.set(baseURLString, for: SecretStoreKeys.playgroundBaseURL)
    try? secrets.set(controlPlaneURLString, for: SecretStoreKeys.controlPlaneBaseURL)
    try? secrets.set(showDeveloperSettings ? "1" : "0", for: "prism.showDeveloperSettings")
  }

  func setShowDeveloperSettings(_ on: Bool) {
    showDeveloperSettings = on
    persistSettings()
  }

  func rebuildClients(clearSession: Bool = true) {
    let playURL =
      URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
      ?? PrismClient.playBaseURL
    playground = PrismClient(baseURL: playURL)
    // Re-inject Keychain session into the new ephemeral jar (process restart / URL apply).
    if let token = try? secrets.get(SecretStoreKeys.playgroundSessionCookie), !token.isEmpty {
      _ = playground.restoreSessionToken(token)
    }
    if let who = try? secrets.get(SecretStoreKeys.playgroundSessionUsername), !who.isEmpty {
      sessionUsername = who
    }

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

  /// Persist playground session token + username after login/signup.
  private func persistPlaygroundSession(username: String?) {
    if let token = playground.exportSessionToken(), !token.isEmpty {
      try? secrets.set(token, for: SecretStoreKeys.playgroundSessionCookie)
    }
    if let username, !username.isEmpty {
      try? secrets.set(username, for: SecretStoreKeys.playgroundSessionUsername)
    }
  }

  /// Drop stored session when logout or cookie no longer accepted.
  private func clearPersistedPlaygroundSession() {
    try? secrets.set(nil, for: SecretStoreKeys.playgroundSessionCookie)
    try? secrets.set(nil, for: SecretStoreKeys.playgroundSessionUsername)
    playground.clearSession()
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
      if let u = res.username { sessionUsername = u }
      // Stale Keychain cookie: server says not signed in while we still hold a token.
      if res.authenticated != true, (try? secrets.get(SecretStoreKeys.playgroundSessionCookie)) != nil {
        clearPersistedPlaygroundSession()
      } else if res.authenticated == true {
        // Keep jar + Keychain in sync if Set-Cookie rotated (rare).
        persistPlaygroundSession(username: sessionUsername)
      }
      pickDefaultModel()
      banner = statusBannerPlayground(from: res)
    } catch {
      errorMessage = prismUserFacingError(error)
    }
  }

  private func refreshPlaneModels() async {
    authMode = "control-plane"
    guard deviceKeyPresent else {
      models = []
      planeUsageLines = []
      banner = "Control plane · no device key · enroll in Settings"
      return
    }
    do {
      let list = try await controlPlane.listModels()
      models = list.data.map { $0.asModelEntry() }
      pickDefaultModel()
      if let me = try? await controlPlane.me() {
        applyPlaneMe(me)
      } else {
        banner = "Control plane · \(models.count) models"
      }
      authenticated = true
    } catch {
      errorMessage = prismUserFacingError(error)
      banner = "Control plane · error loading models"
    }
  }

  private func applyPlaneMe(_ me: MeResponse) {
    planeClientLabel = me.client?.label ?? me.client?.id
    planeBalance = me.usage?.balanceDescription
    planeUsageLines = me.usage?.dualPoolLines ?? []
    banner = statusBannerPlane(modelCount: models.count, me: me)
  }

  private func pickDefaultModel() {
    if selectedModelId == nil || !chatModels.contains(where: { $0.model == selectedModelId }) {
      selectedModelId = chatModels.first(where: { $0.streaming == true })?.model
        ?? chatModels.first?.model
    }
    if selectedImageModelId == nil || !imageModels.contains(where: { $0.model == selectedImageModelId }) {
      // Prefer pure t2i for first run (flux-1-schnell); list is already pure-t2i first.
      selectedImageModelId = imageModels.first(where: { $0.model.contains("flux-1-schnell") })?.model
        ?? imageModels.first(where: {
          !($0.capabilities ?? []).contains("image-input")
        })?.model
        ?? imageModels.first?.model
    }
    if selectedVideoModelId == nil || !videoModels.contains(where: { $0.model == selectedVideoModelId }) {
      selectedVideoModelId = videoModels.first(where: { $0.model == "google/veo-3.1-fast" })?.model
        ?? videoModels.first(where: { $0.model.hasPrefix("google/veo") })?.model
        ?? videoModels.first(where: { $0.model == "bytedance/seedance-2.0-fast" })?.model
        ?? videoModels.first(where: {
          !$0.model.hasPrefix("minimax/hailuo") && !$0.model.hasPrefix("xai/grok-imagine-video")
        })?.model
        ?? videoModels.first?.model
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
      persistPlaygroundSession(username: sessionUsername)
      await refreshModels()
    } catch {
      errorMessage = prismUserFacingError(error)
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
      persistPlaygroundSession(username: sessionUsername)
      await refreshModels()
    } catch {
      errorMessage = prismUserFacingError(error)
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
        errorMessage = prismUserFacingError(error)
      }
      clearPersistedPlaygroundSession()
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
      errorMessage = prismUserFacingError(error)
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
      errorMessage = prismUserFacingError(error)
    }
  }

  func clearDeviceKey() async {
    try? secrets.set(nil, for: SecretStoreKeys.controlPlaneDeviceKey)
    controlPlane.setClientKey(nil)
    deviceKeyPresent = false
    models = []
    planeBalance = nil
    planeUsageLines = []
    planeClientLabel = nil
    turns = []
    conversationId = nil
    banner = "Control plane · device key cleared"
  }

  // MARK: - Chat

  func send() {
    chatTask?.cancel()
    chatTask = Task { await self.performSend() }
  }

  func cancelChat() {
    chatTask?.cancel()
    chatTask = nil
    isBusy = false
    if let last = turns.last, last.role == .assistant, last.text.isEmpty {
      updateAssistant(id: last.id, text: "(cancelled)")
    }
    errorMessage = PrismError.cancelled.userFacingMessage
  }

  private func performSend() async {
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
    // Stamp the model now so mid-stream picker changes do not relabel this reply.
    turns.append(
      ChatTurn(
        id: assistantId,
        role: .assistant,
        text: "",
        modelId: model.model,
        modelLabel: model.label ?? model.model
      )
    )

    isBusy = true
    errorMessage = nil
    defer { isBusy = false }

    do {
      try Task.checkCancellation()
      switch backend {
      case .playground:
        // Server keeps history under conversationId; model can change per turn.
        try await sendPlayground(model: model, userText: text, assistantId: assistantId)
      case .controlPlane:
        // Client resends full turns as messages; model is only the next completion's id.
        try await sendPlane(model: model, assistantId: assistantId)
      }
    } catch is CancellationError {
      updateAssistant(id: assistantId, text: "(cancelled)")
      errorMessage = PrismError.cancelled.userFacingMessage
    } catch {
      let msg = prismUserFacingError(error)
      updateAssistant(id: assistantId, text: "(error) \(msg)")
      errorMessage = msg
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
        try Task.checkCancellation()
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
      try Task.checkCancellation()
      updateAssistant(id: assistantId, text: res.output ?? "")
      if let cid = res.conversation_id { conversationId = cid }
    }
  }

  private func sendPlane(model: ModelEntry, assistantId: UUID) async throws {
    // Full transcript → messages. Prior turns may have been produced by other models;
    // that is intentional (same as play.skyphusion.org).
    var messages: [ControlPlaneChatMessage] = []
    for turn in turns where turn.id != assistantId {
      switch turn.role {
      case .user:
        guard !turn.text.isEmpty else { continue }
        messages.append(ControlPlaneChatMessage(role: "user", content: turn.text))
      case .assistant:
        // Skip empty / cancelled shells so the next model does not see noise.
        let t = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.hasPrefix("(cancelled)"), !t.hasPrefix("(error)") else { continue }
        messages.append(ControlPlaneChatMessage(role: "assistant", content: turn.text))
      case .system:
        guard !turn.text.isEmpty else { continue }
        messages.append(ControlPlaneChatMessage(role: "system", content: turn.text))
      }
    }

    if useStream, model.streaming == true {
      var assembled = ""
      let body = ControlPlaneChatRequest(model: model.model, messages: messages, stream: true)
      for try await event in controlPlane.chatCompletionsStream(body) {
        try Task.checkCancellation()
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
      try Task.checkCancellation()
      updateAssistant(id: assistantId, text: text)
    }

    await refreshPlaneBalanceOnly()
  }

  private func updateAssistant(id: UUID, text: String) {
    guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
    turns[i].text = text
  }

  /// New conversation: clear turns and conversation id.
  func newChat() {
    cancelChat()
    turns = []
    conversationId = nil
    errorMessage = nil
  }

  func clearChat() { newChat() }

  // MARK: - Image / video generation (control plane)

  func generateImage() {
    mediaTask?.cancel()
    mediaTask = Task { await self.performGenerateImage() }
  }

  func generateVideo() {
    mediaTask?.cancel()
    mediaTask = Task { await self.performGenerateVideo() }
  }

  func cancelMedia() {
    mediaTask?.cancel()
    mediaTask = nil
    mediaBusy = false
    mediaStatus = nil
    mediaError = PrismError.cancelled.userFacingMessage
  }

  /// Attach a reference still as a data: URL (Photos picker / camera roll).
  func setImageReferenceData(_ data: Data, mime: String = "image/jpeg") {
    let b64 = data.base64EncodedString()
    imageImageRef = "data:\(mime);base64,\(b64)"
  }

  func setVideoReferenceData(_ data: Data, mime: String = "image/jpeg") {
    let b64 = data.base64EncodedString()
    videoImageRef = "data:\(mime);base64,\(b64)"
  }

  /// Use last generated image as the next i2i/i2v reference.
  func useLastImageAsReference(forVideo: Bool = false) {
    if let b64 = lastImageBase64, !b64.isEmpty {
      let raw = b64.hasPrefix("data:") ? b64 : "data:image/png;base64,\(b64)"
      if forVideo { videoImageRef = raw } else { imageImageRef = raw }
      return
    }
    if let url = lastImageURL, !url.isEmpty {
      if forVideo { videoImageRef = url } else { imageImageRef = url }
    }
  }

  private func performGenerateImage() async {
    guard canUseMediaDoors else {
      mediaError = "Control plane + device key required for image generation."
      return
    }
    let prompt = imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      mediaError = "Enter an image prompt."
      return
    }
    guard let model = selectedImageModel else {
      mediaError = "Pick an image model."
      return
    }
    mediaBusy = true
    mediaError = nil
    mediaStatus = "Generating \(model.model)…"
    lastImageBase64 = nil
    lastImageURL = nil
    defer { mediaBusy = false }
    let imageRef = imageImageRef.trimmingCharacters(in: .whitespacesAndNewlines)
    let caps = model.capabilities ?? []
    if caps.contains("image-input-required"), imageRef.isEmpty {
      mediaError = "This model requires a reference image (i2i). Add a photo or paste a URL."
      return
    }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateImage(
        model: model.model,
        prompt: prompt,
        image: imageRef.isEmpty ? nil : imageRef
      )
      try Task.checkCancellation()
      lastImageBase64 = res.firstBase64
      lastImageURL = res.firstDisplayURL
      lastImageModel = res.model ?? model.model
      if lastImageBase64 == nil, lastImageURL == nil {
        mediaError = "No image bytes or URL in response for \(lastImageModel ?? model.model)."
        mediaStatus = nil
        return
      }
      mediaStatus = "Done · \(lastImageModel ?? model.model)"
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      mediaError = PrismError.cancelled.userFacingMessage
      mediaStatus = nil
    } catch {
      mediaError = prismUserFacingError(error)
      mediaStatus = nil
    }
  }

  private func performGenerateVideo() async {
    guard canUseMediaDoors else {
      mediaError = "Control plane + device key required for video generation."
      return
    }
    let prompt = videoPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let imageRef = videoImageRef.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty || !imageRef.isEmpty else {
      mediaError = "Enter a video prompt and/or a reference image for i2v."
      return
    }
    guard let model = selectedVideoModel else {
      mediaError = "Pick a video model."
      return
    }
    if model.model.hasPrefix("minimax/hailuo"), imageRef.isEmpty {
      mediaError = "Hailuo is image-to-video only. Add a reference photo, or pick Veo / Seedance Fast."
      return
    }
    mediaBusy = true
    mediaError = nil
    mediaStatus = "Generating \(model.model) (often 1–3 min)…"
    lastVideoURL = nil
    defer { mediaBusy = false }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateVideo(
        model: model.model,
        prompt: prompt.isEmpty ? " " : prompt,
        image: imageRef.isEmpty ? nil : imageRef
      )
      try Task.checkCancellation()
      lastVideoURL = res.video
      lastVideoModel = res.model ?? model.model
      mediaStatus = "Done · \(lastVideoModel ?? model.model)"
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      mediaError = PrismError.cancelled.userFacingMessage
      mediaStatus = nil
    } catch {
      mediaError = prismUserFacingError(error)
      mediaStatus = nil
    }
  }

  private func refreshPlaneBalanceOnly() async {
    guard deviceKeyPresent else { return }
    if let me = try? await controlPlane.me() {
      applyPlaneMe(me)
    }
  }

  /// StoreKit 2 signed transaction → prepaid credit on this device's account.
  func redeemStoreTransaction(jws: String) async throws -> StoreRedeemResponse {
    try await controlPlane.redeemStore(signedTransaction: jws)
  }
}
