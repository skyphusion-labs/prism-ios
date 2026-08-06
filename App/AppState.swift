import Foundation
import Network
import PrismKit
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// One chat turn for the shell UI (also persisted in multi-session storage).
///
/// Context is **client-side**: every send rebuilds the OpenAI message list from
/// `turns` (plane) or reuses `conversationId` (playground). Switching
/// `selectedModelId` never clears turns -- same chat, next model.
struct ChatTurn: Identifiable, Equatable, Codable {
  let id: UUID
  let role: Role
  var text: String
  /// Model that produced this assistant turn (nil for user / system).
  var modelId: String?
  var modelLabel: String?

  enum Role: String, Equatable, Codable {
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

/// One saved conversation (local multi-session list).
struct ChatSession: Identifiable, Equatable, Codable {
  let id: UUID
  var title: String
  var turns: [ChatTurn]
  var conversationId: String?
  var selectedModelId: String?
  /// Plane client-side compact (playground compact lives on the Worker).
  var compact: ConversationCompactState?
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    title: String = "New chat",
    turns: [ChatTurn] = [],
    conversationId: String? = nil,
    selectedModelId: String? = nil,
    compact: ConversationCompactState? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.turns = turns
    self.conversationId = conversationId
    self.selectedModelId = selectedModelId
    self.compact = compact
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  static func makeTitle(from turns: [ChatTurn]) -> String {
    guard let first = turns.first(where: { $0.role == .user }) else { return "New chat" }
    let t = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "New chat" }
    if t.count <= 48 { return t }
    return String(t.prefix(45)) + "..."
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

/// One generated image or video kept in-session for history / re-use.
struct MediaHistoryItem: Identifiable, Equatable {
  enum Kind: String, Equatable { case image, video }

  let id: UUID
  let kind: Kind
  let model: String
  let prompt: String
  let createdAt: Date
  let imageBase64: String?
  let imageURL: String?
  let videoURL: String?

  init(
    id: UUID = UUID(),
    kind: Kind,
    model: String,
    prompt: String,
    createdAt: Date = Date(),
    imageBase64: String? = nil,
    imageURL: String? = nil,
    videoURL: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.model = model
    self.prompt = prompt
    self.createdAt = createdAt
    self.imageBase64 = imageBase64
    self.imageURL = imageURL
    self.videoURL = videoURL
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
  @Published var selectedSpeechModelId: String?
  @Published var selectedSttModelId: String?
  @Published var selectedMusicModelId: String?
  @Published var authMode: String?

  // MARK: - Chat

  @Published var turns: [ChatTurn] = []
  @Published var draft: String = ""
  @Published var conversationId: String?
  @Published var useStream: Bool = true
  /// Active compact state (playground server or plane local).
  @Published var compactState: ConversationCompactState?
  @Published var compactBusy: Bool = false
  /// Saved conversations (newest first). Active transcript is `turns`.
  @Published var sessions: [ChatSession] = []
  @Published var currentSessionId: UUID?

  // MARK: - Image / video / speech (control plane)

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
  /// Elapsed seconds while a media job is running (video long-run UX).
  @Published var mediaElapsedSeconds: Int = 0
  /// Last N image/video results in this session (newest first). Cap 20.
  @Published var mediaHistory: [MediaHistoryItem] = []
  /// TTS input text.
  @Published var speechText: String = ""
  @Published var lastSpeechData: Data?
  @Published var lastSpeechFormat: String = "mp3"
  @Published var lastSpeechModel: String?
  @Published var speechBusy: Bool = false
  @Published var speechError: String?
  @Published var speechStatus: String?
  /// STT: raw audio for next request (base64 or data: URL).
  @Published var sttAudioPayload: String = ""
  @Published var sttAudioLabel: String = ""
  @Published var lastTranscript: String?
  @Published var lastSttModel: String?
  @Published var sttBusy: Bool = false
  @Published var sttError: String?
  @Published var sttStatus: String?
  /// Music generation.
  @Published var musicPrompt: String = ""
  @Published var musicLyrics: String = ""
  @Published var lastMusicAudio: String?
  @Published var lastMusicData: Data?
  @Published var lastMusicModel: String?
  @Published var musicBusy: Bool = false
  @Published var musicError: String?
  @Published var musicStatus: String?
  /// Last user text that failed (for Retry).
  @Published private(set) var lastFailedChatText: String?
  @Published private(set) var canRetryLastChat: Bool = false

  // MARK: - UI chrome

  @Published var isBusy: Bool = false
  @Published var banner: String?
  @Published var errorMessage: String?
  /// Last plane `GET /health` probe (`nil` = not probed yet).
  @Published var planeHealthOK: Bool?
  @Published var planeHealthService: String?
  /// Device has a usable network path (Wi-Fi / cellular).
  @Published var isNetworkSatisfied: Bool = true
  /// Short label for Settings / empty states.
  var planeHealthLabel: String {
    guard backend == .controlPlane else { return "n/a" }
    switch planeHealthOK {
    case .none: return "not checked"
    case .some(true):
      if let s = planeHealthService, !s.isEmpty { return "ok · \(s)" }
      return "ok"
    case .some(false):
      return "unreachable"
    }
  }

  /// True when the last turn is an assistant reply we can re-run under the current model.
  /// Control plane only: client owns the transcript. Playground history is server-side.
  var canRegenerateLastReply: Bool {
    guard backend == .controlPlane, !isBusy, canChat else { return false }
    guard let last = turns.last, last.role == .assistant else { return false }
    return turns.dropLast().last?.role == .user
  }

  /// Completed user/assistant pairs eligible for compact (same bar as web: need 3+).
  var completedChatPairCount: Int {
    completedChatPairs().count
  }

  var isCompacted: Bool {
    guard let c = compactState else { return false }
    return !c.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Enough history to compact, and not already compacted.
  var canCompactConversation: Bool {
    guard canChat, !isBusy, !compactBusy, !isCompacted else { return false }
    if backend == .playground {
      guard let cid = conversationId, !cid.isEmpty else { return false }
    }
    return completedChatPairCount >= ConversationCompact.minTurnsToCompact
  }

  var canExpandConversation: Bool {
    canChat && !isBusy && !compactBusy && isCompacted
  }

  private let secrets: any SecretStore
  private var playground: PrismClient
  private var controlPlane: ControlPlaneClient
  private var chatTask: Task<Void, Never>?
  private var mediaTask: Task<Void, Never>?
  private var speechTask: Task<Void, Never>?
  private var mediaTimerTask: Task<Void, Never>?
  private var pathMonitor: NWPathMonitor?
  #if canImport(AVFoundation) && os(iOS)
  private var speechPlayer: AVAudioPlayer?
  #endif
  private static let mediaHistoryCap = 20
  private static let sessionCap = 50

  /// Empty-state chips; tapping fills the draft (user can edit before send).
  static let starterPrompts: [String] = [
    "Explain this simply, like I am new to the topic:",
    "Summarize the following in three short bullets:",
    "Write a clear product blurb (2 sentences) for:",
    "List practical next steps to debug:",
  ]

  init(secrets: (any SecretStore)? = nil) {
    let store = secrets ?? SecretStores.default()
    self.secrets = store
    playground = PrismClient(baseURL: PrismClient.playBaseURL)
    controlPlane = ControlPlaneClient()
    loadPersisted()
    loadSessionsFromDisk()
    rebuildClients(clearSession: false)
    startNetworkMonitor()
  }

  deinit {
    pathMonitor?.cancel()
  }

  private func startNetworkMonitor() {
    let mon = NWPathMonitor()
    mon.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.isNetworkSatisfied = path.status == .satisfied
      }
    }
    mon.start(queue: DispatchQueue(label: "org.skyphusion.prism.net"))
    pathMonitor = mon
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

  var speechModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "") == "tts" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { ($0.label ?? $0.model) < ($1.label ?? $1.model) }
  }

