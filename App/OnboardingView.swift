import SwiftUI
import PrismKit

/// First-run plane path: welcome → enroll → ready.
struct OnboardingView: View {
  @EnvironmentObject private var state: AppState
  @State private var step: Int = 0

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text("Welcome to Prism")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        if step == 0 {
          Text("Commercial inference on the control plane: chat, image, and video, metered to your account.")
            .font(.body)
          Text("You need a one-time enrollment token from the operator (or a pcp_ device key).")
            .font(.body)
            .foregroundStyle(.secondary)
          Button("Continue") { step = 1 }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue to enrollment")
        } else {
          EnrollView()
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
}

#Preview {
  OnboardingView()
    .environmentObject(AppState(secrets: MemorySecretStore()))
}
