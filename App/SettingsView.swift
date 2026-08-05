import SwiftUI
import PrismKit

struct SettingsView: View {
  @EnvironmentObject private var state: AppState
  @State private var draftURL: String = ""

  var body: some View {
    Form {
      Section {
        TextField("Base URL", text: $draftURL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .textContentType(.URL)
        Button("Apply and reload") {
          state.baseURLString = draftURL
          state.rebuildClient()
          Task { await state.refreshModels() }
        }
        Button("Use play.skyphusion.org") {
          draftURL = PrismClient.playBaseURL.absoluteString
          state.baseURLString = draftURL
          state.rebuildClient()
          Task { await state.refreshModels() }
        }
      } header: {
        Text("Playground server")
      } footer: {
        Text(
          "Public playground needs signup. Self-host Access mode can chat without this app's login when the Worker trusts Access (or local anonymous)."
        )
      }

      Section {
        row("Mode", state.authMode ?? "unknown")
        row("Signed in", state.authenticated ? (state.sessionUsername ?? "yes") : "no")
        row("Models", "\(state.models.count)")
        row("Kit", "\(PrismKit.name) \(PrismKit.version)")
      } header: {
        Text("Session")
      }

      Section {
        Button("Refresh models") {
          Task { await state.refreshModels() }
        }
        if state.authenticated {
          Button("Sign out", role: .destructive) {
            Task { await state.logout() }
          }
        }
      }

      if let err = state.errorMessage {
        Section {
          Text(err).foregroundStyle(.red).font(.footnote)
        }
      }
    }
    .navigationTitle("Settings")
    .onAppear {
      draftURL = state.baseURLString
    }
  }

  @ViewBuilder
  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
      .environmentObject(AppState())
  }
}
