import SwiftUI
import PrismKit

struct ModelPickerView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Model")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        Toggle("Stream", isOn: $state.useStream)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
        Text("Stream")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if state.chatModels.isEmpty {
        Text(state.isBusy ? "Loading models…" : "No chat models loaded. Check Settings / base URL.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        Picker("Model", selection: Binding(
          get: { state.selectedModelId ?? state.chatModels[0].model },
          set: { state.selectedModelId = $0 }
        )) {
          ForEach(state.chatModels) { m in
            Text(label(for: m)).tag(m.model)
          }
        }
        .pickerStyle(.menu)
      }
    }
  }

  private func label(for m: ModelEntry) -> String {
    var parts: [String] = []
    parts.append(m.label ?? m.model)
    if m.streaming == true { parts.append("SSE") }
    if let p = m.provider, !p.isEmpty { parts.append(p) }
    return parts.joined(separator: " · ")
  }
}
