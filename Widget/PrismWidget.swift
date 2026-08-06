import SwiftUI
import WidgetKit

/// Keep in sync with SecretStoreKeys.appGroupId / widget* keys in the main app.
private enum WidgetKeys {
  static let groupId = "group.org.skyphusion.prism"
  static let balance = "widget.balance"
  static let updatedAt = "widget.updatedAt"
}

/// Home-screen balance glance (reads App Group defaults written by the main app).
struct BalanceEntry: TimelineEntry {
  let date: Date
  let balance: String
  let updated: String
}

struct BalanceProvider: TimelineProvider {
  func placeholder(in context: Context) -> BalanceEntry {
    BalanceEntry(date: Date(), balance: "$0.0000 spendable", updated: "—")
  }

  func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
    completion(load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
    let entry = load()
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }

  private func load() -> BalanceEntry {
    let defaults = UserDefaults(suiteName: WidgetKeys.groupId)
    let bal = defaults?.string(forKey: WidgetKeys.balance) ?? "Open Prism to refresh"
    let updated = defaults?.string(forKey: WidgetKeys.updatedAt) ?? ""
    return BalanceEntry(date: Date(), balance: bal, updated: updated)
  }
}

private let widgetGradient = LinearGradient(
  colors: [
    Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255),
    Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255),
  ],
  startPoint: .topLeading,
  endPoint: .bottomTrailing
)

struct PrismWidgetEntryView: View {
  var entry: BalanceEntry

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding()
      .widgetChrome()
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Prism")
        .font(.headline)
        .foregroundStyle(.white.opacity(0.9))
      Text(entry.balance)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .minimumScaleFactor(0.7)
        .lineLimit(3)
      if !entry.updated.isEmpty {
        Text(entry.updated)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.7))
      }
    }
  }
}

private extension View {
  @ViewBuilder
  func widgetChrome() -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(for: .widget) { widgetGradient }
    } else {
      self.background(widgetGradient)
    }
  }
}

@main
struct PrismWidget: Widget {
  let kind = "PrismBalanceWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
      PrismWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Prism balance")
    .description("Spendable credit from your last refresh in the app.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
