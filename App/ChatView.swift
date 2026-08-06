import SwiftUI
import PrismKit
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
  @EnvironmentObject private var state: AppState
  @FocusState private var draftFocused: Bool
  @State private var sharePayload: ShareTextPayload?

  var body: some View {
    VStack(spacing: 0) {
      if let banner = state.banner {
        Text(banner)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 6)
      }

      ModelPickerView()
        .padding(.horizontal)
        .padding(.bottom, 4)

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
                onUseAsDraft: { state.useTurnAsDraft(turn) }
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
        }
        .padding(.horizontal)
      }

      Divider()

      HStack(alignment: .bottom, spacing: 8) {
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
          .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityLabel("Send message")
        }
      }
      .padding()
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("New chat") {
          state.newChat()
          Haptics.light()
        }
        .disabled(state.turns.isEmpty && state.conversationId == nil)
        .accessibilityLabel("Start new chat")
        .accessibilityHint("Clears conversation context")
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
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    guard let last = state.turns.last else { return }
    withAnimation(.easeOut(duration: 0.15)) {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }
}

/// First-paint guidance when the transcript is empty.
private struct ChatEmptyState: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    VStack(spacing: 12) {
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
    }
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var subtitle: String {
    if state.backend == .controlPlane {
      return "Messages stay on this device. Switch models anytime; context is kept until New chat."
    }
    return "Pick a model above and type a message. Streaming is on by default when the model supports it."
  }
}

private struct TurnBubble: View {
  let turn: ChatTurn
  var isStreaming: Bool = false
  var onUseAsDraft: (() -> Void)?

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
        Group {
          if isStreaming {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Thinking…")
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Generating response")
          } else if turn.text.isEmpty {
            Text("…")
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
