import SwiftUI
import PrismKit

struct ChatView: View {
  @EnvironmentObject private var state: AppState
  @FocusState private var draftFocused: Bool

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
            ForEach(state.turns) { turn in
              TurnBubble(turn: turn)
                .id(turn.id)
            }
          }
          .padding()
        }
        .onChange(of: state.turns.count) { _ in
          if let last = state.turns.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
      }

      if let err = state.errorMessage {
        Text(err)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal)
      }

      Divider()

      HStack(alignment: .bottom, spacing: 8) {
        TextField("Message", text: $state.draft, axis: .vertical)
          .lineLimit(1...6)
          .textFieldStyle(.roundedBorder)
          .focused($draftFocused)
          .disabled(state.isBusy)
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
          }
          .accessibilityLabel("Cancel")
        } else {
          Button {
            state.send()
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
          }
          .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding()
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("New chat") {
          state.newChat()
        }
        .disabled(state.turns.isEmpty && state.conversationId == nil)
      }
      if state.backend == .playground, state.authenticated {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Sign out") {
            Task { await state.logout() }
          }
        }
      }
    }
  }
}

private struct TurnBubble: View {
  let turn: ChatTurn

  var body: some View {
    HStack {
      if turn.role == .user { Spacer(minLength: 40) }
      VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
        Text(turn.role == .user ? "You" : "Prism")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(turn.text.isEmpty ? "…" : turn.text)
          .textSelection(.enabled)
          .padding(10)
          .background(turn.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      if turn.role != .user { Spacer(minLength: 40) }
    }
  }
}

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
