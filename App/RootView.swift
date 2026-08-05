import SwiftUI
import PrismKit

struct RootView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    NavigationStack {
      Group {
        if state.needsPlaygroundLogin {
          LoginView()
        } else if state.needsPlaneEnroll {
          EnrollView()
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
    .environmentObject(AppState(secrets: MemorySecretStore()))
}
