import SwiftUI

@main
struct PrismApp: App {
  @StateObject private var state = AppState()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(state)
    }
  }
}
