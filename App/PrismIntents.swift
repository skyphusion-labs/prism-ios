import AppIntents
import Foundation

/// Shortcuts: open Prism surfaces without going through a full UI hunt.
@available(iOS 16.0, *)
struct OpenChatIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Prism Chat"
  static var description = IntentDescription("Open the Prism chat tab.")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    .result()
  }
}

@available(iOS 16.0, *)
struct OpenUsageIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Prism Usage"
  static var description = IntentDescription("Open dual-pool usage and spend detail.")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    .result()
  }
}

@available(iOS 16.0, *)
struct NewChatIntent: AppIntent {
  static var title: LocalizedStringResource = "New Prism Chat"
  static var description = IntentDescription("Start a new chat session in Prism.")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    .result()
  }
}

@available(iOS 16.0, *)
struct PrismAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenChatIntent(),
      phrases: [
        "Open \(.applicationName) chat",
        "Chat in \(.applicationName)",
      ],
      shortTitle: "Chat",
      systemImageName: "bubble.left.and.bubble.right"
    )
    AppShortcut(
      intent: OpenUsageIntent(),
      phrases: [
        "Show \(.applicationName) usage",
        "Check \(.applicationName) balance",
      ],
      shortTitle: "Usage",
      systemImageName: "chart.bar"
    )
    AppShortcut(
      intent: NewChatIntent(),
      phrases: [
        "New \(.applicationName) chat",
        "Start a chat in \(.applicationName)",
      ],
      shortTitle: "New chat",
      systemImageName: "plus.bubble"
    )
  }
}
