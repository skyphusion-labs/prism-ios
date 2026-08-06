import SwiftUI

/// SkyPhusion Labs brand blue (logo gradient start `#1d4ed8`).
private let skyphusionAccent = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)

@main
struct PrismApp: App {
  @StateObject private var state = AppState()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(state)
        .tint(skyphusionAccent)
        .onChange(of: scenePhase) { phase in
          guard phase == .active else { return }
          Task { await state.onBecomeActive() }
        }
    }
  }
}
