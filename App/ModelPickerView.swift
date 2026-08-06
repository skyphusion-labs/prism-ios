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

      if state.backend == .controlPlane {
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search models", text: $state.modelSearch)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if !state.modelSearch.isEmpty {
            Button {
              state.modelSearch = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
          }
        }
        .font(.footnote)
        Toggle("Hide unspendable", isOn: $state.hideUnspendable)
          .font(.caption)
      }

      if state.chatModels.isEmpty {
        Text(state.isBusy ? "Loading models…" : emptyCopy)
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
        if let sel = state.selectedModel {
          Text(sel.model)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
  }

  private var emptyCopy: String {
    if !state.modelSearch.isEmpty {
      return "No chat models match “\(state.modelSearch)”."
    }
    return "No chat models loaded. Check Settings / enroll."
  }

  private func label(for m: ModelEntry) -> String {
    var parts: [String] = []
    parts.append(m.label ?? m.model)
    if let p = m.priceLabel { parts.append(p) }
    if m.streaming == true { parts.append("SSE") }
    if let g = m.group, !g.isEmpty { parts.append(g) }
    if !m.isSpendable { parts.append("unspendable") }
    return parts.joined(separator: " · ")
  }
}
