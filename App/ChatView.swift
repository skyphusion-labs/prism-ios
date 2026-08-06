import SwiftUI
import PrismKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
  @EnvironmentObject private var state: AppState
  @FocusState private var draftFocused: Bool
  @State private var sharePayload: ShareTextPayload?
  @State private var showSessions = false
  @State private var photoItem: PhotosPickerItem?
  @StateObject private var chatRecorder = AudioRecorder()
  @StateObject private var liveMic = LivePCMCapture()
  @State private var showCamera = false

  var body: some View {
    VStack(spacing: 0) {
      if !state.isNetworkSatisfied {
        Text("Offline · reconnect to send or generate")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 6)
          .background(Color.orange)
          .accessibilityLabel("No network connection")
      }
      if let banner = state.banner {
        Text(banner)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 6)
      }
      if let cost = state.lastRequestCost {
        Text(cost)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.bottom, 2)
          .accessibilityLabel(cost)
      }
      if state.liveSttActive || state.liveSttStatus != nil {
        HStack(spacing: 8) {
          Image(systemName: "waveform")
            .foregroundStyle(.red)
          VStack(alignment: .leading, spacing: 2) {
            Text(state.liveSttStatus ?? "Live STT")
              .font(.caption.weight(.semibold))
            if !state.liveSttPartial.isEmpty {
              Text(state.liveSttPartial)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer()
          Button("Stop") {
            Task { await stopLiveListen() }
          }
          .font(.caption.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
        .accessibilityElement(children: .combine)
      }

      ModelPickerView()
        .padding(.horizontal)
        .padding(.bottom, 4)

      if state.canCompactConversation || state.canExpandConversation || state.isCompacted {
        CompactBar()
          .padding(.horizontal)
          .padding(.bottom, 6)
      }

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            if state.turns.isEmpty {
              ChatEmptyState()
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            }
            ForEach(state.turns) { turn in
              TurnBubble(
                turn: turn,
                isStreaming: state.isBusy
                  && turn.role == .assistant
                  && turn.id == state.turns.last?.id
                  && turn.text.isEmpty,
                canRegenerate: state.canRegenerateLastReply
                  && turn.id == state.turns.last?.id
                  && turn.role == .assistant,
                canSpeak: state.canUseMediaDoors
                  && !state.speechModels.isEmpty
                  && turn.role == .assistant
                  && !turn.text.isEmpty
                  && !turn.text.hasPrefix("(error)")
                  && !turn.text.hasPrefix("(cancelled)"),
                onUseAsDraft: { state.useTurnAsDraft(turn) },
                onRegenerate: { state.regenerateLastReply() },
                onSpeak: { state.speakText(turn.text) }
              )
              .id(turn.id)
            }
          }
          .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
          await state.refreshModels()
        }
        .onChange(of: state.turns.count) { _ in
          scrollToBottom(proxy)
        }
        .onChange(of: state.turns.last?.text) { _ in
          scrollToBottom(proxy)
        }
      }

      if let err = state.errorMessage {
        VStack(alignment: .leading, spacing: 6) {
          Text(err)
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
          if state.canRetryLastChat, !state.isBusy {
            Button {
              state.retryLastFailedChat()
            } label: {
              Label("Retry last message", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Retry last failed message")
          }
          if state.canRegenerateLastReply {
            Button {
              state.regenerateLastReply()
            } label: {
              Label("Regenerate reply", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Regenerate last assistant reply")
          }
        }
        .padding(.horizontal)
      }

      Divider()

      if !state.draftImageDataUrls.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(Array(state.draftImageDataUrls.enumerated()), id: \.offset) { idx, url in
              ZStack(alignment: .topTrailing) {
                draftThumb(url)
                  .frame(width: 56, height: 56)
                  .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                  state.removeDraftImage(at: idx)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                }
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove attachment \(idx + 1)")
              }
            }
          }
          .padding(.horizontal)
          .padding(.top, 8)
        }
      }

      HStack(alignment: .bottom, spacing: 8) {
        Menu {
          PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            Label("Photo library", systemImage: "photo.on.rectangle")
          }
          Button {
            showCamera = true
          } label: {
            Label("Take photo", systemImage: "camera")
          }
          Button {
            _ = state.pasteChatImageFromClipboard()
          } label: {
            Label("Paste image", systemImage: "doc.on.clipboard")
          }
        } label: {
          Image(systemName: "photo.on.rectangle")
            .font(.title3)
            .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(state.isBusy || state.draftImageDataUrls.count >= 3)
        .accessibilityLabel("Attach photo")
        .accessibilityHint("Library, camera, or clipboard. Up to three images for vision models")
        .onChange(of: photoItem) { newItem in
          guard let newItem else { return }
          Task {
            if let data = try? await newItem.loadTransferable(type: Data.self) {
              #if canImport(UIKit)
              let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.75) ?? data
              state.attachChatImageJPEGData(jpeg)
              #else
              state.attachChatImageJPEGData(data)
              #endif
            }
            photoItem = nil
          }
        }

        // Record (file STT) or Live (WebSocket Flux) → draft
        Menu {
          Button {
            Task { await toggleChatMic() }
          } label: {
            Label(
              chatRecorder.isRecording ? "Stop recording" : "Record (file STT)",
              systemImage: "mic"
            )
          }
          Button {
            Task { await toggleLiveListen() }
          } label: {
            Label(
              state.liveSttActive ? "Stop live listen" : "Live listen (WebSocket)",
              systemImage: "waveform"
            )
          }
          .disabled(!state.canUseMediaDoors)
        } label: {
          Image(
            systemName: chatRecorder.isRecording || state.liveSttActive || state.chatSttBusy
              ? "stop.circle.fill"
              : "mic.circle"
          )
          .font(.title2)
          .foregroundStyle(
            chatRecorder.isRecording || state.liveSttActive ? .red : .primary
          )
          .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(state.isBusy && !chatRecorder.isRecording && !state.liveSttActive)
        .accessibilityLabel(
          state.liveSttActive
            ? "Live speech to text active"
            : (chatRecorder.isRecording ? "Stop recording" : "Speech to text")
        )
        .accessibilityHint("Record file STT or live WebSocket listen. Transcript goes into the draft.")

        TextField("Message", text: $state.draft, axis: .vertical)
          .lineLimit(1...6)
          .textFieldStyle(.roundedBorder)
          .font(.body)
          .focused($draftFocused)
          .disabled(state.isBusy)
          .accessibilityLabel("Message")
          .onSubmit {
            state.send()
          }

        if state.isBusy {
          Button {
            state.cancelChat()
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.title2)
              .foregroundStyle(.red)
              .frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel("Cancel generation")
        } else {
          Button {
            state.send()
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
              .frame(minWidth: 44, minHeight: 44)
          }
          .disabled(
            state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              && state.draftImageDataUrls.isEmpty
          )
          .accessibilityLabel("Send message")
        }
      }
      .padding()
      #if canImport(UIKit)
      .fullScreenCover(isPresented: $showCamera) {
        CameraPicker { data in
          if let data {
            state.attachChatImageJPEGData(data)
          }
          showCamera = false
        }
        .ignoresSafeArea()
      }
      #endif
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          showSessions = true
        } label: {
          Image(systemName: "list.bullet")
        }
        .accessibilityLabel("Chat list")
        .accessibilityHint("Open saved conversations")
      }
      ToolbarItem(placement: .topBarLeading) {
        Button("New") {
          state.newChat()
          Haptics.light()
        }
        .disabled(state.turns.isEmpty && state.conversationId == nil)
        .accessibilityLabel("Start new chat")
        .accessibilityHint("Saves current chat and opens a blank one")
      }
      if state.canRegenerateLastReply {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            state.regenerateLastReply()
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
          }
          .accessibilityLabel("Regenerate last reply")
          .accessibilityHint("Re-runs the last user message with the current model")
        }
      }
      if !state.turns.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            let text = state.chatTranscriptText()
            guard !text.isEmpty else { return }
            sharePayload = ShareTextPayload(text: text)
            Haptics.light()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share transcript")
        }
      }
      if state.backend == .controlPlane, let bal = state.planeBalance, !bal.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Text(bal)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("Balance \(bal)")
        }
      }
      if state.backend == .playground, state.authenticated {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Sign out") {
            Task { await state.logout() }
          }
        }
      }
    }
    .sheet(item: $sharePayload) { payload in
      #if canImport(UIKit)
      ActivityView(items: [payload.text])
      #else
      Text(payload.text)
      #endif
    }
    .sheet(isPresented: $showSessions) {
      NavigationStack {
        SessionListView()
      }
      .environmentObject(state)
    }
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    guard let last = state.turns.last else { return }
    withAnimation(.easeOut(duration: 0.15)) {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }
}