  var sttModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "") == "stt" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { ($0.label ?? $0.model) < ($1.label ?? $1.model) }
  }

  var musicModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "") == "music" }
      .filter(appliesSpendableFilter)
      .filter(matchesSearch)
      .sorted { ($0.label ?? $0.model) < ($1.label ?? $1.model) }
  }

  /// All chat models ignoring search filter (selection must survive search/filter).
  var allChatModels: [ModelEntry] {
    models
      .filter { ($0.type ?? "chat") == "chat" }
      .filter(appliesSpendableFilter)
  }

  var selectedSpeechModel: ModelEntry? {
    if let id = selectedSpeechModelId, let m = speechModels.first(where: { $0.model == id }) {
      return m
    }
    return speechModels.first
  }

  var selectedSttModel: ModelEntry? {
    if let id = selectedSttModelId, let m = sttModels.first(where: { $0.model == id }) {
      return m
    }
    return sttModels.first
  }

  var selectedMusicModel: ModelEntry? {
    if let id = selectedMusicModelId, let m = musicModels.first(where: { $0.model == id }) {
      return m
    }
    return musicModels.first
  }

  var speechSpendPreview: String? { spendPreview(for: selectedSpeechModel) }
  var sttSpendPreview: String? { spendPreview(for: selectedSttModel) }
  var musicSpendPreview: String? { spendPreview(for: selectedMusicModel) }

  func selectSpeechModel(_ modelId: String) {
    selectedSpeechModelId = modelId.isEmpty ? nil : modelId
    persistUIPrefs()
  }

  func selectSttModel(_ modelId: String) {
    selectedSttModelId = modelId.isEmpty ? nil : modelId
    persistUIPrefs()
  }

  func selectMusicModel(_ modelId: String) {
    selectedMusicModelId = modelId.isEmpty ? nil : modelId
    persistUIPrefs()
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
    persistUIPrefs()
  }

  func selectImageModel(_ modelId: String) {
    selectedImageModelId = modelId.isEmpty ? nil : modelId
    persistUIPrefs()
  }

  func selectVideoModel(_ modelId: String) {
    selectedVideoModelId = modelId.isEmpty ? nil : modelId
    persistUIPrefs()
  }

  func setUseStream(_ on: Bool) {
    useStream = on
    persistUIPrefs()
  }

  func setHideUnspendable(_ on: Bool) {
    hideUnspendable = on
    persistUIPrefs()
  }

  /// Put a past turn back into the draft (edit / re-ask).
  func useTurnAsDraft(_ turn: ChatTurn) {
    draft = turn.text
  }

  /// Plain-text transcript for share / copy.
  func chatTranscriptText() -> String {
    turns.compactMap { t -> String? in
      let body = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !body.isEmpty else { return nil }
      switch t.role {
      case .user: return "You: \(body)"
      case .assistant:
        let who = t.modelLabel ?? t.modelId ?? "Prism"
        return "\(who): \(body)"
      case .system: return "System: \(body)"
      }
    }.joined(separator: "\n\n")
  }

  /// Re-run last image prompt/model after failure (mirrors video retry).
  func retryLastImage() {
    guard !imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    generateImage()
  }

  func clearImageReference() {
    imageImageRef = ""
  }

  func clearVideoReference() {
    videoImageRef = ""
  }

  /// Fill draft from an empty-state starter chip.
  func applyStarterPrompt(_ text: String) {
    draft = text
    Haptics.light()
  }

  /// Clipboard → enrollment token field (token or full pcp_ key routed appropriately).
  @discardableResult
  func pasteEnrollmentFromClipboard() -> Bool {
    #if canImport(UIKit)
    guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty
    else {
      errorMessage = "Clipboard is empty."
      return false
    }
    if raw.hasPrefix("pcp_") {
      // Recovery path: save as device key instead of enrollment token.
      Task { await saveDeviceKey(raw) }
      return true
    }
    enrollmentToken = raw
    errorMessage = nil
    Haptics.light()
    return true
    #else
    return false
    #endif
  }

  /// Unit-price preview for image/video generate (catalog `priceLabel`).
  func spendPreview(for model: ModelEntry?) -> String? {
    guard let p = model?.priceLabel, !p.isEmpty else { return nil }
    if p == "included" { return "Est. cost: included (no unit charge on this plan rate)" }
    return "Est. cost: \(p) per request (metered after success)"
  }

  var imageSpendPreview: String? { spendPreview(for: selectedImageModel) }
  var videoSpendPreview: String? { spendPreview(for: selectedVideoModel) }

  /// Re-send the last failed user message (same context + current model).
  func retryLastFailedChat() {
    guard let text = lastFailedChatText, !text.isEmpty else { return }
    draft = text
    canRetryLastChat = false
    send()
  }

  private func recordChatFailure(userText: String) {
    lastFailedChatText = userText
    canRetryLastChat = true
  }

  private func clearChatFailure() {
    lastFailedChatText = nil
    canRetryLastChat = false
  }

  private func startMediaTimer() {
    mediaTimerTask?.cancel()
    mediaElapsedSeconds = 0
    mediaTimerTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { break }
        mediaElapsedSeconds += 1
      }
    }
  }

  private func stopMediaTimer() {
    mediaTimerTask?.cancel()
    mediaTimerTask = nil
  }

  private func pushMediaHistory(_ item: MediaHistoryItem) {
    mediaHistory.insert(item, at: 0)
    if mediaHistory.count > Self.mediaHistoryCap {
      mediaHistory = Array(mediaHistory.prefix(Self.mediaHistoryCap))
    }
  }

  func restoreMediaHistoryItem(_ item: MediaHistoryItem) {
    switch item.kind {
    case .image:
      lastImageBase64 = item.imageBase64
      lastImageURL = item.imageURL
      lastImageModel = item.model
      imagePrompt = item.prompt
      if let mid = imageModels.first(where: { $0.model == item.model })?.model {
        selectedImageModelId = mid
      }
    case .video:
      lastVideoURL = item.videoURL
      lastVideoModel = item.model
      videoPrompt = item.prompt
      if let mid = videoModels.first(where: { $0.model == item.model })?.model {
        selectedVideoModelId = mid
      }
    }
  }

  /// Re-run last video prompt/model after timeout or failure.
  func retryLastVideo() {
    guard !videoPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !videoImageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    generateVideo()
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
    if backend == .controlPlane {
      await probePlaneHealth()
    }
    await refreshModels()
  }

  /// Foreground resume: cheap health + balance/models refresh when enrolled.
  func onBecomeActive() async {
    if backend == .controlPlane {
      await probePlaneHealth()
      if deviceKeyPresent {
        await refreshPlaneBalanceOnly()
      }
    }
  }

  /// Unauthenticated `GET /health` on the control plane origin.
  func probePlaneHealth() async {
    do {
      let h = try await controlPlane.health()
      planeHealthOK = h.ok
      planeHealthService = h.service
      if !h.ok {
        // Surface soft status without clobbering a richer model banner if we already have one.
        if banner == nil || banner?.contains("error") == true || banner?.contains("unreachable") == true {
          banner = "Control plane · health not ok"
        }
      }
    } catch {
      planeHealthOK = false
      planeHealthService = nil
      // Only overwrite banner when we have no models yet (cold start / offline).
      if models.isEmpty {
        banner = "Control plane · unreachable (\(prismUserFacingError(error)))"
      }
    }
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
    if let m = try? secrets.get(SecretStoreKeys.selectedChatModel), !m.isEmpty {
      selectedModelId = m
    }
    if let m = try? secrets.get(SecretStoreKeys.selectedImageModel), !m.isEmpty {
      selectedImageModelId = m
    }
    if let m = try? secrets.get(SecretStoreKeys.selectedVideoModel), !m.isEmpty {
      selectedVideoModelId = m
    }
    if let m = try? secrets.get(SecretStoreKeys.selectedSpeechModel), !m.isEmpty {
      selectedSpeechModelId = m
    }
    if let m = try? secrets.get(SecretStoreKeys.selectedSttModel), !m.isEmpty {
      selectedSttModelId = m
    }
    if let m = try? secrets.get(SecretStoreKeys.selectedMusicModel), !m.isEmpty {
      selectedMusicModelId = m
    }
    if let s = try? secrets.get(SecretStoreKeys.useStream) {
      useStream = (s == "1" || s == "true")
    }
    if let h = try? secrets.get(SecretStoreKeys.hideUnspendable) {
      hideUnspendable = (h != "0" && h != "false")
    }
  }

  func persistSettings() {
    try? secrets.set(backend.rawValue, for: SecretStoreKeys.backendMode)
    try? secrets.set(baseURLString, for: SecretStoreKeys.playgroundBaseURL)
    try? secrets.set(controlPlaneURLString, for: SecretStoreKeys.controlPlaneBaseURL)
    try? secrets.set(showDeveloperSettings ? "1" : "0", for: "prism.showDeveloperSettings")
  }

  func persistUIPrefs() {
    try? secrets.set(selectedModelId, for: SecretStoreKeys.selectedChatModel)
    try? secrets.set(selectedImageModelId, for: SecretStoreKeys.selectedImageModel)
    try? secrets.set(selectedVideoModelId, for: SecretStoreKeys.selectedVideoModel)
    try? secrets.set(selectedSpeechModelId, for: SecretStoreKeys.selectedSpeechModel)
    try? secrets.set(selectedSttModelId, for: SecretStoreKeys.selectedSttModel)
    try? secrets.set(selectedMusicModelId, for: SecretStoreKeys.selectedMusicModel)
    try? secrets.set(useStream ? "1" : "0", for: SecretStoreKeys.useStream)
    try? secrets.set(hideUnspendable ? "1" : "0", for: SecretStoreKeys.hideUnspendable)
  }

  // MARK: - Multi-session chat

  private var sessionsFileURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("org.skyphusion.prism", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("chat-sessions.json")
  }

  private struct SessionsPayload: Codable {
    var sessions: [ChatSession]
    var currentId: UUID?
  }

  private func loadSessionsFromDisk() {
    let url = sessionsFileURL
    guard let data = try? Data(contentsOf: url),
          let payload = try? JSONDecoder().decode(SessionsPayload.self, from: data)
    else {
      ensureActiveSession()
      return
    }
    sessions = payload.sessions.sorted { $0.updatedAt > $1.updatedAt }
    if let id = payload.currentId, sessions.contains(where: { $0.id == id }) {
      currentSessionId = id
      if let s = sessions.first(where: { $0.id == id }) {
        turns = s.turns
        conversationId = s.conversationId
        compactState = s.compact
        if let mid = s.selectedModelId { selectedModelId = mid }
      }
    } else {
      ensureActiveSession()
    }
  }

  private func saveSessionsToDisk() {
    let payload = SessionsPayload(sessions: sessions, currentId: currentSessionId)
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? data.write(to: sessionsFileURL, options: .atomic)
  }

  /// Keep an active session id; create empty one if list is empty.
  private func ensureActiveSession() {
    if let id = currentSessionId, sessions.contains(where: { $0.id == id }) { return }
    if let first = sessions.first {
      currentSessionId = first.id
      turns = first.turns
      conversationId = first.conversationId
      compactState = first.compact
      return
    }
    let s = ChatSession(selectedModelId: selectedModelId)
    sessions = [s]
    currentSessionId = s.id
    turns = []
    conversationId = nil
    compactState = nil
    saveSessionsToDisk()
  }

  /// Write current transcript into `sessions` and disk.
  func persistCurrentSession() {
    guard let id = currentSessionId else {
      if !turns.isEmpty {
        let s = ChatSession(
          title: ChatSession.makeTitle(from: turns),
          turns: turns,
          conversationId: conversationId,
          selectedModelId: selectedModelId,
          compact: compactState
        )
        sessions.insert(s, at: 0)
        currentSessionId = s.id
        trimSessions()
        saveSessionsToDisk()
      }
      return
    }
    if let i = sessions.firstIndex(where: { $0.id == id }) {
      sessions[i].turns = turns
      sessions[i].conversationId = conversationId
      sessions[i].selectedModelId = selectedModelId
      sessions[i].compact = compactState
      sessions[i].title = ChatSession.makeTitle(from: turns)
      sessions[i].updatedAt = Date()
      // Move to front when activity happens.
      if i != 0 {
        let s = sessions.remove(at: i)
        sessions.insert(s, at: 0)
      }
    }
    trimSessions()
    saveSessionsToDisk()
  }

  private func trimSessions() {
    if sessions.count > Self.sessionCap {
      sessions = Array(sessions.prefix(Self.sessionCap))
    }
  }

  func openSession(_ id: UUID) {
    guard id != currentSessionId else { return }
    persistCurrentSession()
    guard let s = sessions.first(where: { $0.id == id }) else { return }
    currentSessionId = id
    turns = s.turns
    conversationId = s.conversationId
    compactState = s.compact
    if let mid = s.selectedModelId {
      selectedModelId = mid
      persistUIPrefs()
    }
    errorMessage = nil
    clearChatFailure()
    cancelChat()
    saveSessionsToDisk()
  }

  func deleteSession(_ id: UUID) {
    sessions.removeAll { $0.id == id }
    if currentSessionId == id {
      cancelChat()
      if let next = sessions.first {
        currentSessionId = next.id
        turns = next.turns
        conversationId = next.conversationId
        compactState = next.compact
      } else {
        let s = ChatSession(selectedModelId: selectedModelId)
        sessions = [s]
        currentSessionId = s.id
        turns = []
        conversationId = nil
        compactState = nil
      }
      clearChatFailure()
      errorMessage = nil
    }
    saveSessionsToDisk()
    Haptics.light()
  }

  // MARK: - Conversation compact

  /// Completed user/assistant pairs (skips empty / error / cancelled assistant shells).
  func completedChatPairs() -> [ConversationCompact.Pair] {
    var pairs: [ConversationCompact.Pair] = []
    var i = 0
    let list = turns
    while i < list.count {
      let t = list[i]
      if t.role == .user {
        let u = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if i + 1 < list.count, list[i + 1].role == .assistant {
          let a = list[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
          if !u.isEmpty, !a.isEmpty, !a.hasPrefix("(error)"), !a.hasPrefix("(cancelled)") {
            pairs.append(
              ConversationCompact.Pair(user: u, assistant: a, throughTurnIndex: i + 1)
            )
          }
          i += 2
          continue
        }
      }
      i += 1
    }
    return pairs
  }

  /// Compact older turns: playground Worker API, or plane-local summary via a chat model.
  func compactConversation() {
    guard canCompactConversation else { return }
    Task { await performCompact() }
  }

  /// Clear compact so the next send uses full history again.
  func expandConversation() {
    guard canExpandConversation else { return }
    Task { await performExpand() }
  }

  private func performCompact() async {
    compactBusy = true
    errorMessage = nil
    defer { compactBusy = false }
    do {
      switch backend {
      case .playground:
        guard let cid = conversationId, !cid.isEmpty else {
          errorMessage = "Send a message first so the playground has a conversation id."
          return
        }
        let model = selectedModelId
        let res = try await playground.compactConversation(
          id: cid,
          keepRecent: ConversationCompact.defaultKeepRecent,
          model: model
        )
        compactState = res.compact
        let n = res.turns_summarized ?? 0
        let k = res.turns_kept_raw ?? 0
        banner = "Compacted \(n) turn\(n == 1 ? "" : "s"); keeping \(k) recent raw"
      case .controlPlane:
        try await performPlaneCompact()
      }
      persistCurrentSession()
      Haptics.success()
    } catch {
      errorMessage = prismUserFacingError(error)
      Haptics.error()
    }
  }

  private func performPlaneCompact() async throws {
    let pairs = completedChatPairs()
    let keep = ConversationCompact.defaultKeepRecent
    guard pairs.count >= keep + 1 else {
      throw PrismError.serverError(
        "Need at least \(keep + 1) completed turns to compact (have \(pairs.count))."
      )
    }
    let split = ConversationCompact.splitPairs(pairs, keepRecent: keep)
    guard !split.summarize.isEmpty else {
      throw PrismError.serverError("Nothing to summarize with keep_recent=\(keep).")
    }
    guard let modelId = selectedModelId ?? selectedModel?.model else {
      throw PrismError.serverError("Pick a chat model to run the compact summary.")
    }
    let transcript = ConversationCompact.formatPairsForSummary(split.summarize)
    let messages = [
      ControlPlaneChatMessage(role: "system", content: ConversationCompact.systemPrompt),
      ControlPlaneChatMessage(
        role: "user",
        content: "Compress the following conversation into a continuity brief.\n\n\(transcript)"
      ),
    ]
    let raw = try await controlPlane.chat(model: modelId, messages: messages)
    let summary = ConversationCompact.normalizeSummary(raw)
    guard !summary.isEmpty else {
      throw PrismError.serverError("Compact model returned empty summary.")
    }
    let through = split.summarize.last!.throughTurnIndex
    compactState = ConversationCompactState(
      summary: summary,
      through_turn_index: through,
      keep_recent: keep,
      model: modelId,
      updated_at: ISO8601DateFormatter().string(from: Date())
    )
    banner =
      "Compacted \(split.summarize.count) turn\(split.summarize.count == 1 ? "" : "s"); keeping \(split.keep.count) recent raw"
    await refreshPlaneBalanceOnly()
  }

  private func performExpand() async {
    compactBusy = true
    errorMessage = nil
    defer { compactBusy = false }
    do {
      if backend == .playground, let cid = conversationId, !cid.isEmpty {
        _ = try await playground.clearConversationCompact(id: cid)
      }
      compactState = nil
      banner = "Expanded -- next turn uses full history"
      persistCurrentSession()
      Haptics.light()
    } catch {
      errorMessage = prismUserFacingError(error)
      Haptics.error()
    }
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
      compactState = nil
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
    // Always re-probe health when refreshing plane catalog (cheap, no auth).
    await probePlaneHealth()
    guard deviceKeyPresent else {
      models = []
      planeUsageLines = []
      let health = planeHealthOK == false ? " · plane unreachable" : ""
      banner = "Control plane · no device key · enroll in Settings\(health)"
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
      Haptics.error()
    }
  }

  private func applyPlaneMe(_ me: MeResponse) {
    planeClientLabel = me.client?.label ?? me.client?.id
    planeBalance = me.usage?.balanceDescription
    planeUsageLines = me.usage?.dualPoolLines ?? []
    banner = statusBannerPlane(modelCount: models.count, me: me)
  }

  private func pickDefaultModel() {
    // Prefer persisted ids; only fill gaps or replace missing/unspendable-hidden models.
    if selectedModelId == nil || !allChatModels.contains(where: { $0.model == selectedModelId }) {
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
    if selectedSpeechModelId == nil || !speechModels.contains(where: { $0.model == selectedSpeechModelId }) {
      selectedSpeechModelId = speechModels.first(where: { $0.model.contains("aura-2-en") })?.model
        ?? speechModels.first(where: { $0.model.contains("melotts") })?.model
        ?? speechModels.first?.model
    }
    if selectedSttModelId == nil || !sttModels.contains(where: { $0.model == selectedSttModelId }) {
      selectedSttModelId = sttModels.first(where: { $0.model.contains("whisper") })?.model
        ?? sttModels.first?.model
    }
    if selectedMusicModelId == nil || !musicModels.contains(where: { $0.model == selectedMusicModelId }) {
      selectedMusicModelId = musicModels.first?.model
    }
    persistUIPrefs()
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
    compactState = nil
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
      Haptics.success()
      await refreshModels()
    } catch {
      errorMessage = prismUserFacingError(error)
      deviceKeyPresent = false
      Haptics.error()
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
    compactState = nil
    banner = "Control plane · device key cleared"
  }

  // MARK: - Chat

  func send() {
    chatTask?.cancel()
    chatTask = Task { await self.performSend(mode: .newFromDraft) }
  }

  /// Drop the last assistant reply and re-run the last user turn under the current model.
  func regenerateLastReply() {
    guard canRegenerateLastReply else { return }
    chatTask?.cancel()
    chatTask = Task { await self.performSend(mode: .regenerateLast) }
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

  private enum SendMode {
    case newFromDraft
    case regenerateLast
  }

  private func performSend(mode: SendMode) async {
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
    if !isNetworkSatisfied {
      errorMessage = "No network connection. Reconnect and try again."
      Haptics.error()
      return
    }

    let text: String
    switch mode {
    case .newFromDraft:
      let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty else { return }
      text = t
      draft = ""
      turns.append(ChatTurn(role: .user, text: text))
    case .regenerateLast:
      // Pop trailing assistant shells until a user turn is last.
      while let last = turns.last, last.role == .assistant {
        turns.removeLast()
      }
      guard let user = turns.last, user.role == .user else {
        errorMessage = "Nothing to regenerate."
        return
      }
      text = user.text
    }

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
        // Regenerate re-sends the same user text (new completion under current model).
        try await sendPlayground(model: model, userText: text, assistantId: assistantId)
      case .controlPlane:
        // Client resends full turns as messages; model is only the next completion's id.
        try await sendPlane(model: model, assistantId: assistantId)
      }
      clearChatFailure()
      persistCurrentSession()
      Haptics.success()
    } catch is CancellationError {
      updateAssistant(id: assistantId, text: "(cancelled)")
      errorMessage = PrismError.cancelled.userFacingMessage
      recordChatFailure(userText: text)
      persistCurrentSession()
      Haptics.warning()
    } catch {
      let msg = prismUserFacingError(error)
      updateAssistant(id: assistantId, text: "(error) \(msg)")
      errorMessage = msg
      recordChatFailure(userText: text)
      persistCurrentSession()
      Haptics.error()
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
    // Transcript → messages. With compact active, inject summary system block and
    // only turns after through_turn_index (prism v0.175.7 parity). UI transcript unchanged.
    var messages: [ControlPlaneChatMessage] = []
    if let compact = compactState {
      let block = compact.systemBlock
      if !block.isEmpty {
        messages.append(ControlPlaneChatMessage(role: "system", content: block))
      }
    }
    let through = compactState?.through_turn_index
    for (idx, turn) in turns.enumerated() where turn.id != assistantId {
      if let through, idx <= through { continue }
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
            assembled = out
            updateAssistant(id: assistantId, text: out)
          }
        case .error(let m):
          throw PrismError.serverError(m)
        case .unknown:
          break
        }
      }
      // Stream closed with no text (mobile idle / partial body). Fall back to non-stream once
      // rather than showing Empty stream completion for models that still work buffered.
      if assembled.isEmpty,
         let i = turns.firstIndex(where: { $0.id == assistantId }),
         turns[i].text.isEmpty
      {
        let text = try await controlPlane.chat(model: model.model, messages: messages)
        try Task.checkCancellation()
        guard !text.isEmpty else {
          throw PrismError.serverError("Empty stream completion")
        }
        updateAssistant(id: assistantId, text: text)
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

  /// New conversation: save the current session, open a blank one.
  func newChat() {
    cancelChat()
    persistCurrentSession()
    // Drop empty "New chat" shells so the list does not fill with blanks.
    if let id = currentSessionId,
       let i = sessions.firstIndex(where: { $0.id == id }),
       sessions[i].turns.isEmpty
    {
      sessions.remove(at: i)
    }
    let s = ChatSession(selectedModelId: selectedModelId)
    sessions.insert(s, at: 0)
    currentSessionId = s.id
    turns = []
    conversationId = nil
    compactState = nil
    errorMessage = nil
    clearChatFailure()
    trimSessions()
    saveSessionsToDisk()
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
    stopMediaTimer()
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
    if !isNetworkSatisfied {
      mediaError = "No network connection. Reconnect and try again."
      Haptics.error()
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
    startMediaTimer()
    defer {
      stopMediaTimer()
      mediaBusy = false
    }
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
      mediaStatus = "Done · \(lastImageModel ?? model.model) · \(mediaElapsedSeconds)s"
      pushMediaHistory(
        MediaHistoryItem(
          kind: .image,
          model: lastImageModel ?? model.model,
          prompt: prompt,
          imageBase64: lastImageBase64,
          imageURL: lastImageURL
        )
      )
      Haptics.success()
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      mediaError = PrismError.cancelled.userFacingMessage
      mediaStatus = nil
      Haptics.warning()
    } catch {
      mediaError = prismUserFacingError(error)
      mediaStatus = nil
      Haptics.error()
    }
  }

  private func performGenerateVideo() async {
    guard canUseMediaDoors else {
      mediaError = "Control plane + device key required for video generation."
      return
    }
    if !isNetworkSatisfied {
      mediaError = "No network connection. Reconnect and try again."
      Haptics.error()
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
    mediaStatus = "Generating \(model.model) (often 1-3 min)…"
    lastVideoURL = nil
    startMediaTimer()
    defer {
      stopMediaTimer()
      mediaBusy = false
    }
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
      mediaStatus = "Done · \(lastVideoModel ?? model.model) · \(mediaElapsedSeconds)s"
      pushMediaHistory(
        MediaHistoryItem(
          kind: .video,
          model: lastVideoModel ?? model.model,
          prompt: prompt,
          videoURL: lastVideoURL
        )
      )
      Haptics.success()
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      mediaError = PrismError.cancelled.userFacingMessage
      mediaStatus = nil
      Haptics.warning()
    } catch {
      mediaError = prismUserFacingError(error)
      mediaStatus = "Failed after \(mediaElapsedSeconds)s · prompt kept for Retry"
      Haptics.error()
    }
  }

  // MARK: - Speech (TTS)

  func generateSpeech() {
    speechTask?.cancel()
    speechTask = Task { await self.performGenerateSpeech() }
  }

  func cancelSpeech() {
    speechTask?.cancel()
    speechTask = nil
    speechBusy = false
    speechStatus = nil
    speechError = PrismError.cancelled.userFacingMessage
  }

  /// Fill speech field from a chat turn and synthesize.
  func speakText(_ text: String) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    speechText = t
    generateSpeech()
  }

  func playLastSpeech() {
    guard let data = lastSpeechData else { return }
    #if canImport(AVFoundation) && os(iOS)
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      speechPlayer = try AVAudioPlayer(data: data)
      speechPlayer?.prepareToPlay()
      speechPlayer?.play()
      Haptics.light()
    } catch {
      speechError = "Could not play audio: \(error.localizedDescription)"
      Haptics.error()
    }
    #endif
  }

  private func performGenerateSpeech() async {
    guard canUseMediaDoors else {
      speechError = "Control plane + device key required for speech."
      return
    }
    if !isNetworkSatisfied {
      speechError = "No network connection. Reconnect and try again."
      Haptics.error()
      return
    }
    let text = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      speechError = "Enter text to speak."
      return
    }
    guard let model = selectedSpeechModel else {
      speechError = "Pick a speech model."
      return
    }
    speechBusy = true
    speechError = nil
    speechStatus = "Synthesizing \(model.model)…"
    lastSpeechData = nil
    defer { speechBusy = false }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateSpeech(model: model.model, input: text)
      try Task.checkCancellation()
      guard let data = res.audioData else {
        speechError = "No audio in response."
        speechStatus = nil
        return
      }
      lastSpeechData = data
      lastSpeechFormat = res.format ?? "mp3"
      lastSpeechModel = res.model ?? model.model
      speechStatus = "Done · \(lastSpeechModel ?? model.model) · \(data.count / 1024) KB"
      Haptics.success()
      playLastSpeech()
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      speechError = PrismError.cancelled.userFacingMessage
      speechStatus = nil
      Haptics.warning()
    } catch {
      speechError = prismUserFacingError(error)
      speechStatus = nil
      Haptics.error()
    }
  }

  // MARK: - STT (transcription)

  /// Load recorded or imported audio for transcription.
  func setSttAudioData(_ data: Data, mime: String = "audio/mp4", label: String = "audio") {
    let b64 = data.base64EncodedString()
    sttAudioPayload = "data:\(mime);base64,\(b64)"
    sttAudioLabel = "\(label) · \(data.count / 1024) KB"
    sttError = nil
  }

  func clearSttAudio() {
    sttAudioPayload = ""
    sttAudioLabel = ""
  }

  func transcribeAudio() {
    speechTask?.cancel()
    speechTask = Task { await self.performTranscribe() }
  }

  func cancelStt() {
    speechTask?.cancel()
    speechTask = nil
    sttBusy = false
    sttStatus = nil
    sttError = PrismError.cancelled.userFacingMessage
  }

  /// Push last transcript into chat draft.
  func useTranscriptAsChatDraft() {
    guard let t = lastTranscript, !t.isEmpty else { return }
    draft = t
    Haptics.light()
  }

  /// Push last transcript into TTS field.
  func useTranscriptAsSpeech() {
    guard let t = lastTranscript, !t.isEmpty else { return }
    speechText = t
    Haptics.light()
  }

  private func performTranscribe() async {
    guard canUseMediaDoors else {
      sttError = "Control plane + device key required for transcription."
      return
    }
    if !isNetworkSatisfied {
      sttError = "No network connection. Reconnect and try again."
      Haptics.error()
      return
    }
    let audio = sttAudioPayload.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !audio.isEmpty else {
      sttError = "Record or import audio first."
      return
    }
    guard let model = selectedSttModel else {
      sttError = "Pick a transcription model."
      return
    }
    sttBusy = true
    sttError = nil
    sttStatus = "Transcribing \(model.model)…"
    lastTranscript = nil
    defer { sttBusy = false }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.transcribe(model: model.model, audio: audio)
      try Task.checkCancellation()
      let text = (res.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        sttError = "Empty transcript."
        sttStatus = nil
        return
      }
      lastTranscript = text
      lastSttModel = res.model ?? model.model
      sttStatus = "Done · \(lastSttModel ?? model.model)"
      Haptics.success()
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      sttError = PrismError.cancelled.userFacingMessage
      sttStatus = nil
      Haptics.warning()
    } catch {
      sttError = prismUserFacingError(error)
      sttStatus = nil
      Haptics.error()
    }
  }

  // MARK: - Music

  private var musicTask: Task<Void, Never>?

  func generateMusic() {
    musicTask?.cancel()
    musicTask = Task { await self.performGenerateMusic() }
  }

  func cancelMusic() {
    musicTask?.cancel()
    musicTask = nil
    musicBusy = false
    musicStatus = nil
    musicError = PrismError.cancelled.userFacingMessage
  }

  func playLastMusic() {
    if let data = lastMusicData {
      #if canImport(AVFoundation) && os(iOS)
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        speechPlayer = try AVAudioPlayer(data: data)
        speechPlayer?.prepareToPlay()
        speechPlayer?.play()
        Haptics.light()
      } catch {
        musicError = "Could not play audio: \(error.localizedDescription)"
        Haptics.error()
      }
      #endif
      return
    }
    // URL-only: open is handled by the view (Link / share).
  }

  private func performGenerateMusic() async {
    guard canUseMediaDoors else {
      musicError = "Control plane + device key required for music."
      return
    }
    if !isNetworkSatisfied {
      musicError = "No network connection. Reconnect and try again."
      Haptics.error()
      return
    }
    let prompt = musicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      musicError = "Enter a music prompt."
      return
    }
    guard let model = selectedMusicModel else {
      musicError = "Pick a music model."
      return
    }
    musicBusy = true
    musicError = nil
    musicStatus = "Generating \(model.model)…"
    lastMusicAudio = nil
    lastMusicData = nil
    defer { musicBusy = false }
    let lyrics = musicLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateMusic(
        model: model.model,
        prompt: prompt,
        lyrics: lyrics.isEmpty ? nil : lyrics
      )
      try Task.checkCancellation()
      lastMusicAudio = res.audio
      lastMusicData = res.audioData
      lastMusicModel = res.model ?? model.model
      musicStatus = "Done · \(lastMusicModel ?? model.model)"
      Haptics.success()
      if lastMusicData != nil {
        playLastMusic()
      }
      await refreshPlaneBalanceOnly()
    } catch is CancellationError {
      musicError = PrismError.cancelled.userFacingMessage
      musicStatus = nil
      Haptics.warning()
    } catch {
      musicError = prismUserFacingError(error)
      musicStatus = nil
      Haptics.error()
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
