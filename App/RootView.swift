import SwiftUI
import PrismKit

struct RootView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    Group {
      if state.needsPlaygroundLogin {
        NavigationStack {
          LoginView()
            .navigationTitle("Prism")
            .toolbar { settingsLink }
        }
      } else if state.needsPlaneEnroll {
        NavigationStack {
          EnrollView()
            .navigationTitle("Prism")
            .toolbar { settingsLink }
        }
      } else if state.backend == .controlPlane {
        // Plane: chat + image + video doors
        TabView {
          NavigationStack {
            ChatView()
              .navigationTitle("Chat")
              .toolbar { settingsLink }
          }
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

          NavigationStack {
            MediaGenerateView(kind: .image)
              .toolbar { settingsLink }
          }
          .tabItem { Label("Image", systemImage: "photo") }

          NavigationStack {
            MediaGenerateView(kind: .video)
              .toolbar { settingsLink }
          }
          .tabItem { Label("Video", systemImage: "film") }
        }
      } else {
        NavigationStack {
          ChatView()
            .navigationTitle("Prism")
            .toolbar { settingsLink }
        }
      }
    }
    .task {
      await state.bootstrap()
    }
  }

  @ToolbarContentBuilder
  private var settingsLink: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      NavigationLink {
        SettingsView()
      } label: {
        Image(systemName: "gearshape")
      }
    }
  }
}

#Preview {
  RootView()
    .environmentObject(AppState(secrets: MemorySecretStore()))
}