/// Compact / expand controls (playground API or plane client-side).
private struct CompactBar: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    HStack(spacing: 8) {
      if state.isCompacted {
        Label("Compacted", systemImage: "arrow.down.right.and.arrow.up.left")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.orange)
          .accessibilityLabel("Conversation is compacted for model context")
      } else if state.completedChatPairCount >= ConversationCompact.minTurnsToCompact {
        Text("\(state.completedChatPairCount) turns · compact shrinks model context")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      if state.compactBusy {
        ProgressView()
          .controlSize(.small)
      } else if state.canExpandConversation {
        Button("Expand") {
          state.expandConversation()
        }
        .font(.caption.weight(.semibold))
        .accessibilityLabel("Expand conversation history")
        .accessibilityHint("Next send uses full transcript again")
      } else if state.canCompactConversation {
        Button("Compact") {
          state.compactConversation()
        }
        .font(.caption.weight(.semibold))
        .accessibilityLabel("Compact conversation")
        .accessibilityHint("Summarize older turns for the model; UI transcript stays full")
      }
    }
    .frame(minHeight: 28)
  }
}

/// First-paint guidance when the transcript is empty.
private struct ChatEmptyState: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("Start a conversation")
        .font(.title3.weight(.semibold))
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      if let model = state.selectedModel {
        Text("Using \(model.label ?? model.model)")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      if state.backend == .controlPlane, state.planeHealthOK == false {
        Text("Plane health: unreachable. Pull to refresh or check Settings.")
          .font(.caption)
          .foregroundStyle(.orange)
          .multilineTextAlignment(.center)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Try a starter")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(AppState.starterPrompts, id: \.self) { prompt in
          Button {
            state.applyStarterPrompt(prompt)
          } label: {
            Text(prompt)
              .font(.footnote)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
              .background(Color.secondary.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .buttonStyle(.plain)
          .frame(minHeight: 44)
          .accessibilityLabel("Starter: \(prompt)")
        }
      }
      .frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }

  private var subtitle: String {
    if state.backend == .controlPlane {
      return "Messages stay on this device (plane privacy). Attach photos for vision models. Compact summarizes older turns."
    }
    return "Pick a model and type a message. Attach photos for vision. Sync cloud history from the chat list when signed in."
  }
}

