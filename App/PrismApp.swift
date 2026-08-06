import SwiftUI

@main
struct PrismApp: App {
  @StateObject private var state = AppState()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(state)
        .onChange(of: scenePhase) { phase in
          guard phase == .active else { return }
          Task { await state.onBecomeActive() }
        }
    }
  }
}
