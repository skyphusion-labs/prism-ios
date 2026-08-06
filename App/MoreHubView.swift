import SwiftUI
import PrismKit

/// Secondary doors + status, so the main tab bar stays Chat / Image / Video / More.
struct MoreHubView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    List {
      Section {
        NavigationLink {
          SpeechGenerateView()
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Audio")
              Text("Text-to-speech and speech-to-text")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "waveform")
          }
          .frame(minHeight: 44)
        }
        .accessibilityLabel("Audio, text to speech and speech to text")

        NavigationLink {
          MusicGenerateView()
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Music")
              Text("Prompted music generation")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "music.note")
          }
          .frame(minHeight: 44)
        }
        .accessibilityLabel("Music generation")
      } header: {
        Text("Generate")
      }

      Section {
        if state.deviceKeyPresent {
          if let bal = state.planeBalance, !bal.isEmpty {
            LabeledContent("Balance", value: bal)
          }
          if !state.planeUsageLines.isEmpty {
            ForEach(state.planeUsageLines, id: \.self) { line in
              Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          LabeledContent("Plane health", value: state.planeHealthLabel)
        } else {
          Text("Enroll a device key to use metered doors.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Button {
          Task { await state.refreshModels() }
        } label: {
          Label("Refresh catalog / balance", systemImage: "arrow.clockwise")
            .frame(minHeight: 44)
        }
      } header: {
        Text("Account")
      }

      Section {
        NavigationLink {
          SettingsView()
        } label: {
          Label("Settings", systemImage: "gearshape")
            .frame(minHeight: 44)
        }
        LabeledContent("Kit", value: "\(PrismKit.name) \(PrismKit.version)")
      } header: {
        Text("App")
      } footer: {
        Text("Chat, Image, and Video stay on the tab bar. Audio and Music live here so the bar stays readable.")
      }
    }
    .navigationTitle("More")
  }
}

#Preview {
  NavigationStack {
    MoreHubView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
