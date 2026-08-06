import SwiftUI
import PrismKit

/// First-run plane path: welcome → enroll → tips → ready.
struct OnboardingView: View {
  @EnvironmentObject private var state: AppState
  @State private var step: Int = 0

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text(title)
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        switch step {
        case 0:
          welcome
        case 1:
          EnrollView()
          if state.deviceKeyPresent {
            Button("Continue") { step = 2 }
              .buttonStyle(.borderedProminent)
              .padding(.top, 8)
          }
        default:
          tips
        }

        Spacer()
        if state.showDeveloperSettings {
          Text("Developer options are on (playground available in Settings).")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .navigationTitle("Get started")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            SettingsView()
          } label: {
            Image(systemName: "gearshape")
              .accessibilityLabel("Settings")
          }
        }
      }
    }
  }

  private var title: String {
    switch step {
    case 0: return "Welcome to Prism"
    case 1: return "Enroll this device"
    default: return "You're set"
    }
  }

  @ViewBuilder
  private var welcome: some View {
    Text(
      "Commercial inference on the control plane: chat, image, video, audio, and music, metered to your prepaid account."
    )
    .font(.body)
    Text(
      "Chats stay on this device (the plane never stores prompts). You need a one-time enrollment token from the operator, or a recovery pcp_ device key."
    )
    .font(.body)
    .foregroundStyle(.secondary)
    VStack(alignment: .leading, spacing: 8) {
      bullet("Paste enrollment token or full pcp_ key from clipboard")
      bullet("Optional: top up with App Store credit packs after enroll")
      bullet("TestFlight builds use your personal Apple team")
    }
    Button("Continue to enroll") { step = 1 }
      .buttonStyle(.borderedProminent)
      .accessibilityLabel("Continue to enrollment")
  }

  @ViewBuilder
  private var tips: some View {
    Text("Quick start")
      .font(.title3.weight(.semibold))
    VStack(alignment: .leading, spacing: 10) {
      bullet("Chat: pick a model, Stream optional, attach photos for vision models")
      bullet("Image / Video tabs for generation; Seedance preferred for text-to-video")
      bullet("More → Usage for dual-pool balance; Settings → Top up for credit packs")
      bullet("Chats list: local sessions; Export in Settings for backup")
    }
    .font(.body)
    Text("You can open Settings anytime from the gear icon.")
      .font(.footnote)
      .foregroundStyle(.secondary)
    if state.deviceKeyPresent {
      Text("Device key stored. Open Chat to start.")
        .font(.footnote)
        .foregroundStyle(.green)
    }
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text("·")
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#Preview {
  OnboardingView()
    .environmentObject(AppState(secrets: MemorySecretStore()))
}
