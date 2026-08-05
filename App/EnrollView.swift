import SwiftUI
import PrismKit

/// First-run control-plane enrollment when no device key is in the Keychain.
struct EnrollView: View {
  @EnvironmentObject private var state: AppState

  var body: some View {
    Form {
      if let banner = state.banner {
        Section {
          Text(banner)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        SecureField("Enrollment token", text: $state.enrollmentToken)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button {
          Task { await state.enrollPlane() }
        } label: {
          if state.isBusy {
            ProgressView()
          } else {
            Text("Enroll this device")
              .frame(maxWidth: .infinity)
          }
        }
        .disabled(
          state.isBusy
            || state.enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      } header: {
        Text("Control plane")
      } footer: {
        Text(
          "Exchange a single-use enrollment token for a pcp_ device key. The key is stored in the Keychain and never shown again by the plane."
        )
      }

      Section {
        Text("Open Settings (gear) to paste an existing device key, change the plane URL, or switch back to the playground.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let err = state.errorMessage {
        Section {
          Text(err)
            .foregroundStyle(.red)
            .font(.footnote)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    EnrollView()
      .environmentObject(AppState(secrets: MemorySecretStore()))
  }
}