extension ChatView {
  @ViewBuilder
  fileprivate func draftThumb(_ dataURL: String) -> some View {
    #if canImport(UIKit)
    if let ui = decodeDataURLImage(dataURL) {
      Image(uiImage: ui).resizable().scaledToFill()
    } else {
      Color.secondary.opacity(0.2)
    }
    #else
    Color.secondary.opacity(0.2)
    #endif
  }

  @MainActor
  fileprivate func toggleChatMic() async {
    if state.liveSttActive {
      await stopLiveListen()
    }
    if chatRecorder.isRecording {
      if let captured = chatRecorder.stop() {
        state.sttToChatDraft(audioData: captured.data, mime: "audio/mp4")
      }
      return
    }
    if state.chatSttBusy { return }
    let ok = await chatRecorder.requestPermission()
    guard ok else {
      state.errorMessage = "Microphone permission denied. Enable it in Settings."
      return
    }
    do {
      try chatRecorder.start()
      Haptics.light()
    } catch {
      state.errorMessage = prismUserFacingError(error)
    }
  }

  @MainActor
  fileprivate func toggleLiveListen() async {
    if state.liveSttActive {
      await stopLiveListen()
      return
    }
    if chatRecorder.isRecording {
      _ = chatRecorder.stop()
    }
    let ok = await liveMic.requestPermission()
    guard ok else {
      state.errorMessage = "Microphone permission denied. Enable it in Settings."
      return
    }
    liveMic.onPCM = { data in
      state.sendLiveSttPCM(data)
    }
    await state.startLiveStt()
    guard state.liveSttActive else { return }
    do {
      try liveMic.start()
    } catch {
      await state.stopLiveStt(commit: false)
      state.errorMessage = prismUserFacingError(error)
    }
  }

