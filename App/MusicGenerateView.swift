import SwiftUI
import PrismKit
#if canImport(UIKit)
import UIKit
#endif

/// Control-plane music generation (`POST /v1/music/generations`).
struct MusicGenerateView: View {
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
            Text("Control plane + device key required. Enroll in Settings.")
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
            get: { state.selectedMusicModelId ?? state.musicModels.first?.model ?? "" },
            set: { state.selectMusicModel($0) }
          )) {
            ForEach(state.musicModels) { m in
              Text(shortLabel(m)).tag(m.model)
            }
          }
          if let id = state.selectedMusicModelId ?? state.musicModels.first?.model {
            Text(id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if state.musicModels.isEmpty, state.canUseMediaDoors {
            Text("No music models match. Clear search or refresh models.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        } header: {
          Text("Model")
        }

        Section {
          TextField("Music prompt", text: $state.musicPrompt, axis: .vertical)
            .lineLimit(2...6)
            .font(.body)
            .accessibilityLabel("Music prompt")
          TextField("Optional lyrics", text: $state.musicLyrics, axis: .vertical)
            .lineLimit(2...8)
            .font(.body)
            .accessibilityLabel("Optional lyrics")
          if let preview = state.musicSpendPreview {
            Text(preview).font(.footnote).foregroundStyle(.secondary)
          }
          if state.musicBusy {
            HStack {
              ProgressView()
              Text(state.musicStatus ?? "Generating…").font(.footnote).foregroundStyle(.secondary)
            }
            Button(role: .destructive) { state.cancelMusic() } label: {
              Text("Cancel").frame(maxWidth: .infinity).frame(minHeight: 44)
            }
          } else {
            Button { state.generateMusic() } label: {
              Text("Generate music").frame(maxWidth: .infinity).frame(minHeight: 44)
            }
            .disabled(!state.canUseMediaDoors || state.musicModels.isEmpty
              || state.musicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        } header: {
          Text("Prompt")
        } footer: {
          Text("Unit-priced per request. Long runs may take a minute.")
        }

        if let status = state.musicStatus {
          Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }
        if let err = state.musicError {
          Section { Text(err).font(.footnote).foregroundStyle(.red) }
        }

        if state.lastMusicData != nil || state.lastMusicAudio != nil {
          Section {
            if state.lastMusicData != nil {
              Button { state.playLastMusic() } label: {
                Label("Play", systemImage: "play.circle.fill")
                  .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
              }
            }
            if let urlStr = state.lastMusicAudio, let url = URL(string: urlStr),
               url.scheme?.hasPrefix("http") == true
            {
              Link("Open audio URL", destination: url)
              Text(urlStr).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            #if canImport(UIKit)
            Button {
              if let data = state.lastMusicData {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-music.mp3")
                try? data.write(to: url)
                sharePayload = SharePayload(items: [url])
              } else if let s = state.lastMusicAudio, let url = URL(string: s) {
                sharePayload = SharePayload(items: [url])
              }
            } label: {
              Label("Share", systemImage: "square.and.arrow.up")
            }
            #endif
            if let model = state.lastMusicModel {
              Text(model).font(.caption2).foregroundStyle(.secondary)
            }
          } header: {
            Text("Result")
          }
        }
      }
    }
    .navigationTitle("Music")
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
    MusicGenerateView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
