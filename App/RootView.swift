import SwiftUI
import PrismKit

struct RootView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    Group {
      if state.isBiometricallyLocked {
        BiometricLockView()
      } else if state.needsPlaygroundLogin {
        NavigationStack {
          LoginView()
            .navigationTitle("Prism")
            .toolbar { settingsLink }
        }
      } else if state.needsPlaneEnroll {
        OnboardingView()
      } else if state.backend == .controlPlane {
        // Primary doors on the bar; Audio/Music under More (readable tab bar).
        // `selectedTab` enables Image/Video → Chat handoffs without a second gesture.
        TabView(selection: $state.selectedTab) {
          NavigationStack {
            ChatView()
              .navigationTitle("Chat")
              .toolbar { settingsLink }
          }
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(AppMainTab.chat)

          NavigationStack {
            MediaGenerateView(kind: .image)
              .toolbar { settingsLink }
          }
          .tabItem { Label("Image", systemImage: "photo") }
          .tag(AppMainTab.image)

          NavigationStack {
            MediaGenerateView(kind: .video)
              .toolbar { settingsLink }
          }
          .tabItem { Label("Video", systemImage: "film") }
          .tag(AppMainTab.video)

          NavigationStack {
            MoreHubView()
              .toolbar { settingsLink }
          }
          .tabItem { Label("More", systemImage: "ellipsis.circle") }
          .tag(AppMainTab.more)
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

/// Full-screen Face ID / Touch ID gate before the enrolled session is visible.
private struct BiometricLockView: View {
  @EnvironmentObject private var state: AppState
  @State private var busy = false

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 56))
        .foregroundStyle(Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255))
        .accessibilityHidden(true)
      Text("Prism is locked")
        .font(.title2.weight(.semibold))
      Text("Use \(BiometricLock.biometryLabel) to unlock your enrolled session.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Button {
        Task {
          busy = true
          await state.unlockWithBiometrics()
          busy = false
        }
      } label: {
        if busy {
          ProgressView()
            .frame(minWidth: 160, minHeight: 44)
        } else {
          Label("Unlock with \(BiometricLock.biometryLabel)", systemImage: "faceid")
            .frame(minWidth: 160, minHeight: 44)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(busy)
      .accessibilityLabel("Unlock Prism")
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .task {
      // Auto-prompt once on appear so unlock is one glance, not two taps.
      await state.unlockWithBiometrics()
    }
  }
}

#Preview {
  RootView()
    .environmentObject(AppState(secrets: MemorySecretStore()))
}
