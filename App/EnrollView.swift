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
          _ = state.pasteEnrollmentFromClipboard()
        } label: {
          Label("Paste from clipboard", systemImage: "doc.on.clipboard")
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Paste enrollment token or device key from clipboard")
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
          "Exchange a single-use enrollment token for a pcp_ device key. The key is stored in the Keychain and never shown again by the plane. If the clipboard already has a pcp_ key, Paste saves it directly."
        )
      }

      if let key = state.unsavedDeviceKey {
        Section {
          Text(key)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
          Button {
            state.copyUnsavedDeviceKeyToClipboard()
          } label: {
            Label("Copy device key", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: 44)
          }
          Button {
            Task { await state.retrySavingDeviceKey() }
          } label: {
            Text("Try saving to the Keychain again")
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: 44)
          }
        } header: {
          Text("Save this device key now")
        } footer: {
          Text(
            "Enrollment succeeded but the key could not be written to the Keychain. It works until you close the app; the enrollment token is spent and the plane will not show the key again. Copy it somewhere safe, then paste it back under Settings."
          )
        }
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
