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
        OnboardingView()
      } else if state.backend == .controlPlane {
        // Primary doors on the bar; Audio/Music under More (readable tab bar).
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

          NavigationStack {
            MoreHubView()
              .toolbar { settingsLink }
          }
          .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
      } else {
        NavigationStack {
          ChatView()
            .navigationTitle("Prism")
            .toolbar { settingsLink }
        }
      }
    }
    .overlay(alignment: .top) {
      if !state.isNetworkSatisfied, state.needsPlaneEnroll || state.needsPlaygroundLogin {
        Text("Offline")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(Color.orange)
          .accessibilityLabel("No network connection")
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
