import SwiftUI

struct RootView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    NavigationStack {
      Group {
        if state.authMode == "public", !state.authenticated {
          LoginView()
        } else {
          ChatView()
        }
      }
      .navigationTitle("Prism")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            SettingsView()
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
    }
    .task {
      await state.bootstrap()
    }
  }
}

#Preview {
  RootView()
    .environmentObject(AppState())
}
