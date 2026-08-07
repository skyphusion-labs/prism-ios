import Foundation
import Network
import PrismKit
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(AVFoundation) && os(iOS)
/// Relays `AVAudioPlayer` end-of-track so music UI can clear `isMusicPlaying`.
private final class AudioPlayerFinishRelay: NSObject, AVAudioPlayerDelegate {
  var onFinish: (() -> Void)?
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    onFinish?()
  }
}
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
  /// Vision attachments for this turn (data:image/... URLs). User turns only.
  var imageDataUrls: [String]?

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
    modelLabel: String? = nil,
    imageDataUrls: [String]? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.modelId = modelId
    self.modelLabel = modelLabel
    self.imageDataUrls = imageDataUrls
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

  /// Prefer data: URL, else https, for chat attach / i2v handoff.
  var imageDataURL: String? {
    if let b64 = imageBase64, !b64.isEmpty {
      return b64.hasPrefix("data:") ? b64 : "data:image/png;base64,\(b64)"
    }
    if let url = imageURL, !url.isEmpty { return url }
    return nil
  }
}

/// Main tab bar selection (plane shell). Used for Image/Video → Chat handoffs.
enum AppMainTab: Hashable {
  case chat
  case image
  case video
  case more
}

/// Inline text file staged for the next chat send (not RAG -- whole file in this turn).
struct DraftDocument: Identifiable, Equatable {
  let id: UUID
  let name: String
  let text: String

  init(id: UUID = UUID(), name: String, text: String) {
    self.id = id
    self.name = name
    self.text = text
  }
}

@MainActor
final class AppState: ObservableObject {
  // MARK: - Backend

  /// Selected main tab (plane). Drives TabView + cross-modal navigation.
  @Published var selectedTab: AppMainTab = .chat

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
  /// DEBUG smoke only: in-memory pcp_ when Keychain write fails (unsigned sim builds).
  #if DEBUG
  private var smokeClientKey: String?
  #endif
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
  /// Pending chat image attachments (data URLs) for the next send.
  @Published var draftImageDataUrls: [String] = []
  /// Text-file attachments inlined into the next user message (not Vectorize RAG).
  @Published var draftDocuments: [DraftDocument] = []
  /// Last plane request cost from response headers (`prism-usage-micro-usd`).
  @Published var lastRequestCost: String?
  /// Biometric lock enabled (Face ID / Touch ID when app becomes active).
  @Published var biometricLockEnabled: Bool = false
  /// True until the user unlocks after launch / background.
  @Published var isBiometricallyLocked: Bool = false
  /// Live WebSocket STT is connected / streaming.
  @Published var liveSttActive: Bool = false
  /// Partial transcript while live STT is running.
  @Published var liveSttPartial: String = ""
  /// Live STT status line for the chat chrome.
  @Published var liveSttStatus: String?
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
  /// Clip length in seconds (clamped to selected model max on generate).
  @Published var videoDurationSeconds: Int = 5
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
  /// True while in-app TTS playback is running.
  @Published private(set) var isSpeechPlaying: Bool = false
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
  /// Seconds elapsed while a music job is running (mirrors mediaElapsedSeconds).
  @Published var musicElapsedSeconds: Int = 0
  /// True while in-app music playback is running (local bytes or streamed URL).
  @Published private(set) var isMusicPlaying: Bool = false
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
  private var musicTimerTask: Task<Void, Never>?
  private var pathMonitor: NWPathMonitor?
  #if canImport(AVFoundation) && os(iOS)
  private var speechPlayer: AVAudioPlayer?
  /// Local music bytes (kept separate from speech so Stop / TTS do not share a player).
  private var musicLocalPlayer: AVAudioPlayer?
  private var musicStreamPlayer: AVPlayer?
  private var musicEndObserver: NSObjectProtocol?
  private let musicPlayerFinish = AudioPlayerFinishRelay()
  private let speechPlayerFinish = AudioPlayerFinishRelay()
  #endif
  private static let mediaHistoryCap = 20
  private static let sessionCap = 50

  /// Empty-state chips; full self-contained prompts (never trailing blanks).
  static let starterPrompts: [String] = [
    "In plain language, explain how HTTPS keeps web traffic private.",
    "Summarize the tradeoffs between SQL and document databases in three short bullets.",
    "Write a two-sentence product blurb for a prepaid AI playground aimed at indie developers.",
    "List five practical steps to debug a REST API that returns 502 only under load.",
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
    // Snap duration into the new model's legal range.
    let limits = VideoDurationCatalog.limits(for: modelId)
    videoDurationSeconds = limits.clamp(videoDurationSeconds)
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

  /// Attach a photo (JPEG data URL) to the next chat send. Cap 3 images / ~3 MiB each.
  func attachChatImageJPEGData(_ data: Data, maxBytes: Int = 3 * 1024 * 1024) {
    guard draftImageDataUrls.count < 3 else {
      errorMessage = "At most 3 images per message."
      return
    }
    var jpeg = data
    if jpeg.count > maxBytes {
      #if canImport(UIKit)
      if let img = UIImage(data: data),
         let smaller = img.jpegData(compressionQuality: 0.6),
         smaller.count <= maxBytes
      {
        jpeg = smaller
      } else {
        errorMessage = "Image is too large (max ~3 MB after compress)."
        return
      }
      #else
      errorMessage = "Image is too large (max ~3 MB)."
      return
      #endif
    }
    let b64 = jpeg.base64EncodedString()
    draftImageDataUrls.append("data:image/jpeg;base64,\(b64)")
    Haptics.light()
  }

  /// Attach an existing data: or https: image URL to the chat draft (handoff from Image tab).
  @discardableResult
  func attachChatImageDataURL(_ dataURL: String) -> Bool {
    let trimmed = dataURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard draftImageDataUrls.count < 3 else {
      errorMessage = "At most 3 images per message."
      return false
    }
    if draftImageDataUrls.contains(trimmed) {
      Haptics.light()
      return true
    }
    draftImageDataUrls.append(trimmed)
    Haptics.light()
    return true
  }

  func removeDraftImage(at index: Int) {
    guard draftImageDataUrls.indices.contains(index) else { return }
    draftImageDataUrls.remove(at: index)
  }

  func clearDraftImages() {
    draftImageDataUrls = []
  }

  // MARK: - Cross-modal handoffs (Image ↔ Chat ↔ Video)

  /// Last generated image → chat draft attachments; jumps to Chat tab.
  func useLastImageInChat() {
    guard let url = lastImageAsDataURL() else {
      errorMessage = "No generated image to send to chat."
      Haptics.warning()
      return
    }
    guard attachChatImageDataURL(url) else { return }
    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft = "Describe this image."
    }
    selectedTab = .chat
    banner = "Image attached to chat draft"
    Haptics.success()
  }

