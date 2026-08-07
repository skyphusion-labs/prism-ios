import SwiftUI

/// SkyPhusion Labs brand blue (logo gradient start `#1d4ed8`).
private let skyphusionAccent = Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255)

@main
struct PrismApp: App {
  @UIApplicationDelegateAdaptor(PrismAppDelegate.self) private var appDelegate
  @StateObject private var state = AppState()
  /// Owned by the app, not by Settings.
  ///
  /// `StoreManager.init` starts the `Transaction.updates` listener, so whoever owns the object
  /// decides how long the app is listening for StoreKit deliveries. While it was a `@StateObject`
  /// of `SettingsView`, the app listened only while Settings existed, and the plane redeem
  /// handler was attached only from that screen's `onAppear`. A purchase delivered at any other
  /// moment had nowhere to go. See prism-ios#49 F5.
  @StateObject private var store = StoreManager()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()
          .environmentObject(state)
          .environmentObject(store)

        // The biometric lock re-locks on `.background` (deliberately, so the Face ID sheet does
        // not re-trigger it), but iOS captures the app-switcher snapshot on the way out through
        // `.inactive`, where nothing runs. Cover the window there instead, so the switcher card
        // and the snapshot iOS writes into the container show the shield and not the last
        // conversation. The lock itself is unchanged.
        if state.biometricLockEnabled, scenePhase != .active {
          PrivacyCoverView()
        }
      }
      .tint(skyphusionAccent)
      .task {
        // Attach the plane redeem path once, for the app's lifetime, then sweep anything
        // StoreKit is still holding: a transaction left unfinished on a previous run (or
        // delivered before this handler existed) is retried here rather than waiting for the
        // user to open Settings.
        store.redeemHandler = { jws in
          try await state.redeemStoreTransaction(jws: jws)
        }
        store.onRedeemed = {
          await state.refreshModels()
        }
        await store.redeemUnfinished()
      }
      .onChange(of: scenePhase) { phase in
        switch phase {
        case .background:
          // Re-lock only when fully backgrounded (not Face ID sheet inactive).
          // Does not cancel long gens; iOS may still suspend the network wait.
          state.lockIfNeeded()
        case .active:
          Task { await state.onBecomeActive() }
        default:
          break
        }
      }
    }
  }
}

/// Opaque cover drawn while the app is not active and the biometric lock is on.
///
/// Deliberately carries no state and no content: its whole job is that the snapshot iOS takes
/// contains nothing.
private struct PrivacyCoverView: View {
  var body: some View {
    ZStack {
      Rectangle()
        .fill(.background)
        .ignoresSafeArea()
      Image(systemName: "lock.shield")
        .font(.system(size: 44))
        .foregroundStyle(.secondary)
    }
    .accessibilityHidden(true)
  }
}