  @MainActor
  fileprivate func stopLiveListen() async {
    liveMic.stop()
    liveMic.onPCM = nil
    await state.stopLiveStt(commit: true)
  }
}

#if canImport(UIKit)
/// Simple UIImagePickerController camera wrapper.
private struct CameraPicker: UIViewControllerRepresentable {
  var onFinish: (Data?) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let p = UIImagePickerController()
    p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    p.delegate = context.coordinator
    p.allowsEditing = false
    return p
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onFinish: (Data?) -> Void
    init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onFinish(nil)
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
      onFinish(img?.jpegData(compressionQuality: 0.75))
    }
  }
}
#endif

#if canImport(UIKit)
private func decodeDataURLImage(_ dataURL: String) -> UIImage? {
  var s = dataURL
  if let r = s.range(of: "base64,") { s = String(s[r.upperBound...]) }
  guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { return nil }
  return UIImage(data: data)
}
#endif

private struct TurnBubble: View {
  let turn: ChatTurn
  var isStreaming: Bool = false
  var canRegenerate: Bool = false
  var canSpeak: Bool = false
  var onUseAsDraft: (() -> Void)?
  var onRegenerate: (() -> Void)?
  var onSpeak: (() -> Void)?

  var body: some View {
    HStack {
      if turn.role == .user { Spacer(minLength: 40) }
      VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(turn.role == .user ? "You" : "Prism")
            .font(.caption2)
            .foregroundStyle(.secondary)
          if turn.role == .assistant, let label = turn.modelLabel ?? turn.modelId {
            Text(label)
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
              .accessibilityLabel("Model \(label)")
          }
        }
        if let urls = turn.imageDataUrls, !urls.isEmpty {
          HStack(spacing: 6) {
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
              #if canImport(UIKit)
              if let ui = decodeDataURLImage(url) {
                Image(uiImage: ui)
                  .resizable()
                  .scaledToFill()
                  .frame(width: 72, height: 72)
                  .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              }
              #endif
            }
          }
          .accessibilityLabel("\(urls.count) attached image\(urls.count == 1 ? "" : "s")")
        }
        Group {
          if isStreaming {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Thinking…")
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Generating response")
          } else if turn.text.isEmpty || turn.text == "(image)" {
            if turn.imageDataUrls?.isEmpty != false {
              Text("…")
            }
          } else if let attr = try? AttributedString(
            markdown: turn.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
          ) {
            Text(attr)
          } else {
            Text(turn.text)
          }
        }
        .font(.body)
        .textSelection(.enabled)
        .padding(10)
        .background(turn.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
          if !turn.text.isEmpty {
            Button("Copy") {
              #if canImport(UIKit)
              UIPasteboard.general.string = turn.text
              #endif
              Haptics.light()
            }
            Button("Use as draft") {
              onUseAsDraft?()
              Haptics.light()
            }
          }
          if canRegenerate {
            Button("Regenerate") {
              onRegenerate?()
            }
          }
          if canSpeak {
            Button("Speak") {
              onSpeak?()
            }
          }
        }
      }
      if turn.role != .user { Spacer(minLength: 40) }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ShareTextPayload: Identifiable {
  let id = UUID()
  let text: String
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
  NavigationStack {
    ChatView()
      .environmentObject({
        let s = AppState(secrets: MemorySecretStore())
        s.authMode = "access"
        s.authenticated = true
        s.models = [
          ModelEntry(model: "demo", label: "Demo", type: "chat", streaming: true),
        ]
        s.selectedModelId = "demo"
        s.turns = [
          ChatTurn(role: .user, text: "Hello"),
          ChatTurn(role: .assistant, text: "Hi there."),
        ]
        return s
      }())
  }
}
