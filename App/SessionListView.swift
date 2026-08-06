import SwiftUI
import PrismKit

/// Local multi-session chat list (saved under Application Support).
struct SessionListView: View {
  @EnvironmentObject private var state: AppState
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      Section {
        Button {
          state.newChat()
          Haptics.light()
          dismiss()
        } label: {
          Label("New chat", systemImage: "plus.bubble")
            .frame(minHeight: 44)
        }
      }

      Section {
        if state.sessions.isEmpty {
          Text("No saved chats yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ForEach(state.sessions) { session in
            Button {
              state.openSession(session.id)
              dismiss()
            } label: {
              HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(session.title)
                    .font(.body.weight(session.id == state.currentSessionId ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                  Text(meta(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if session.id == state.currentSessionId {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Current chat")
                }
              }
              .frame(minHeight: 44)
            }
            .accessibilityLabel("Open chat \(session.title)")
          }
          .onDelete(perform: delete)
        }
      } header: {
        Text("Chats")
      } footer: {
        Text("Stored on this device only (not on the plane). Max \(50) chats. Swipe to delete.")
      }
    }
    .navigationTitle("Chats")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Done") { dismiss() }
      }
    }
  }

  private func meta(_ s: ChatSession) -> String {
    let n = s.turns.filter { $0.role == .user || $0.role == .assistant }.count
    let turns = "\(n) turn\(n == 1 ? "" : "s")"
    let when = s.updatedAt.formatted(date: .abbreviated, time: .shortened)
    return "\(turns) · \(when)"
  }

  private func delete(at offsets: IndexSet) {
    let ids = offsets.map { state.sessions[$0].id }
    for id in ids {
      state.deleteSession(id)
    }
  }
}

#Preview {
  NavigationStack {
    SessionListView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
