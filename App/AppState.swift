import Foundation
import PrismKit
import SwiftUI

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

@MainActor
final class AppState: ObservableObject {
  // MARK: - Connection

  /// Playground base URL (public or self-host).
  @Published var baseURLString: String = PrismClient.playBaseURL.absoluteString

  // MARK: - Auth

  @Published var username: String = ""
  @Published var password: String = ""
  @Published var authenticated: Bool = false
  @Published var sessionUsername: String?

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

  private var client: PrismClient

  init() {
    client = PrismClient(baseURL: PrismClient.playBaseURL)
  }

  var chatModels: [ModelEntry] {
    models.filter { ($0.type ?? "chat") == "chat" }
  }

  var selectedModel: ModelEntry? {
    chatModels.first { $0.model == selectedModelId } ?? chatModels.first
  }

  // MARK: - Lifecycle

  func bootstrap() async {
    rebuildClient()
    await refreshModels()
  }

  func rebuildClient() {
    let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = URL(string: trimmed) ?? PrismClient.playBaseURL
    client = PrismClient(baseURL: url)
    authenticated = false
    sessionUsername = nil
    conversationId = nil
    turns = []
  }

  func refreshModels() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      let res = try await client.models()
      models = res.models
      authMode = res.mode
      authenticated = res.authenticated == true
      sessionUsername = res.username
      if selectedModelId == nil {
        selectedModelId = chatModels.first(where: { $0.streaming == true })?.model
          ?? chatModels.first?.model
      }
      banner = statusBanner(from: res)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func statusBanner(from res: ModelsResponse) -> String {
    let mode = res.mode ?? "unknown"
    if res.authenticated == true {
      let who = res.username ?? res.user ?? "signed in"
      return "\(mode) · \(who) · \(res.models.count) models"
    }
    return "\(mode) · not signed in · \(res.models.count) models"
  }

  // MARK: - Auth

  func login() async {
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      let res = try await client.login(username: username, password: password)
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
      let res = try await client.signup(username: username, password: password)
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
    do {
      try await client.logout()
    } catch {
      // Still clear local session state.
      errorMessage = error.localizedDescription
    }
    authenticated = false
    sessionUsername = nil
    conversationId = nil
    turns = []
    await refreshModels()
  }

  // MARK: - Chat

  func send() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    guard let model = selectedModel else {
      errorMessage = "Pick a chat model first."
      return
    }
    if authMode == "public", !authenticated {
      errorMessage = "Sign in (or sign up) before chatting on the public playground."
      return
    }

    draft = ""
    turns.append(ChatTurn(role: .user, text: text))
    let assistantId = UUID()
    turns.append(ChatTurn(id: assistantId, role: .assistant, text: ""))

    isBusy = true
    errorMessage = nil
    defer { isBusy = false }

    let body = ChatRequestBody(
      model: model.model,
      userInput: text,
      conversationId: conversationId
    )

    do {
      if useStream, model.streaming == true {
        let (streamed, final) = try await client.chatStreamText(body)
        updateAssistant(id: assistantId, text: streamed.isEmpty ? (final?.output ?? "") : streamed)
        if let cid = final?.conversation_id { conversationId = cid }
      } else {
        let res = try await client.chat(body)
        updateAssistant(id: assistantId, text: res.output ?? "")
        if let cid = res.conversation_id { conversationId = cid }
      }
    } catch {
      updateAssistant(id: assistantId, text: "(error) \(error.localizedDescription)")
      errorMessage = error.localizedDescription
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
