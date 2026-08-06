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
        Toggle("Stream", isOn: Binding(
          get: { state.useStream },
          set: { state.setUseStream($0) }
        ))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityLabel("Stream responses")
        Text("Stream")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if state.backend == .controlPlane {
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
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
            .accessibilityLabel("Clear model search")
          }
        }
        .font(.footnote)
        Toggle("Hide unspendable", isOn: Binding(
          get: { state.hideUnspendable },
          set: { state.setHideUnspendable($0) }
        ))
          .font(.caption)
      }

      if state.chatModels.isEmpty {
        Text(state.isBusy ? "Loading models…" : emptyCopy)
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        // Selection writes via selectChatModel so we never clear chat context.
        Picker("Model", selection: Binding(
          get: {
            // Prefer the real selection even if filtered out of the menu.
            if let id = state.selectedModelId { return id }
            return state.chatModels[0].model
          },
          set: { state.selectChatModel($0) }
        )) {
          // Keep the currently selected model visible even when search would hide it.
          if let sel = state.selectedModel,
             !state.chatModels.contains(where: { $0.model == sel.model })
          {
            Text(label(for: sel) + " (selected)").tag(sel.model)
          }
          ForEach(state.chatModels) { m in
            Text(label(for: m)).tag(m.model)
          }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Chat model")
        .accessibilityHint("Changing model keeps the same conversation")

        if let sel = state.selectedModel {
          Text(sel.model)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          if !sel.capabilityTags.isEmpty {
            Text(sel.capabilityTags.joined(separator: " · "))
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .accessibilityLabel("Capabilities \(sel.capabilityTags.joined(separator: ", "))")
          }
        }
        if let preview = state.chatSpendPreview {
          Text(preview)
            .font(.caption2)
            .foregroundStyle(
              (!state.draftImageDataUrls.isEmpty && state.selectedModel?.supportsVision != true)
                ? Color.orange : Color.secondary
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(preview)
        }
      }

      if state.chatContextTurnCount > 0 {
        Text(
          "\(state.chatContextTurnCount) turn\(state.chatContextTurnCount == 1 ? "" : "s") in this chat · switch models anytime; context is kept until New chat"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Conversation keeps context when you change models")
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
    parts.append(contentsOf: m.capabilityTags)
    return parts.joined(separator: " · ")
  }
}
