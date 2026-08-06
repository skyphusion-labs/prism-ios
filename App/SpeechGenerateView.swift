import SwiftUI
import PrismKit
#if canImport(UIKit)
import UIKit
#endif

/// Control-plane text-to-speech (`POST /v1/audio/speech`).
struct SpeechGenerateView: View {
  @EnvironmentObject private var state: AppState
  @State private var sharePayload: SharePayload?

  var body: some View {
    VStack(spacing: 0) {
      if let banner = state.banner {
        Text(banner)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 6)
      }

      Form {
        if !state.canUseMediaDoors {
          Section {
            Text("Switch to Control plane and enroll (or paste a pcp_ key) in Settings. Speech is plane-only.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          if state.backend == .controlPlane {
            TextField("Search models", text: $state.modelSearch)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          Picker("Model", selection: Binding(
            get: { state.selectedSpeechModelId ?? state.speechModels.first?.model ?? "" },
            set: { state.selectSpeechModel($0) }
          )) {
            ForEach(state.speechModels) { m in
              Text(shortLabel(m)).tag(m.model)
            }
          }
          if let id = state.selectedSpeechModelId ?? state.speechModels.first?.model {
            Text(id)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          if state.speechModels.isEmpty, state.canUseMediaDoors {
            Text("No TTS models match. Clear search or refresh models in Settings.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Model")
        }

        Section {
          TextField("Text to speak", text: $state.speechText, axis: .vertical)
            .lineLimit(3...12)
            .font(.body)
            .accessibilityLabel("Text to speak")

          if let preview = state.speechSpendPreview {
            Text(preview)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if state.speechBusy {
            HStack {
              ProgressView()
              Text(state.speechStatus ?? "Synthesizing…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
              state.cancelSpeech()
            } label: {
              Text("Cancel")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
          } else {
            Button {
              state.generateSpeech()
            } label: {
              Text("Generate speech")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .disabled(!state.canUseMediaDoors || state.speechModels.isEmpty
              || state.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Generate speech")
          }
        } header: {
          Text("Input")
        } footer: {
          Text("Aura-2 is billed per 1k characters; MeloTTS per audio minute (plane floors at 1 unit). Audio plays automatically when ready.")
        }

        if let status = state.speechStatus {
          Section {
            Text(status).font(.footnote).foregroundStyle(.secondary)
          }
        }
        if let err = state.speechError {
          Section {
            Text(err).font(.footnote).foregroundStyle(.red)
          }
        }

        if state.lastSpeechData != nil {
          Section {
            Button {
              state.playLastSpeech()
            } label: {
              Label("Play", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Play speech audio")

            #if canImport(UIKit)
            Button {
              if let data = state.lastSpeechData {
                let name = "prism-speech.\(state.lastSpeechFormat)"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: url)
                sharePayload = SharePayload(items: [url])
              }
            } label: {
              Label("Share audio", systemImage: "square.and.arrow.up")
            }
            #endif

            if let model = state.lastSpeechModel {
              Text(model).font(.caption2).foregroundStyle(.secondary)
            }
          } header: {
            Text("Result")
          }
        }
      }
    }
    .navigationTitle("Speech")
    .sheet(item: $sharePayload) { payload in
      ActivityView(items: payload.items)
    }
  }

  private func shortLabel(_ m: ModelEntry) -> String {
    var parts = [m.label ?? m.model]
    if let p = m.priceLabel { parts.append(p) }
    return parts.joined(separator: " · ")
  }
}

private struct SharePayload: Identifiable {
  let id = UUID()
  let items: [Any]
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
  NavigationStack {
    SpeechGenerateView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