  /// Media history row → chat draft (images only).
  func useMediaHistoryInChat(_ item: MediaHistoryItem) {
    guard item.kind == .image, let url = item.imageDataURL else {
      errorMessage = "That history item has no image."
      Haptics.warning()
      return
    }
    guard attachChatImageDataURL(url) else { return }
    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft = "Describe this image."
    }
    selectedTab = .chat
    banner = "Image attached to chat draft"
    Haptics.success()
  }

  /// Last generated image → Video i2v first frame; jumps to Video tab.
  func animateLastImage() {
    guard lastImageAsDataURL() != nil else {
      errorMessage = "No generated image to animate."
      Haptics.warning()
      return
    }
    useLastImageAsReference(forVideo: true)
    selectedTab = .video
    banner = "Image set as video first frame"
    Haptics.success()
  }

  /// Media history image → Video i2v.
  func animateMediaHistory(_ item: MediaHistoryItem) {
    guard item.kind == .image, let url = item.imageDataURL else {
      errorMessage = "That history item has no image."
      Haptics.warning()
      return
    }
    videoImageRef = url
    selectedTab = .video
    banner = "Image set as video first frame"
    Haptics.success()
  }

  /// Chat draft attachment → Video i2v.
  func animateChatDraftImage(at index: Int) {
    guard draftImageDataUrls.indices.contains(index) else { return }
    videoImageRef = draftImageDataUrls[index]
    selectedTab = .video
    banner = "Chat image set as video first frame"
    Haptics.success()
  }

  /// Chat turn image(s) → Video i2v (uses first URL).
  func animateChatTurnImages(_ urls: [String]) {
    guard let first = urls.first, !first.isEmpty else {
      errorMessage = "No image on that message."
      Haptics.warning()
      return
    }
    videoImageRef = first
    selectedTab = .video
    banner = "Chat image set as video first frame"
    Haptics.success()
  }

  private func lastImageAsDataURL() -> String? {
    if let b64 = lastImageBase64, !b64.isEmpty {
      return b64.hasPrefix("data:") ? b64 : "data:image/png;base64,\(b64)"
    }
    if let url = lastImageURL, !url.isEmpty { return url }
    return nil
  }

  // MARK: - Inline document attach (not RAG)

  /// Max characters inlined per text file (protects context; playground uses ~200k).
  static let draftDocumentMaxChars = 80_000
  static let draftDocumentMaxCount = 3

  /// Stage a UTF-8 text file for the next chat turn (whole file in prompt, not Vectorize).
  @discardableResult
  func attachChatDocument(name: String, data: Data) -> Bool {
    guard draftDocuments.count < Self.draftDocumentMaxCount else {
      errorMessage = "At most \(Self.draftDocumentMaxCount) text files per message."
      Haptics.warning()
      return false
    }
    guard let raw = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .isoLatin1)
    else {
      errorMessage = "Could not read \(name) as text. Use UTF-8 / plain text, not binary."
      Haptics.error()
      return false
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "File is empty."
      Haptics.warning()
      return false
    }
    // Reject mostly-binary (high control-char ratio excluding tab/newline).
    let sample = trimmed.prefix(4000)
    let control = sample.filter { ch in
      guard let s = ch.unicodeScalars.first else { return false }
      return s.value < 32 && s.value != 9 && s.value != 10 && s.value != 13
    }.count
    if control > sample.count / 10 {
      errorMessage = "\(name) looks binary. Attach images via the photo menu, or use a text file."
      Haptics.error()
      return false
    }
    var text = trimmed
    if text.count > Self.draftDocumentMaxChars {
      text = String(text.prefix(Self.draftDocumentMaxChars))
        + "\n\n…[truncated at \(Self.draftDocumentMaxChars) characters]"
    }
    let safeName = name.isEmpty ? "document.txt" : name
    draftDocuments.append(DraftDocument(name: safeName, text: text))
    Haptics.light()
    return true
  }

  func removeDraftDocument(id: UUID) {
    draftDocuments.removeAll { $0.id == id }
  }

  func clearDraftDocuments() {
    draftDocuments = []
  }

  /// Fold staged documents into the user message (fenced blocks). Clears draft docs.
  private func consumeDraftDocumentsIntoText(_ userText: String) -> String {
    guard !draftDocuments.isEmpty else { return userText }
    let blocks = draftDocuments.map { doc -> String in
      let fence = "```"
      return "\(fence)\(doc.name)\n\(doc.text)\n\(fence)"
    }
    draftDocuments = []
    let body = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.isEmpty {
      return blocks.joined(separator: "\n\n")
    }
    return body + "\n\n" + blocks.joined(separator: "\n\n")
  }

  func clearMediaHistory() {
    mediaHistory = []
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

  private func startMusicTimer() {
    musicTimerTask?.cancel()
    musicElapsedSeconds = 0
    musicTimerTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { break }
        musicElapsedSeconds += 1
      }
    }
  }

  private func stopMusicTimer() {
    musicTimerTask?.cancel()
    musicTimerTask = nil
  }

  /// Live status line for the music form (elapsed + rough estimate).
  var musicElapsedLabel: String {
    let s = musicElapsedSeconds
    let m = s / 60
    let r = s % 60
    let elapsed = m > 0 ? String(format: "%d:%02d", m, r) : "\(s)s"
    // Live MiniMax full tracks often ~2-4 min wall time (measured ~233s); lyrics/vocals
    // and R2 rehost can push toward the plane's 5 min nonchat ceiling.
    let estimate = musicLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "often 2-4 min"
      : "often 3-5 min"
    return "Elapsed \(elapsed) · \(estimate) · lock-safe poll"
  }

  /// Grok ZDR / play-proxy media may 404 briefly; wait for a successful HEAD/GET.
  private static func waitUntilMediaReachable(
    _ urlString: String,
    attempts: Int = 12,
    delayNs: UInt64 = 2_000_000_000
  ) async -> String? {
    guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
      return urlString
    }
    // Only retry our own media host (not arbitrary provider URLs).
    let host = url.host ?? ""
    let isOurs = host.contains("play-proxy") || url.path.contains("/v1/media/")
    if !isOurs { return urlString }

    for _ in 0..<attempts {
      var req = URLRequest(url: url)
      req.httpMethod = "HEAD"
      req.timeoutInterval = 15
      if let (_, resp) = try? await URLSession.shared.data(for: req),
         let http = resp as? HTTPURLResponse,
         (200...399).contains(http.statusCode)
      {
        return urlString
      }
      // Some edges refuse HEAD; try a Range GET of first byte.
      var get = URLRequest(url: url)
      get.setValue("bytes=0-0", forHTTPHeaderField: "Range")
      get.timeoutInterval = 15
      if let (_, resp) = try? await URLSession.shared.data(for: get),
         let http = resp as? HTTPURLResponse,
         (200...399).contains(http.statusCode)
      {
        return urlString
      }
      try? await Task.sleep(nanoseconds: delayNs)
    }
    return urlString
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
    #if DEBUG
    // Simulator / CI smoke: inject pcp_ from Documents/pcp.key or env path (never log value).
    var smokePaths: [String] = []
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      smokePaths.append(docs.appendingPathComponent("pcp.key").path)
    }
    if let path = ProcessInfo.processInfo.environment["PRISM_SMOKE_DEVICE_KEY_FILE"], !path.isEmpty {
      smokePaths.append(path)
    }
    for path in smokePaths {
      guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
      let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if k.hasPrefix("pcp_"), k.count >= 20 {
        smokeClientKey = k
        try? secrets.set(k, for: SecretStoreKeys.controlPlaneDeviceKey)
        try? secrets.set("controlPlane", for: SecretStoreKeys.backendMode)
        backend = .controlPlane
        deviceKeyPresent = true
        break
      }
    }
    #endif
    #if canImport(UIKit)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    #endif
    // Gate UI before any network when biometric lock is on with a stored key.
    if biometricLockEnabled, deviceKeyPresent {
      isBiometricallyLocked = true
    }
    rebuildClients(clearSession: false)
    if backend == .controlPlane {
      await probePlaneHealth()
      if deviceKeyPresent {
        // Cold start: pick up Workflow jobs that finished while the app was dead.
        await forceSyncPendingJobs()
      }
    }
    await refreshModels()
  }

  /// Foreground resume: always re-check plane jobs (even under biometric lock UI).
  /// Suspended poll Tasks keep `musicBusy`/`mediaBusy` true, so a `!busy` resume never ran.
  func onBecomeActive() async {
    if backend == .controlPlane, deviceKeyPresent {
      // Force-sync pending Workflow jobs first so a finished song appears after unlock.
      await forceSyncPendingJobs()
    }
    guard !isBiometricallyLocked else { return }
    if backend == .controlPlane {
      await probePlaneHealth()
      if deviceKeyPresent {
        await refreshPlaneBalanceOnly()
      }
    }
  }

  /// Call when scene enters background so the next open requires biometrics.
  func lockIfNeeded() {
    if biometricLockEnabled, deviceKeyPresent {
      isBiometricallyLocked = true
    }
  }

  func setBiometricLockEnabled(_ on: Bool) {
    biometricLockEnabled = on
    try? secrets.set(on ? "1" : "0", for: SecretStoreKeys.biometricLockEnabled)
    if on, deviceKeyPresent {
      isBiometricallyLocked = true
    } else if !on {
      isBiometricallyLocked = false
    }
  }

  /// Face ID / Touch ID unlock (or device passcode fallback).
  func unlockWithBiometrics() async {
    guard biometricLockEnabled else {
      isBiometricallyLocked = false
      return
    }
    let ok = await BiometricLock.authenticate(reason: "Unlock Prism")
    if ok {
      isBiometricallyLocked = false
      Haptics.success()
      if backend == .controlPlane, deviceKeyPresent {
        await forceSyncPendingJobs()
        await probePlaneHealth()
        await refreshPlaneBalanceOnly()
      }
    } else {
      Haptics.warning()
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
    if let b = try? secrets.get(SecretStoreKeys.biometricLockEnabled) {
      biometricLockEnabled = (b == "1" || b == "true")
    }
  }

  func persistSettings() {
    try? secrets.set(backend.rawValue, for: SecretStoreKeys.backendMode)
    try? secrets.set(baseURLString, for: SecretStoreKeys.playgroundBaseURL)
    try? secrets.set(controlPlaneURLString, for: SecretStoreKeys.controlPlaneBaseURL)
    try? secrets.set(showDeveloperSettings ? "1" : "0", for: "prism.showDeveloperSettings")
    try? secrets.set(biometricLockEnabled ? "1" : "0", for: SecretStoreKeys.biometricLockEnabled)
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
    try? secrets.set(biometricLockEnabled ? "1" : "0", for: SecretStoreKeys.biometricLockEnabled)
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

  /// Pull playground server conversation list into the local session list (playground only).
  @Published var serverSyncBusy = false
  @Published var serverSyncMessage: String?

  func syncPlaygroundConversations() async {
    guard backend == .playground, authenticated else {
      serverSyncMessage = "Sign in to the playground to sync cloud chats."
      return
    }
    serverSyncBusy = true
    serverSyncMessage = nil
    defer { serverSyncBusy = false }
    do {
      let remote = try await playground.listConversations()
      var imported = 0
      for item in remote.prefix(40) {
        let cid = item.conversation_id
        if sessions.contains(where: { $0.conversationId == cid }) { continue }
        let detail = try await playground.getConversation(id: cid)
        if let err = detail.error, !err.isEmpty { continue }
        var turns: [ChatTurn] = []
        // Server rows are chat table rows: user_input + output per turn.
        if let rows = detail.turns {
          for row in rows {
            let userIn = row.user_input ?? ""
            let out = row.resolvedOutput ?? ""
            if !userIn.isEmpty {
              turns.append(ChatTurn(role: .user, text: userIn))
            }
            if !out.isEmpty {
              turns.append(
                ChatTurn(role: .assistant, text: out, modelId: row.model, modelLabel: row.model)
              )
            }
          }
        }
        let title = item.first_input.map { t in
          t.count <= 48 ? t : String(t.prefix(45)) + "..."
        } ?? "Cloud chat"
        let s = ChatSession(
          title: title.isEmpty ? "Cloud chat" : title,
          turns: turns,
          conversationId: cid,
          selectedModelId: item.latest_model,
          compact: detail.compact
        )
        sessions.append(s)
        imported += 1
      }
      sessions.sort { $0.updatedAt > $1.updatedAt }
      trimSessions()
      saveSessionsToDisk()
      serverSyncMessage = imported == 0
        ? "Already up to date with playground (\(remote.count) cloud chats)."
        : "Imported \(imported) chat(s) from playground."
      Haptics.success()
    } catch {
      serverSyncMessage = prismUserFacingError(error)
      Haptics.error()
    }
  }

  /// Export all local sessions as JSON (share / backup). Control plane has no server history.
  func exportSessionsJSON() -> Data? {
    persistCurrentSession()
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    return try? enc.encode(sessions)
  }

  /// Preview of a chat export file (count + sample titles) before merge/replace.
  struct ChatImportPreview: Equatable {
    let count: Int
    let titles: [String]
    let newIds: Int
    let overlappingIds: Int
  }

  /// Decode without applying; used for import confirmation UX.
  func previewImportSessionsJSON(_ data: Data) throws -> ChatImportPreview {
    let incoming = try decodeSessionsJSON(data)
    let existing = Set(sessions.map(\.id))
    let newIds = incoming.filter { !existing.contains($0.id) }.count
    let overlapping = incoming.filter { existing.contains($0.id) }.count
    let titles = incoming.prefix(5).map(\.title)
    return ChatImportPreview(
      count: incoming.count,
      titles: Array(titles),
      newIds: newIds,
      overlappingIds: overlapping
    )
  }

  /// Import sessions from JSON.
  /// - Parameter replace: if true, replace local list with file; else merge by id (file wins on conflict).
  @discardableResult
  func importSessionsJSON(_ data: Data, replace: Bool = false) throws -> ChatImportPreview {
    let incoming = try decodeSessionsJSON(data)
    let preview = try previewImportSessionsJSON(data)
    if replace {
      sessions = incoming.sorted { $0.updatedAt > $1.updatedAt }
    } else {
      var byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
      for s in incoming {
        byId[s.id] = s
      }
      sessions = Array(byId.values).sorted { $0.updatedAt > $1.updatedAt }
    }
    trimSessions()
    saveSessionsToDisk()
    ensureActiveSession()
    Haptics.success()
    return preview
  }

  private func decodeSessionsJSON(_ data: Data) throws -> [ChatSession] {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return try dec.decode([ChatSession].self, from: data)
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
    #if DEBUG
    let existingKey = (try? secrets.get(SecretStoreKeys.controlPlaneDeviceKey)) ?? smokeClientKey
    #else
    let existingKey = try? secrets.get(SecretStoreKeys.controlPlaneDeviceKey)
    #endif
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
    publishWidgetBalance(planeBalance)
  }

  /// Write spendable balance into the App Group for the home-screen widget (no secrets).
  private func publishWidgetBalance(_ balance: String?) {
    let suite = UserDefaults(suiteName: SecretStoreKeys.appGroupId)
    let text = balance ?? "Open Prism to refresh"
    suite?.set(text, forKey: SecretStoreKeys.widgetBalanceKey)
    let fmt = DateFormatter()
    fmt.dateStyle = .none
    fmt.timeStyle = .short
    suite?.set("Updated \(fmt.string(from: Date()))", forKey: SecretStoreKeys.widgetUpdatedAtKey)
    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
  }

  private func applyMeterHeaders(_ meter: PlaneMeterHeaders) {
    if let cost = meter.costDescription {
      lastRequestCost = cost
    }
    // Prefer remaining headers over a full /me round-trip when present.
    var remainingBits: [String] = []
    if let c = meter.creditRemainingMicroUsd {
      remainingBits.append(String(format: "prepaid $%.4f", Double(c) / 1_000_000.0))
    }
    if let a = meter.allowanceRemainingMicroUsd {
      remainingBits.append(String(format: "allowance $%.4f", Double(a) / 1_000_000.0))
    }
    if !remainingBits.isEmpty {
      planeBalance = remainingBits.joined(separator: " · ")
      publishWidgetBalance(planeBalance)
    }
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
      // Prefer Seedance for text-to-video (Hailuo is i2v-only; Grok needs ZDR path).
      selectedVideoModelId = videoModels.first(where: { $0.model == "bytedance/seedance-2.0-fast" })?.model
        ?? videoModels.first(where: { $0.model.hasPrefix("bytedance/seedance") })?.model
        ?? videoModels.first(where: { $0.model == "google/veo-3.1-fast" })?.model
        ?? videoModels.first(where: { $0.model.hasPrefix("google/veo") })?.model
        ?? videoModels.first(where: {
          !$0.model.hasPrefix("minimax/hailuo") && !$0.model.hasPrefix("xai/grok-imagine-video")
        })?.model
        ?? videoModels.first?.model
    }
    if let mid = selectedVideoModelId {
      videoDurationSeconds = VideoDurationCatalog.limits(for: mid).clamp(videoDurationSeconds)
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
    var sendImages: [String] = []
    switch mode {
    case .newFromDraft:
      let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      sendImages = draftImageDataUrls
      let hasDocs = !draftDocuments.isEmpty
      guard !t.isEmpty || !sendImages.isEmpty || hasDocs else { return }
      // Inline text files into this turn only (not RAG / Vectorize).
      let withDocs = consumeDraftDocumentsIntoText(t)
      text = withDocs.isEmpty ? (sendImages.isEmpty ? "" : "(image)") : withDocs
      guard !text.isEmpty || !sendImages.isEmpty else { return }
      draft = ""
      draftImageDataUrls = []
      turns.append(ChatTurn(role: .user, text: text, imageDataUrls: sendImages.isEmpty ? nil : sendImages))
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
      sendImages = user.imageDataUrls ?? []
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
        try await sendPlayground(
          model: model,
          userText: text,
          assistantId: assistantId,
          imageDataUrls: sendImages
        )
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

  private func sendPlayground(
    model: ModelEntry,
    userText: String,
    assistantId: UUID,
    imageDataUrls: [String] = []
  ) async throws {
    let atts: [ChatAttachment]? =
      imageDataUrls.isEmpty ? nil : imageDataUrls.map { ChatAttachment.image(dataURL: $0) }
    let body = ChatRequestBody(
      model: model.model,
      userInput: userText,
      conversationId: conversationId,
      attachments: atts
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
        let imgs = turn.imageDataUrls ?? []
        guard !turn.text.isEmpty || !imgs.isEmpty else { continue }
        messages.append(
          ControlPlaneChatMessage(
            role: "user",
            content: turn.text.isEmpty ? " " : turn.text,
            imageDataUrls: imgs.isEmpty ? nil : imgs
          )
        )
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
        let (text, meter) = try await controlPlane.chatWithMeter(model: model.model, messages: messages)
        try Task.checkCancellation()
        guard !text.isEmpty else {
          throw PrismError.serverError("Empty stream completion")
        }
        updateAssistant(id: assistantId, text: text)
        applyMeterHeaders(meter)
      } else {
        // SSE rarely carries usage headers; balance refresh covers the spend.
        lastRequestCost = "Streamed · cost in balance"
      }
    } else {
      let (text, meter) = try await controlPlane.chatWithMeter(model: model.model, messages: messages)
      try Task.checkCancellation()
      updateAssistant(id: assistantId, text: text)
      applyMeterHeaders(meter)
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
    clearPendingVideoJob()
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
    // gpt-image-2 (and other auto-async plane models) return 202; status must say job continues.
    let likelyAsync = model.model == "openai/gpt-image-2"
    mediaStatus = likelyAsync
      ? "Generating \(model.model)… · plane job (safe to lock)"
      : "Generating \(model.model)…"
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
      if let id = res.id, res.isAsyncAccept {
        try? secrets.set(id, for: SecretStoreKeys.pendingImageJobId)
        try? secrets.set(model.model, for: SecretStoreKeys.pendingImageJobModel)
        mediaStatus = "Plane job \(id.prefix(12))… · unlock to refresh if locked"
        try await finishImageJob(id: id, fallbackModel: model.model, prompt: prompt)
        return
      }
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
      if (try? secrets.get(SecretStoreKeys.pendingImageJobId)) != nil {
        mediaStatus = "Paused (locked). Unlock to check plane job…"
        mediaError = nil
      } else {
        mediaError = PrismError.cancelled.userFacingMessage
        mediaStatus = nil
        Haptics.warning()
      }
    } catch {
      clearPendingImageJob()
      mediaError = prismUserFacingError(error)
      mediaStatus = "Failed after \(mediaElapsedSeconds)s · prompt kept for Retry"
      Haptics.error()
    }
  }

  private func finishImageJob(id: String, fallbackModel: String, prompt: String = "") async throws {
    let job = try await controlPlane.waitForJob(id: id, pollInterval: 4, timeout: 420)
    if !job.isSuccess {
      clearPendingImageJob()
      let msg = job.error?.message ?? job.error?.code ?? "Image job failed"
      throw PrismError.serverError(msg)
    }
    _ = prompt
    try await applyImageJobResult(job, fallbackModel: fallbackModel)
  }

  private func applyImageJobResult(_ job: AsyncJobResponse, fallbackModel: String) async throws {
    let url = job.result?.firstImageURL
    let b64 = job.result?.firstImageBase64
    guard url != nil || b64 != nil else {
      clearPendingImageJob()
      throw PrismError.serverError("Image job finished with no image")
    }
    clearPendingImageJob()
    lastImageBase64 = b64
    lastImageURL = url
    lastImageModel = job.result?.model ?? job.model ?? fallbackModel
    mediaStatus = "Done · \(lastImageModel ?? fallbackModel) · \(mediaElapsedSeconds)s"
    mediaError = nil
    pushMediaHistory(
      MediaHistoryItem(
        kind: .image,
        model: lastImageModel ?? fallbackModel,
        prompt: imagePrompt,
        imageBase64: lastImageBase64,
        imageURL: lastImageURL
      )
    )
    Haptics.success()
    await refreshPlaneBalanceOnly()
  }

  private func clearPendingImageJob() {
    try? secrets.set(nil, for: SecretStoreKeys.pendingImageJobId)
    try? secrets.set(nil, for: SecretStoreKeys.pendingImageJobModel)
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
    let duration = VideoDurationCatalog.limits(for: model.model).clamp(videoDurationSeconds)
    videoDurationSeconds = duration
    mediaStatus =
      "Generating \(model.model) · \(duration)s clip · often 1-3 min. Safe to lock; job continues on the plane."
    lastVideoURL = nil
    beginVideoBackgroundWork()
    startMediaTimer()
    defer {
      stopMediaTimer()
      mediaBusy = false
      endVideoBackgroundWork()
    }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateVideo(
        model: model.model,
        prompt: prompt.isEmpty ? " " : prompt,
        image: imageRef.isEmpty ? nil : imageRef,
        async: true,
        duration: duration
      )
      try Task.checkCancellation()
      if let id = res.id, res.video == nil {
        try? secrets.set(id, for: SecretStoreKeys.pendingVideoJobId)
        try? secrets.set(model.model, for: SecretStoreKeys.pendingVideoJobModel)
        mediaStatus = "Plane job \(id.prefix(12))… · unlock to refresh if locked"
        try await finishVideoJob(id: id, fallbackModel: model.model, prompt: prompt)
      } else {
        clearPendingVideoJob()
        guard let v = res.video, !v.isEmpty else {
          throw PrismError.serverError("Empty video payload")
        }
        lastVideoModel = res.model ?? model.model
        lastVideoURL = await Self.waitUntilMediaReachable(v) ?? v
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
        notifyVideoFinished(
          success: true,
          detail: "\(lastVideoModel ?? model.model) finished in \(mediaElapsedSeconds)s"
        )
        await refreshPlaneBalanceOnly()
      }
    } catch is CancellationError {
      if (try? secrets.get(SecretStoreKeys.pendingVideoJobId)) != nil {
        mediaStatus = "Paused (locked). Unlock to check plane job…"
        mediaError = nil
      } else {
        mediaError = PrismError.cancelled.userFacingMessage
        mediaStatus = nil
        Haptics.warning()
      }
    } catch {
      clearPendingVideoJob()
      mediaError = prismUserFacingError(error)
      mediaStatus = "Failed after \(mediaElapsedSeconds)s · prompt kept for Retry"
      notifyVideoFinished(success: false, detail: mediaError ?? "Video failed")
      Haptics.error()
    }
  }

  private func finishVideoJob(id: String, fallbackModel: String, prompt: String = "") async throws {
    let job = try await controlPlane.waitForJob(id: id, pollInterval: 4, timeout: 420)
    if !job.isSuccess {
      clearPendingVideoJob()
      let msg = job.error?.message ?? job.error?.code ?? "Video job failed"
      throw PrismError.serverError(msg)
    }
    // prompt arg kept for call sites; history uses current videoPrompt in apply.
    _ = prompt
    try await applyVideoJobResult(job, fallbackModel: fallbackModel)
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
    clearPendingSpeechJob()
    speechError = PrismError.cancelled.userFacingMessage
  }

  /// Fill speech field from a chat turn and synthesize.
  func speakText(_ text: String) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    speechText = t
    generateSpeech()
  }

  /// Play last TTS result. If already playing, stops (same control as Stop).
  func playLastSpeech() {
    #if canImport(AVFoundation) && os(iOS)
    if isSpeechPlaying {
      stopSpeechPlayback()
      return
    }
    guard let data = lastSpeechData else { return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      // One audio stream at a time in the app shell.
      if isMusicPlaying { stopMusicPlayback() }
      speechPlayer?.stop()
      speechPlayerFinish.onFinish = { [weak self] in
        Task { @MainActor in
          self?.isSpeechPlaying = false
        }
      }
      let player = try AVAudioPlayer(data: data)
      player.delegate = speechPlayerFinish
      speechPlayer = player
      player.prepareToPlay()
      player.play()
      isSpeechPlaying = true
      Haptics.light()
    } catch {
      speechError = "Could not play audio: \(error.localizedDescription)"
      isSpeechPlaying = false
      Haptics.error()
    }
    #endif
  }

  /// Stop in-app TTS playback. Does not affect music.
  func stopSpeechPlayback() {
    #if canImport(AVFoundation) && os(iOS)
    speechPlayer?.stop()
    speechPlayer = nil
    #endif
    isSpeechPlaying = false
    Haptics.light()
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
    speechStatus = "Synthesizing \(model.model)… (Workflow; safe to background)"
    stopSpeechPlayback()
    lastSpeechData = nil
    defer { speechBusy = false }
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateSpeech(
        model: model.model,
        input: text,
        async: true
      )
      try Task.checkCancellation()
      if let id = res.id, res.audioData == nil {
        try? secrets.set(id, for: SecretStoreKeys.pendingSpeechJobId)
        try? secrets.set(model.model, for: SecretStoreKeys.pendingSpeechJobModel)
        speechStatus = "Plane job \(id.prefix(12))… · will re-check when open"
        try await finishSpeechJob(id: id, fallbackModel: model.model)
      } else {
        clearPendingSpeechJob()
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
      }
    } catch is CancellationError {
      if (try? secrets.get(SecretStoreKeys.pendingSpeechJobId)) != nil {
        speechStatus = "Paused (background). Will re-check when open…"
        speechError = nil
      } else {
        speechError = PrismError.cancelled.userFacingMessage
        speechStatus = nil
        Haptics.warning()
      }
    } catch {
      clearPendingSpeechJob()
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
  /// Bumped on every new music poll / generate so a cancelled Task cannot overwrite UI.
  private var musicWorkGeneration: UInt64 = 0

  private func nextMusicGeneration() -> UInt64 {
    musicWorkGeneration += 1
    return musicWorkGeneration
  }

  private func isCurrentMusicGeneration(_ gen: UInt64) -> Bool {
    gen == musicWorkGeneration
  }

  func generateMusic() {
    musicTask?.cancel()
    let gen = nextMusicGeneration()
    musicTask = Task { await self.performGenerateMusic(generation: gen) }
  }

  func cancelMusic() {
    _ = nextMusicGeneration()
    musicTask?.cancel()
    musicTask = nil
    stopMusicTimer()
    musicBusy = false
    musicStatus = nil
    // Explicit user cancel: drop pending plane job tracking (job may still finish server-side).
    clearPendingMusicJob()
    musicError = PrismError.cancelled.userFacingMessage
  }

  /// Play last music result: inline bytes, or stream remote https URL.
  /// If already playing, stops (same control as Stop).
  func playLastMusic() {
    #if canImport(AVFoundation) && os(iOS)
    if isMusicPlaying {
      stopMusicPlayback()
      return
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      musicError = "Could not start audio session: \(error.localizedDescription)"
      Haptics.error()
      return
    }
    // One audio stream at a time in the app shell.
    if isSpeechPlaying { stopSpeechPlayback() }
    clearMusicEndObserver()
    if let data = lastMusicData {
      do {
        musicStreamPlayer?.pause()
        musicStreamPlayer = nil
        musicLocalPlayer?.stop()
        musicPlayerFinish.onFinish = { [weak self] in
          Task { @MainActor in
            self?.isMusicPlaying = false
          }
        }
        let player = try AVAudioPlayer(data: data)
        player.delegate = musicPlayerFinish
        musicLocalPlayer = player
        player.prepareToPlay()
        player.play()
        isMusicPlaying = true
        Haptics.light()
      } catch {
        musicError = "Could not play audio: \(error.localizedDescription)"
        isMusicPlaying = false
        Haptics.error()
      }
      return
    }
    if let urlStr = lastMusicAudio,
       let url = Self.musicPlaybackURL(from: urlStr)
    {
      musicLocalPlayer?.stop()
      musicLocalPlayer = nil
      let item = AVPlayerItem(url: url)
      let player = AVPlayer(playerItem: item)
      musicStreamPlayer = player
      musicEndObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.isMusicPlaying = false
        }
      }
      player.play()
      isMusicPlaying = true
      Haptics.light()
      return
    }
    musicError = "No playable audio on this result."
    Haptics.warning()
    #endif
  }

  /// Stop in-app music playback (local or streamed). Does not affect TTS.
  func stopMusicPlayback() {
    #if canImport(AVFoundation) && os(iOS)
    musicLocalPlayer?.stop()
    musicLocalPlayer = nil
    musicStreamPlayer?.pause()
    musicStreamPlayer = nil
    clearMusicEndObserver()
    #endif
    isMusicPlaying = false
    Haptics.light()
  }

  #if canImport(AVFoundation) && os(iOS)
  private func clearMusicEndObserver() {
    if let musicEndObserver {
      NotificationCenter.default.removeObserver(musicEndObserver)
      self.musicEndObserver = nil
    }
  }
  #endif

  /// Resolved https URL for the last music result (plane rehost or provider).
  var lastMusicPlaybackURL: URL? {
    guard let urlStr = lastMusicAudio else { return nil }
    return Self.musicPlaybackURL(from: urlStr)
  }

  /// Local file if we already saved/prefetched this result into Application Support.
  @Published var lastMusicLocalURL: URL?

  /// Directory for user-visible music saves (Application Support/Prism/Music).
  func musicLibraryDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("Prism/Music", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Download remote audio (or write inline bytes) into Prism/Music and set lastMusicLocalURL.
  @discardableResult
  func saveLastMusicToLibrary() async -> URL? {
    musicError = nil
    if let data = lastMusicData, !data.isEmpty {
      return writeMusicDataToLibrary(data)
    }
    guard let remote = lastMusicPlaybackURL else {
      musicError = "No audio to save."
      Haptics.warning()
      return nil
    }
    do {
      let (data, _) = try await URLSession.shared.data(from: remote)
      guard !data.isEmpty else {
        musicError = "Empty audio download."
        Haptics.error()
        return nil
      }
      lastMusicData = data
      return writeMusicDataToLibrary(data)
    } catch {
      musicError = "Could not download audio: \(error.localizedDescription)"
      Haptics.error()
      return nil
    }
  }

  private func writeMusicDataToLibrary(_ data: Data) -> URL? {
    let name = "prism-music-\(Int(Date().timeIntervalSince1970)).mp3"
    let url = musicLibraryDirectory().appendingPathComponent(name)
    do {
      try data.write(to: url, options: .atomic)
      lastMusicLocalURL = url
      musicStatus = "Saved · \(name)"
      Haptics.success()
      return url
    } catch {
      musicError = "Could not save audio: \(error.localizedDescription)"
      Haptics.error()
      return nil
    }
  }

  /// Prefetch plane/provider audio into memory so Play/Save work offline for a while.
  private func prefetchMusicIfNeeded(urlString: String) async {
    guard lastMusicData == nil,
          let url = Self.musicPlaybackURL(from: urlString)
    else { return }
    // Only auto-prefetch our play-proxy media URLs (stable, ours). Skip flaky third-party OSS.
    guard url.host?.contains("play-proxy") == true || url.path.contains("/v1/media/") else {
      return
    }
    if let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty {
      lastMusicData = data
    }
  }

  /// Parse play-proxy or provider URLs (percent-encoded path stays intact).
  private static func musicPlaybackURL(from raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let u = URL(string: trimmed), let scheme = u.scheme?.lowercased(),
       scheme == "http" || scheme == "https"
    {
      return u
    }
    return nil
  }

  private func performGenerateMusic(generation gen: UInt64) async {
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
    musicStatus =
      "Generating \(model.model) · often 2-4 min (up to ~5 with lyrics). Safe to lock; job continues on the plane."
    lastMusicAudio = nil
    lastMusicData = nil
    lastMusicLocalURL = nil
    beginMusicBackgroundWork()
    startMusicTimer()
    defer {
      // Only the current generation owns busy/timer; a superseded Task must not clear them.
      if isCurrentMusicGeneration(gen) {
        stopMusicTimer()
        musicBusy = false
        endMusicBackgroundWork()
      }
    }
    let lyrics = musicLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try Task.checkCancellation()
      let res = try await controlPlane.generateMusic(
        model: model.model,
        prompt: prompt,
        lyrics: lyrics.isEmpty ? nil : lyrics,
        async: true
      )
      try Task.checkCancellation()
      guard isCurrentMusicGeneration(gen) else { return }
      if let id = res.id, res.audio == nil {
        try? secrets.set(id, for: SecretStoreKeys.pendingMusicJobId)
        try? secrets.set(model.model, for: SecretStoreKeys.pendingMusicJobModel)
        musicStatus = "Plane job \(id.prefix(12))… · job runs on plane (lock OK)"
        try await finishMusicJob(id: id, fallbackModel: model.model)
      } else {
        clearPendingMusicJob()
        lastMusicAudio = res.audio
        lastMusicData = res.audioData
        lastMusicModel = res.model ?? model.model
        let detail = "\(lastMusicModel ?? model.model) · \(musicElapsedSeconds)s"
        musicStatus = "Done · \(detail)"
        Haptics.success()
        notifyMusicFinished(success: true, detail: detail)
        if lastMusicData == nil, let urlStr = lastMusicAudio {
          Task { await self.prefetchMusicIfNeeded(urlString: urlStr) }
        }
        await refreshPlaneBalanceOnly()
      }
    } catch is CancellationError {
      // Superseded by forceSync / new generate: leave UI alone.
      guard isCurrentMusicGeneration(gen) else { return }
      // Keep pending job id -- onBecomeActive force-sync resumes poll.
      if (try? secrets.get(SecretStoreKeys.pendingMusicJobId)) != nil {
        musicStatus = "Plane job continues · re-checks when app is active"
        musicError = nil
      } else {
        musicError = PrismError.cancelled.userFacingMessage
        musicStatus = "Cancelled after \(musicElapsedSeconds)s"
        Haptics.warning()
        notifyMusicFinished(success: false, detail: "Cancelled after \(musicElapsedSeconds)s")
      }
    } catch {
      guard isCurrentMusicGeneration(gen) else { return }
      // Once accepted, never drop the id on radio blips / poll timeout.
      if (try? secrets.get(SecretStoreKeys.pendingMusicJobId)) != nil,
         prismIsSuspendOrNetworkError(error)
      {
        musicStatus = "Plane job continues · re-checks when app is active"
        musicError = nil
        return
      }
      if (try? secrets.get(SecretStoreKeys.pendingMusicJobId)) != nil,
         prismIsSuspendOrNetworkError(error) == false
      {
        // Terminal-ish client error with pending: still keep id; forceSync is source of truth.
        musicStatus = "Plane job continues · \(prismUserFacingError(error))"
        musicError = nil
        return
      }
      clearPendingMusicJob()
      musicError = prismUserFacingError(error)
      musicStatus = "Failed after \(musicElapsedSeconds)s"
      Haptics.error()
      notifyMusicFinished(success: false, detail: musicError ?? "Failed")
    }
  }

  private func finishMusicJob(id: String, fallbackModel: String) async throws {
    let job = try await controlPlane.waitForJob(id: id, pollInterval: 4, timeout: 420)
    if !job.isTerminal {
      // Poll window ended while Workflow still running. Keep pending for forceSync.
      throw PrismError.serverError("Job still running on the plane")
    }
    if !job.isSuccess {
      clearPendingMusicJob()
      let msg = job.error?.message ?? job.error?.code ?? "Music job failed"
      throw PrismError.serverError(msg)
    }
    try await applyMusicJobResult(job, fallbackModel: fallbackModel)
  }

  private func finishSpeechJob(id: String, fallbackModel: String) async throws {
    let job = try await controlPlane.waitForJob(id: id, pollInterval: 3, timeout: 180)
    if !job.isTerminal {
      throw PrismError.serverError("Job still running on the plane")
    }
    if !job.isSuccess {
      clearPendingSpeechJob()
      let msg = job.error?.message ?? job.error?.code ?? "Speech job failed"
      throw PrismError.serverError(msg)
    }
    try await applySpeechJobResult(job, fallbackModel: fallbackModel)
  }

  private func clearPendingMusicJob() {
    try? secrets.set(nil, for: SecretStoreKeys.pendingMusicJobId)
    try? secrets.set(nil, for: SecretStoreKeys.pendingMusicJobModel)
  }

  private func clearPendingVideoJob() {
    try? secrets.set(nil, for: SecretStoreKeys.pendingVideoJobId)
    try? secrets.set(nil, for: SecretStoreKeys.pendingVideoJobModel)
  }

  /// Always re-query plane for any pending Workflow job.
  /// Does **not** gate on `musicBusy` / `mediaBusy` / `speechBusy`: those stay true while a
  /// suspended Task is stuck, which previously prevented resume after unlock.
  func forceSyncPendingJobs() async {
    if let id = try? secrets.get(SecretStoreKeys.pendingMusicJobId), !id.isEmpty {
      await syncOnePendingMusicJob(id: id)
    }
    if let id = try? secrets.get(SecretStoreKeys.pendingVideoJobId), !id.isEmpty {
      await syncOnePendingVideoJob(id: id)
    }
    if let id = try? secrets.get(SecretStoreKeys.pendingSpeechJobId), !id.isEmpty {
      await syncOnePendingSpeechJob(id: id)
    }
    if let id = try? secrets.get(SecretStoreKeys.pendingImageJobId), !id.isEmpty {
      await syncOnePendingImageJob(id: id)
    }
  }

  private func syncOnePendingImageJob(id: String) async {
    let model = (try? secrets.get(SecretStoreKeys.pendingImageJobModel)) ?? "image"
    do {
      let job = try await controlPlane.getJob(id: id)
      if job.isTerminal {
        mediaTask?.cancel()
        mediaBusy = true
        startMediaTimer()
        defer {
          stopMediaTimer()
          mediaBusy = false
        }
        if job.isSuccess {
          try await applyImageJobResult(job, fallbackModel: model)
        } else {
          clearPendingImageJob()
          mediaError = job.error?.message ?? job.error?.code ?? "Image job failed"
          mediaStatus = "Failed"
          Haptics.error()
        }
        return
      }
      mediaTask?.cancel()
      mediaBusy = true
      mediaError = nil
      mediaStatus = "Plane job \(id.prefix(12))… · still running"
      startMediaTimer()
      mediaTask = Task {
        defer {
          stopMediaTimer()
          mediaBusy = false
        }
        do {
          try await finishImageJob(id: id, fallbackModel: model)
        } catch is CancellationError {
          mediaStatus = "Paused (background). Will re-check when open…"
        } catch {
          clearPendingImageJob()
          mediaError = prismUserFacingError(error)
          mediaStatus = "Failed"
          Haptics.error()
        }
      }
    } catch {
      mediaStatus = "Plane job \(id.prefix(12))… · re-check pending"
    }
  }

  private func syncOnePendingMusicJob(id: String) async {
    let model = (try? secrets.get(SecretStoreKeys.pendingMusicJobModel)) ?? "music"
    do {
      let job = try await controlPlane.getJob(id: id)
      if job.isTerminal {
        musicTask?.cancel()
        musicBusy = true
        beginMusicBackgroundWork()
        startMusicTimer()
        defer {
          stopMusicTimer()
          musicBusy = false
          endMusicBackgroundWork()
        }
        if job.isSuccess {
          try await applyMusicJobResult(job, fallbackModel: model)
        } else {
          clearPendingMusicJob()
          musicError = job.error?.message ?? job.error?.code ?? "Music job failed"
          musicStatus = "Failed"
          Haptics.error()
          notifyMusicFinished(success: false, detail: musicError ?? "Failed")
        }
        return
      }
      // Still running on plane: restart poll (old Task may be hung after suspend).
      musicTask?.cancel()
      musicBusy = true
      musicError = nil
      musicStatus = "Plane job \(id.prefix(12))… · still running"
      beginMusicBackgroundWork()
      startMusicTimer()
      musicTask = Task {
        defer {
          stopMusicTimer()
          musicBusy = false
          endMusicBackgroundWork()
        }
        do {
          try await finishMusicJob(id: id, fallbackModel: model)
        } catch is CancellationError {
          musicStatus = "Paused (background). Will re-check when open…"
        } catch {
          clearPendingMusicJob()
          musicError = prismUserFacingError(error)
          musicStatus = "Failed"
          Haptics.error()
          notifyMusicFinished(success: false, detail: musicError ?? "Failed")
        }
      }
    } catch {
      // Network blip: keep pending id for next active.
      musicStatus = "Plane job \(id.prefix(12))… · re-check pending"
    }
  }

  private func syncOnePendingVideoJob(id: String) async {
    let model = (try? secrets.get(SecretStoreKeys.pendingVideoJobModel)) ?? "video"
    do {
      let job = try await controlPlane.getJob(id: id)
      if job.isTerminal {
        mediaTask?.cancel()
        mediaBusy = true
        beginVideoBackgroundWork()
        startMediaTimer()
        defer {
          stopMediaTimer()
          mediaBusy = false
          endVideoBackgroundWork()
        }
        if job.isSuccess {
          try await applyVideoJobResult(job, fallbackModel: model)
        } else {
          clearPendingVideoJob()
          mediaError = job.error?.message ?? job.error?.code ?? "Video job failed"
          mediaStatus = "Failed"
          Haptics.error()
          notifyVideoFinished(success: false, detail: mediaError ?? "Failed")
        }
        return
      }
      mediaTask?.cancel()
      mediaBusy = true
      mediaError = nil
      mediaStatus = "Plane job \(id.prefix(12))… · still running"
      beginVideoBackgroundWork()
      startMediaTimer()
      mediaTask = Task {
        defer {
          stopMediaTimer()
          mediaBusy = false
          endVideoBackgroundWork()
        }
        do {
          try await finishVideoJob(id: id, fallbackModel: model)
        } catch is CancellationError {
          mediaStatus = "Paused (background). Will re-check when open…"
        } catch {
          clearPendingVideoJob()
          mediaError = prismUserFacingError(error)
          mediaStatus = "Failed"
          Haptics.error()
          notifyVideoFinished(success: false, detail: mediaError ?? "Failed")
        }
      }
    } catch {
      mediaStatus = "Plane job \(id.prefix(12))… · re-check pending"
    }
  }

  private func syncOnePendingSpeechJob(id: String) async {
    let model = (try? secrets.get(SecretStoreKeys.pendingSpeechJobModel)) ?? "speech"
    do {
      let job = try await controlPlane.getJob(id: id)
      if job.isTerminal {
        speechTask?.cancel()
        speechBusy = true
        defer { speechBusy = false }
        if job.isSuccess {
          try await applySpeechJobResult(job, fallbackModel: model)
        } else {
          clearPendingSpeechJob()
          speechError = job.error?.message ?? job.error?.code ?? "Speech job failed"
          speechStatus = "Failed"
          Haptics.error()
        }
        return
      }
      speechTask?.cancel()
      speechBusy = true
      speechError = nil
      speechStatus = "Plane job \(id.prefix(12))… · still running"
      speechTask = Task {
        defer { speechBusy = false }
        do {
          try await finishSpeechJob(id: id, fallbackModel: model)
        } catch is CancellationError {
          speechStatus = "Paused (background). Will re-check when open…"
        } catch {
          clearPendingSpeechJob()
          speechError = prismUserFacingError(error)
          speechStatus = "Failed"
          Haptics.error()
        }
      }
    } catch {
      speechStatus = "Plane job \(id.prefix(12))… · re-check pending"
    }
  }

  private func applyMusicJobResult(_ job: AsyncJobResponse, fallbackModel: String) async throws {
    guard let audio = job.result?.audio, !audio.isEmpty else {
      clearPendingMusicJob()
      throw PrismError.serverError("Music job finished with no audio")
    }
    clearPendingMusicJob()
    lastMusicAudio = audio
    lastMusicData = nil
    lastMusicModel = job.result?.model ?? job.model ?? fallbackModel
    let detail = "\(lastMusicModel ?? fallbackModel) · \(musicElapsedSeconds)s"
    musicStatus = "Done · \(detail)"
    musicError = nil
    Haptics.success()
    notifyMusicFinished(success: true, detail: detail)
    if lastMusicData == nil, let urlStr = lastMusicAudio {
      Task { await self.prefetchMusicIfNeeded(urlString: urlStr) }
    }
    await refreshPlaneBalanceOnly()
  }

  private func applyVideoJobResult(_ job: AsyncJobResponse, fallbackModel: String) async throws {
    guard let v = job.result?.video, !v.isEmpty else {
      clearPendingVideoJob()
      throw PrismError.serverError("Video job finished with no URL")
    }
    clearPendingVideoJob()
    lastVideoModel = job.result?.model ?? job.model ?? fallbackModel
    lastVideoURL = await Self.waitUntilMediaReachable(v) ?? v
    mediaStatus = "Done · \(lastVideoModel ?? fallbackModel) · \(mediaElapsedSeconds)s"
    mediaError = nil
    pushMediaHistory(
      MediaHistoryItem(
        kind: .video,
        model: lastVideoModel ?? fallbackModel,
        prompt: videoPrompt,
        videoURL: lastVideoURL
      )
    )
    Haptics.success()
    notifyVideoFinished(
      success: true,
      detail: "\(lastVideoModel ?? fallbackModel) finished in \(mediaElapsedSeconds)s"
    )
    await refreshPlaneBalanceOnly()
  }

  private func applySpeechJobResult(_ job: AsyncJobResponse, fallbackModel: String) async throws {
    guard let audioURL = job.result?.audio, !audioURL.isEmpty else {
      clearPendingSpeechJob()
      throw PrismError.serverError("Speech job finished with no audio")
    }
    clearPendingSpeechJob()
    // Download signed media URL into lastSpeechData for AVAudioPlayer.
    if let url = URL(string: audioURL),
       let (data, _) = try? await URLSession.shared.data(from: url),
       !data.isEmpty
    {
      lastSpeechData = data
    } else {
      throw PrismError.serverError("Could not download speech audio")
    }
    lastSpeechFormat = job.result?.format ?? "mp3"
    lastSpeechModel = job.result?.model ?? job.model ?? fallbackModel
    speechStatus = "Done · \(lastSpeechModel ?? fallbackModel) · \((lastSpeechData?.count ?? 0) / 1024) KB"
    speechError = nil
    Haptics.success()
    playLastSpeech()
    await refreshPlaneBalanceOnly()
  }

  private func clearPendingSpeechJob() {
    try? secrets.set(nil, for: SecretStoreKeys.pendingSpeechJobId)
    try? secrets.set(nil, for: SecretStoreKeys.pendingSpeechJobModel)
  }

  func refreshPlaneBalanceOnly() async {
    guard deviceKeyPresent else { return }
    if let me = try? await controlPlane.me() {
      applyPlaneMe(me)
    }
  }

  /// Full period usage (`GET /v1/usage`) for the Usage screen.
  func fetchPlaneUsage() async throws -> UsageSummary {
    try await controlPlane.usage()
  }

  /// Chat send cost hint (token rates are not per-request exact).
  var chatSpendPreview: String? {
    guard let m = selectedModel else { return nil }
    var parts: [String] = []
    if let p = m.priceLabel, !p.isEmpty {
      if p == "included" {
        parts.append("Rate: included")
      } else {
        parts.append("Rate: \(p)")
      }
    }
    if m.supportsVision {
      parts.append(draftImageDataUrls.isEmpty ? "vision-capable" : "vision attach · metered")
    } else if !draftImageDataUrls.isEmpty {
      parts.append("warning: model may not support vision")
    }
    if useStream, m.streaming == true {
      parts.append("stream on")
    }
    if let g = m.group, !g.isEmpty { parts.append(g) }
    guard !parts.isEmpty else { return nil }
    return "Send: " + parts.joined(separator: " · ")
  }

  /// Paste image from clipboard into chat draft attachments.
  @discardableResult
  func pasteChatImageFromClipboard() -> Bool {
    #if canImport(UIKit)
    if let img = UIPasteboard.general.image,
       let data = img.jpegData(compressionQuality: 0.75)
    {
      attachChatImageJPEGData(data)
      return true
    }
    if let data = UIPasteboard.general.data(forPasteboardType: "public.jpeg")
      ?? UIPasteboard.general.data(forPasteboardType: "public.png")
    {
      attachChatImageJPEGData(data)
      return true
    }
    errorMessage = "No image on the clipboard."
    return false
    #else
    return false
    #endif
  }

  /// Transcribe recorded m4a bytes and append to the chat draft.
  func sttToChatDraft(audioData: Data, mime: String = "audio/mp4") {
    chatSttTask?.cancel()
    chatSttTask = Task { await performSttToChatDraft(audioData: audioData, mime: mime) }
  }

  /// If a transcript already exists (Audio tab), push it into the draft.
  func applyLastTranscriptToDraft() {
    guard let t = lastTranscript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
      errorMessage = "No transcript yet. Hold the mic to record, or use More → Audio."
      return
    }
    draft = draft.isEmpty ? t : (draft + " " + t)
    Haptics.light()
  }

  @Published var chatSttBusy = false
  private var chatSttTask: Task<Void, Never>?
  private var liveSttClient: LiveSTTClient?
  private var liveSttListenTask: Task<Void, Never>?
  private var liveSttFinals: [String] = []

  /// Start live Flux STT WebSocket (Bearer upgrade). Feed PCM via `sendLiveSttPCM`.
  func startLiveStt() async {
    guard canUseMediaDoors else {
      errorMessage = "Control plane + device key required for live speech-to-text."
      return
    }
    if !isNetworkSatisfied {
      errorMessage = "No network connection."
      return
    }
    guard let key = controlPlane.clientKey, !key.isEmpty else {
      errorMessage = "No device key."
      return
    }
    await stopLiveStt(commit: false)
    liveSttFinals = []
    liveSttPartial = ""
    liveSttStatus = "Connecting…"
    do {
      let url = try controlPlane.sttStreamURL()
      let client = LiveSTTClient()
      try await client.connect(streamURL: url, bearerKey: key)
      liveSttClient = client
      liveSttActive = true
      liveSttStatus = "Listening…"
      Haptics.light()
      liveSttListenTask = Task { [weak self] in
        guard let self else { return }
        for await event in await client.events() {
          await MainActor.run {
            self.handleLiveSttEvent(event)
          }
        }
        await MainActor.run {
          if self.liveSttActive {
            self.liveSttActive = false
            self.liveSttStatus = nil
          }
        }
      }
    } catch {
      liveSttActive = false
      liveSttStatus = nil
      errorMessage = prismUserFacingError(error)
      Haptics.error()
    }
  }

  func sendLiveSttPCM(_ data: Data) {
    guard liveSttActive, let client = liveSttClient else { return }
    Task {
      try? await client.sendPCM(data)
    }
  }

  /// Stop live STT. When `commit` is true, append finals + partial into the chat draft.
  func stopLiveStt(commit: Bool = true) async {
    liveSttListenTask?.cancel()
    liveSttListenTask = nil
    if let client = liveSttClient {
      await client.disconnect()
    }
    liveSttClient = nil
    let partial = liveSttPartial.trimmingCharacters(in: .whitespacesAndNewlines)
    if commit {
      var pieces = liveSttFinals
      if !partial.isEmpty { pieces.append(partial) }
      let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      if !joined.isEmpty {
        draft = draft.isEmpty ? joined : (draft + " " + joined)
        lastTranscript = joined
        banner = "Live transcript added to draft"
        Haptics.success()
        await refreshPlaneBalanceOnly()
      }
    }
    liveSttFinals = []
    liveSttPartial = ""
    liveSttActive = false
    liveSttStatus = nil
  }

  private func handleLiveSttEvent(_ event: LiveSTTClient.Event) {
    switch event {
    case .partial(let t):
      liveSttPartial = t
      liveSttStatus = "Listening…"
    case .final(let t):
      let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        liveSttFinals.append(trimmed)
      }
      liveSttPartial = ""
    case .raw:
      break
    case .closed(let reason):
      liveSttActive = false
      liveSttStatus = reason.map { "Closed: \($0)" }
    case .failed(let msg):
      liveSttActive = false
      liveSttStatus = nil
      errorMessage = msg
      Haptics.error()
    }
  }

  private func performSttToChatDraft(audioData: Data, mime: String) async {
    guard canUseMediaDoors else {
      errorMessage = "Control plane + device key required for speech-to-text."
      return
    }
    if !isNetworkSatisfied {
      errorMessage = "No network connection."
      return
    }
    guard let model = selectedSttModel ?? sttModels.first else {
      errorMessage = "No STT model available."
      return
    }
    chatSttBusy = true
    errorMessage = nil
    defer { chatSttBusy = false }
    setSttAudioData(audioData, mime: mime, label: "chat-mic")
    do {
      let res = try await controlPlane.transcribe(model: model.model, audio: sttAudioPayload)
      let t = (res.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty else {
        errorMessage = "Empty transcript."
        return
      }
      lastTranscript = t
      draft = draft.isEmpty ? t : (draft + " " + t)
      banner = "Transcript added to draft"
      Haptics.success()
      await refreshPlaneBalanceOnly()
    } catch {
      errorMessage = prismUserFacingError(error)
      Haptics.error()
    }
  }

  /// Background task ids while long gens run (iOS).
  ///
  /// Reality check: video/music are **synchronous** plane POSTs that hold the
  /// connection open for minutes. iOS does not guarantee that survives lock or
  /// leaving the app (`beginBackgroundTask` is ~30s; background URLSession is
  /// built for file transfer, not multi-minute idle server waits). What we *can*
  /// do: keep the screen awake so auto-lock does not kill the run, and take a
  /// short background grace on brief app switches. Honest UI must not claim lock-safe.
  #if canImport(UIKit)
  private var videoBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var musicBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  #endif

  func beginVideoBackgroundWork() {
    #if canImport(UIKit)
    endVideoBackgroundWork()
    videoBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "prism.video") { [weak self] in
      self?.endVideoBackgroundWork()
    }
    // Prevent auto-lock while Prism is still foreground; does not survive manual lock.
    UIApplication.shared.isIdleTimerDisabled = true
    #endif
  }

  func endVideoBackgroundWork() {
    #if canImport(UIKit)
    if videoBackgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(videoBackgroundTask)
      videoBackgroundTask = .invalid
    }
    if musicBackgroundTask == .invalid {
      UIApplication.shared.isIdleTimerDisabled = false
    }
    #endif
  }

  func beginMusicBackgroundWork() {
    #if canImport(UIKit)
    endMusicBackgroundWork()
    musicBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "prism.music") { [weak self] in
      self?.endMusicBackgroundWork()
    }
    UIApplication.shared.isIdleTimerDisabled = true
    #endif
  }

  func endMusicBackgroundWork() {
    #if canImport(UIKit)
    if musicBackgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(musicBackgroundTask)
      musicBackgroundTask = .invalid
    }
    if videoBackgroundTask == .invalid {
      UIApplication.shared.isIdleTimerDisabled = false
    }
    #endif
  }

  func notifyVideoFinished(success: Bool, detail: String) {
    notifyLongRunFinished(kind: "Video", success: success, detail: detail)
  }

  func notifyMusicFinished(success: Bool, detail: String) {
    notifyLongRunFinished(kind: "Music", success: success, detail: detail)
  }

  private func notifyLongRunFinished(kind: String, success: Bool, detail: String) {
    #if canImport(UIKit)
    let content = UNMutableNotificationContent()
    content.title = success ? "\(kind) ready" : "\(kind) failed"
    content.body = detail
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: "prism.\(kind.lowercased()).\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(req)
    #endif
  }

  /// StoreKit 2 signed transaction → prepaid credit on this device's account.
  func redeemStoreTransaction(jws: String) async throws -> StoreRedeemResponse {
    try await controlPlane.redeemStore(signedTransaction: jws)
  }
}
